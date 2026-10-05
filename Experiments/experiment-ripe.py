'''
Sends 25 requests for test%d.example.local
'''

import os
import argparse
import dns.resolver
import pandas as pd
import time

from time import sleep
from dotenv import load_dotenv
from datetime import datetime, timedelta
from ripe.atlas.cousteau import (
  Dns,
  Measurement,
  AtlasSource,
  AtlasCreateRequest,
  AtlasLatestRequest
)
from get_ripe_results import get_results_with_metadata, get_measurements_with_metadata, save_to_csv

load_dotenv()
ATLAS_API_KEY = os.getenv("ATLAS_API_KEY")


def poll_results_with_timeout(ids, label, algorithm, strategy, timeout=300, initial_interval=5):
    """
    Polls for results with a timeout and exponential backoff.
    Args:
        ids: List of measurement IDs.
        label: Label for the measurement.
        algorithm: Algorithm used.
        strategy: Strategy used.
        timeout: Maximum time to wait (in seconds).
        initial_interval: Initial polling interval (in seconds).
    Returns:
        Tuple of (df_measurements, df_results) or (None, None) if timeout occurs.
    """
    start_time = time.time()
    current_interval = initial_interval
    max_interval = 30  # Maximum polling interval (in seconds)
    
    while time.time() - start_time < timeout:
        (df_measurements, df_results) = get_results_with_metadata(ids, label, algorithm, strategy)
        if df_measurements is not None and df_results is not None:
            return (df_measurements, df_results)
        
        # Exponential backoff with a cap
        print(f"No results yet. Waiting for {current_interval} seconds...")
        sleep(current_interval)
        current_interval = min(current_interval * 2, max_interval)
    
    print(f"Timeout reached after {timeout} seconds. No results obtained.")
    return (None, None)


'''
run a measurement, wait until the results are in, and return results
'''
def run_measurement(nr_sources, resolver, domain, description, label, algorithm, strategy, country, reuse_probes_msm_id, probes):
    if len(probes) > 0:
        print("Using %d probes from list %s" % (nr_sources, probes))
        source = AtlasSource(
            type="probes",
            value=",".join(map(str, probes)),
            requested=len(probes)
        )
    elif reuse_probes_msm_id > 0:
        print("Using %d probes from measurement %d" % (nr_sources, reuse_probes_msm_id))
        source = AtlasSource(
            type="msm",
            value=reuse_probes_msm_id,
            requested=nr_sources
        )
    elif country == "WW":
        print("Using %d random probes world-wide" % (nr_sources))
        source = AtlasSource(
            type="area",
            value="WW",
            requested=nr_sources,
            tags={"include":["system-ipv4-works", "system-ipv4-stable-30d"], "exclude": ["system-v2", "system-v1"]}
            #tags={"include":["system-ipv4-works", "system-ipv4-stable-30d", "system-v2"]}
        )
    else:
        print("Using %d random probes from country %s" % (nr_sources, country))
        source = AtlasSource(
            type="countries",
            value=country.split(","),
            requested=nr_sources,
            tags={"include":["system-ipv4-works", "system-ipv4-stable-30d"], "exclude": ["system-v2", "system-v1"]}
            #tags={"include":["system-ipv4-works", "system-ipv4-stable-30d", "system-v2"]}
        )
    measurement = Dns(
        af=4,
        description=description,
        query_class="IN",
        query_type="A",
        query_argument=domain,
        target=resolver,
        use_probe_resolver=False,
        set_rd_bit=True,
        set_nsid_bit=True,
        udp_payload_size=1232,
    )
    # send request
    atlas_request = AtlasCreateRequest(
        key=ATLAS_API_KEY,
        measurements=[measurement],
        sources=[source],
        is_oneoff=True
    )
    (is_success, response) = atlas_request.create()
    if is_success:
        ids = response["measurements"]
        print("Success! Collecting results for %s!" % (ids))
        # Use the improved polling mechanism
        (df_measurements, df_results) = poll_results_with_timeout(ids, label, algorithm, strategy, timeout=300, initial_interval=5)
        if df_measurements is None or df_results is None:
            return (None, None, None)
    else:
        print("Request failed: %s" % (response))
        return (None, None, None)
    return (df_measurements, df_results, ids)


'''
runs the experiments but waits for each measurement to complete before starting the next one
prevents that the servers need to handle more than one request at a time
when one-by-one is true, it only does measurements with 1 probe at a time
'''
def run_experiment_wait(nr_sources, nr_queries, resolver, domain, description, label, algorithm, strategy, country, reuse_probes_msm_id=0, probes=[], one_by_one=True):
    description = "%s {\"algorithm\": \"%s\", \"strategy\": \"%s\", \"label\": \"%s\"}" % (description, algorithm, strategy, label)
    dfs_measurements = []
    dfs_results = []
    delta = nr_queries
    if probes != [] and len(probes) != nr_sources:
        print("When providing probes, make sure they equal nr_sources!")
        return
    if one_by_one:
        delta = 1
    print("running experiments with delta %d" % (delta))
    for i in range(0, nr_sources, delta):
        # sel_probes is the same as probes if one_by_one is false
        # if one_by_one is true, we try to select probes[i]
        sel_probes = []
        if one_by_one:
            try:
                sel_probes.append(probes[i])
            except:
                None
        else:
            sel_probes = probes
        (df_measurements, df_results, ids) = run_measurement(delta, resolver, domain, description, label, algorithm, strategy, country, reuse_probes_msm_id, sel_probes)
        if df_measurements is None or df_results is None or len(ids) != 1:
            print("dataframes should not be empty")
            return
        # to make sure we use the same probe for future measurements
        reuse_msm_id = ids[0]
        dfs_measurements.append(df_measurements)
        dfs_results.append(df_results)
        prefix, suffix = domain.split(".", 1)
        for i in range(nr_queries):
            newdomain = "%s%d.%s" % (prefix, i, suffix)
            (df_measurements, df_results, ids) = run_measurement(delta, resolver, newdomain, description, label, algorithm, strategy, country, reuse_msm_id, sel_probes)
            if df_measurements is None or df_results is None:
                print("dataframes should not be empty")
            else:
                dfs_measurements.append(df_measurements)
                dfs_results.append(df_results)
    # combine all the dataframes and write it to a CSV file
    timestamp = pd.Timestamp.now().strftime("%Y-%m-%d_%H-%M-%S")
    # save measurements
    df_measurements = pd.concat([x for x in dfs_measurements], ignore_index=True)
    csv = df_measurements.to_csv(index=False)
    save_to_csv(csv, timestamp, "measurements-%s" % label, strategy, algorithm)
    # save results
    df_results = pd.concat([x for x in dfs_results], ignore_index=True)
    csv = df_results.to_csv(index=False)
    save_to_csv(csv, timestamp, label, strategy, algorithm)

'''
runs the experiment
in order of preference uses the following probes:
1. specified by `probes` array
2. reuses probes used in measurement `reuse_probes_msm_id`
3. randomly selects probes from given country
'''
def run_experiment(nr_sources, nr_queries, resolver, domain, description, label, algorithm, strategy, country, reuse_probes_msm_id=0, probes=[]):
    description = "%s {\"algorithm\": \"%s\", \"strategy\": \"%s\", \"label\": \"%s\"}" % (description, algorithm, strategy, label)
    sources = []
    if len(probes) > 0:
        source = AtlasSource(
            type="probes",
            value=",".join(map(str, probes)),
            requested=len(probes)
        )
        sources.append(source)
    elif reuse_probes_msm_id > 0:
        source = AtlasSource(
            type="msm",
            value=reuse_probes_msm_id,
            requested=nr_sources
        )
        sources.append(source)
    elif country == "WW":
        source = AtlasSource(
            type="area",
            value="WW",
            requested=nr_sources,
            tags={"include":["system-ipv4-works", "system-ipv4-stable-30d"], "exclude": ["system-v2", "system-v1"]}
            #tags={"include":["system-ipv4-works", "system-ipv4-stable-30d", "system-v2"]}
        )
        sources.append(source)
    elif country == "South-East":
        source = AtlasSource(
            type="area",
            value="South-East",
            requested=nr_sources,
            tags={"include":["system-ipv4-works", "system-ipv4-stable-30d"], "exclude": ["system-v2", "system-v1"]}
            #tags={"include":["system-ipv4-works", "system-ipv4-stable-30d", "system-v2"]}
        )
        sources.append(source)
    else:
        countries = country.split(",")
        n = int(nr_sources / len(countries))
        r = nr_sources % len(countries)
        for index, c in enumerate(countries):
            if index == (len(countries) - 1):
                n = n + r
            source = AtlasSource(
                type="country",
                value=c.strip(),
                requested=n,
                tags={"include":["system-ipv4-works", "system-ipv4-stable-30d"], "exclude": ["system-v2", "system-v1"]}
                #tags={"include":["system-ipv4-works", "system-ipv4-stable-30d", "system-v2"]}
            )
            sources.append(source)
    prefix, suffix = domain.split(".", 1)
    measurements=[]
    # add domain, we can exclude it later (for caching)
    measurements.append(Dns(
        af=4,
        description=description,
        query_class="IN",
        query_type="A",
        query_argument=domain,
        target=resolver,
        use_probe_resolver=False,
        set_rd_bit=True,
        set_nsid_bit=True,
        udp_payload_size=1232,
    ))
    for i in range(nr_queries):
        newdomain = "%s%d.%s" % (prefix, i, suffix)
        measurements.append(Dns(
            af=4,
            description=description,
            query_class="IN",
            query_type="A",
            query_argument=newdomain,
            target=resolver,
            use_probe_resolver=False,
            set_rd_bit=True,
            set_nsid_bit=True,
            udp_payload_size=1232,
        ))

    atlas_request = AtlasCreateRequest(
        key=ATLAS_API_KEY,
        measurements=measurements,
        sources=sources,
        is_oneoff=True
    )

    (is_success, response) = atlas_request.create()
    if is_success:
        ids = response["measurements"]
        print("Success! Saving %d ids %s to CSV!" % (len(ids), ids))
        # Use the improved polling mechanism
        (df_measurements, df_results) = poll_results_with_timeout(ids, label, algorithm, strategy, timeout=300, initial_interval=10)
        if df_measurements is not None and df_results is not None:
            timestamp = pd.Timestamp.now().strftime("%Y-%m-%d_%H-%M-%S")
            csv = df_measurements.to_csv(index=False)
            save_to_csv(csv, timestamp, "measurements-%s" % label, strategy, algorithm)
            csv = df_results.to_csv(index=False)
            save_to_csv(csv, timestamp, label, strategy, algorithm)
        else:
            print("Failed to collect results within the timeout period.")
    else:
        print("Request failed: %s" % (response))

def main():

    parser = argparse.ArgumentParser(description="Executes Experiments for Hydra DNS on RIPE Atlas")

    # Required arguments
    parser.add_argument("-r", "--resolver", required=True, help="DNS resolver IP or hostname")
    parser.add_argument("-p", "--port", type=int, default=53, help="Port number (default: 53)")
    parser.add_argument("-l", "--label", required=True, help="Label for the query")
    parser.add_argument("-a", "--algorithm", required=True, help="Algorithm to use")
    parser.add_argument("-s", "--strategy", required=True, help="Strategy to use")

    # Optional arguments
    parser.add_argument("-d", "--description", help="Description for the query (default: [Hydra DNS])", default="[Hydra DNS]")
    parser.add_argument("-c", "--country", help="Country code (default: WW)", default="WW")
    parser.add_argument("-w", "--wait", action="store_true", help="Indicates if we should wait for measurements or not (default: False)")
    parser.add_argument("-n", "--nr_sources", type=int, help="Number of sources (default: 5)", default=5)
    parser.add_argument("-q", "--nr_queries", type=int, help="Number of queries (default: 20)", default=20)
    parser.add_argument("-f", "--frequency", type=int, help="Frequency in seconds (default: 0)", default=0)
    parser.add_argument("--spread", type=int, help="Spread in seconds (must be > 1 and < frequency)", default=None)
    parser.add_argument("--repeat", type=int, help="Number of repetitions (calculates end_date as start_date + (frequency * repeat))", default=None)
    parser.add_argument("--reuse_id", type=int, help="Reuses probes from this measurement (default: 0)", default=0)
    parser.add_argument("--probes", type=str, help='Comma-separated list of Probe IDs to use')
    parser.add_argument("--start_date", help="Start date (default: now)", default=datetime.now().isoformat())
    parser.add_argument("--end_date", help="End date (default: now + 1 day)", default=None)
    parser.add_argument("--domain", help="Domain to query")

    args = parser.parse_args()
    if not hasattr(args, 'domain') or args.domain is None:
        args.domain = "test.%s-%s.test" % (args.algorithm.lower().replace("_", "-"), args.label.lower().replace("_", "-"))

    # Validate and calculate spread and repeat
    if args.spread is not None:
        if args.spread <= 1:
            parser.error("--spread must be greater than 1")
        if args.frequency <= args.spread:
            parser.error("--spread must be less than --frequency")
    
    # Calculate end_date if repeat is provided
    if args.repeat is not None:
        if args.frequency <= 0:
            parser.error("--repeat requires --frequency to be greater than 0")
        start_date = datetime.fromisoformat(args.start_date)
        args.end_date = (start_date + timedelta(seconds=args.frequency * args.repeat)).isoformat()
    elif args.end_date is None:
        args.end_date = (datetime.now() + timedelta(days=1)).isoformat()

    # Print configuration
    print("Configuration:")
    print(f"  Resolver:    {args.resolver}")
    print(f"  Port:        {args.port}")
    print(f"  Label:       {args.label}")
    print(f"  Description: {args.description}")
    print(f"  Algorithm:   {args.algorithm}")
    print(f"  Strategy:    {args.strategy}")
    print(f"  Domain:      {args.domain}")
    print(f"  Country:     {args.country}")
    print(f"  Wait for measurements to finish:        {args.wait}")
    print(f"  Nr. Sources: {args.nr_sources}")
    print(f"  Nr. Queries: {args.nr_queries}")
    print(f"  Probes Measurement ID: {args.reuse_id}")
    print(f"  Probe IDs: {args.probes}")
    if args.frequency > 0:
        print(f"  Frequency:   {args.frequency}")
        print(f"  Start Date:  {args.start_date}")
        print(f"  End Date:    {args.end_date}")
        if args.spread is not None:
            print(f"  Spread:      {args.spread}")
        if args.repeat is not None:
            print(f"  Repeat:      {args.repeat}")
    else:
        print(f"  Frequency:   One-off")
    # Ask user to confirm
    user_input = input("Press Y/y to confirm and run the experiment: ")
    if user_input.lower() == 'y':
        
        try:
            # resolve so that the ns can be cached
            custom_resolver = dns.resolver.Resolver()
            custom_resolver.nameservers = [args.resolver]
            custom_resolver.resolve(args.domain, 'A')
        except Exception as e:
            print(f"  DNS Resolution failed: {e}")
        sleep(1)
        probe_ids = []
        try:
            probe_ids = [int(x.strip()) for x in args.probes.split(",")]
        except:
            None
        if args.wait:
            run_experiment_wait(
                nr_sources=args.nr_sources,
                nr_queries=args.nr_queries,
                resolver=args.resolver,
                domain=args.domain,
                description=args.description,
                label=args.label,
                algorithm=args.algorithm,
                strategy=args.strategy,
                country=args.country,
                reuse_probes_msm_id=args.reuse_id,
                probes=probe_ids
            )
        else:
            run_experiment(
                nr_sources=args.nr_sources,
                nr_queries=args.nr_queries,
                resolver=args.resolver,
                domain=args.domain,
                description=args.description,
                label=args.label,
                algorithm=args.algorithm,
                strategy=args.strategy,
                country=args.country,
                reuse_probes_msm_id=args.reuse_id,
                probes=probe_ids
            )
    else:
        print("Experiment cancelled by user")

if __name__ == "__main__":
    main()
