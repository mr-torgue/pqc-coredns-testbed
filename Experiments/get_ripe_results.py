import argparse
import json
import pandas as pd
import base64
import dns.message

from ripe.atlas.cousteau import (
  AtlasLatestRequest,
  AtlasRequest,
  AtlasResultsRequest,
  Measurement
)
from collections import namedtuple

'''
writes the file to a CSV
'''
def save_to_csv(csv, timestamp, label, strategy, algorithm):
    filename = ""
    if label != "":
        filename = "%s%s-" % (filename, label)
    if strategy != "":
        filename = "%s%s-" % (filename, strategy)
    if algorithm != "":
        filename = "%s%s-" % (filename, algorithm)
    filename = "%s%s.csv" % (filename, timestamp)
    with open(filename, 'w') as f:
        f.write(csv)

'''
parses the description, which should be in format [Hydra DNS] {"algorithm": x, "strategy": y, "label": z}
'''
def parse_description(description):
    # check if algorithm, strategy, and label are set
    algorithm = ""
    strategy = ""
    label = ""

    # Extract JSON part from description
    json_start = description.find('{')
    json_end = description.rfind('}') + 1
    if json_start != -1 and json_end != -1:
        json_str = description[json_start:json_end]
        try:
            metadata = json.loads(json_str)
            algorithm = metadata.get("algorithm", "")
            strategy = metadata.get("strategy", "")
            label = metadata.get("label", "")
        except json.JSONDecodeError:
            pass

    return algorithm, strategy, label

'''
parses the abuf if available so that we know the domain name and rcode
'''
def parse_dns_message(encoded_msg):
    try:
        binary_msg = base64.b64decode(encoded_msg)
        msg = dns.message.from_wire(binary_msg)
        qname = msg.question[0].name.to_text() if msg.question else None
        rcode = msg.rcode() if msg.flags else None
        return qname, rcode
    except Exception as e:
        print(f"Error parsing message: {e}")
        return None, None

'''
Our experiments can consist of multiple measurements.
We assume that all measurements with the same label belong to the same experiment.
Return dataframe for measurements and results.
'''
def get_results_from_label(label, write_to_csv=True):
    kwargs = {
        "description__contains": f"\"label\": \"{label}\"",
        "mine": True,
    }
    url_path = "/api/v2/measurements"
    request = AtlasRequest(**{"url_path": url_path})
    (is_success, response) = request.get(**kwargs)
    results = response["results"]
    print("Found %d results for label %s" % (response["count"], label))
    if results == []:
        print("No results for label %s!" % (label))
        return (None, None)
    elif is_success:
        df_measurements = pd.DataFrame(pd.json_normalize(results))
        df_measurements = df_measurements.assign(label="%s" % (label))
        ids = df_measurements["id"].astype(int).tolist()
        return get_results(ids)
    else:
        print("Failed to fetch results")
        return (None, None)

'''
same as get_results, but this time we already know the metadata
assumption: all ids have the same label, algorithm, and strategy
'''
def get_results_with_metadata(ids, label, algorithm, strategy):
    dfs = []
    df_measurements = get_measurements_with_metadata(ids, label)
    if df_measurements is None:
        print("Could not find measurements")
        return (None, None)

    for id in ids:
        kwargs = {
            "msm_id": id,
        }
        is_success, results = AtlasLatestRequest(**kwargs).create()
        if results == []:
            print("No results for id %d!" % (id))
            return (None, None)
        elif is_success:
            df = pd.DataFrame(pd.json_normalize(results))
            # add qname and rcode
            df[['qname', 'rcode']] = df["result.abuf"].apply(
                lambda x: pd.Series(parse_dns_message(x))
            )
            df = df.assign(algorithm="%s" % (algorithm))
            df = df.assign(strategy="%s" % (strategy))
            df = df.assign(label="%s" % (label))
            dfs.append(df)
        else:
            print("Could not fetch measurement %d" % (id))
            return (df_measurements, None)
    if dfs != []:
        # concate all dataframes
        df_results = pd.concat([x for x in dfs], ignore_index=True)
        return (df_measurements, df_results)
    else:
        print("No results!")
        return (df_measurements, None)

'''
gets the measurement information for given ids
'''
def get_measurements_with_metadata(ids, label):
    kwargs = {
        "id": ", ".join([str(x) for x in ids])
    }
    url_path = "/api/v2/measurements"
    request = AtlasRequest(**{"url_path": url_path})
    (is_success, response) = request.get(**kwargs)
    if is_success:
        results = response["results"]
        if results == []:
            print("No results for ids %s!" % (ids))
            return None
        elif len(ids) != response["count"]:
            print("len(ids) (%d) != response[\"count\"] (%d)" % (len(ids), response["count"]))
            return None
        print("Found %d results for ids %s" % (response["count"], ids))
        df = pd.DataFrame(pd.json_normalize(results))
        df = df.assign(label="%s" % (label))
        return df
    else:
        print("Failed to fetch results")
        return None

'''
get all the results based on the measurements specified in ids
only works if the description contains a json part with {"algorithm": x, "strategy": y, "label": z}
outputs as a single CSV (no label, strategy, or algorithm)
'''
def get_results(ids):
    dfs = []
    df_measurements = get_measurements_with_metadata(ids, "")
    if df_measurements is None:
        print("Could not find measurements")
        return (None, None)
    for id in ids:
        kwargs = {
            "msm_id": id,
        }
        is_success, results = AtlasLatestRequest(**kwargs).create()
        if results == []:
            print("No results for id %d!" % (id))
        elif is_success:
            df = pd.DataFrame(pd.json_normalize(results))
            measurement = Measurement(id=id)
            # check if algorithm, strategy, and label are set
            algorithm, strategy, label = parse_description(measurement.description)
            if algorithm == "" or strategy == "":
                print("We expect 'algorithm' and 'strategy' to be set in the tags!")
                return (df_measurements, None)
            # add qname and rcode
            df[['qname', 'rcode']] = df["result.abuf"].apply(
                lambda x: pd.Series(parse_dns_message(x))
            )
            # add columns
            df = df.assign(algorithm="%s" % (algorithm))
            df = df.assign(strategy="%s" % (strategy))
            df = df.assign(label="%s" % (label))
            dfs.append(df)
        else:
            print("Could not fetch measurement %d" % (id))
    if dfs != []:
        # concate all dataframes
        df_results = pd.concat([x for x in dfs], ignore_index=True)
        return (df_measurements, df_results)
    else:
        print("No results!")
        return (df_measurements, None)

def main():
    parser = argparse.ArgumentParser(description='Fetch and save Atlas measurement results.')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-i', '--ids', type=str, help='Comma-separated list of Measurement IDs to fetch results for')
    group.add_argument('-l', '--label', type=str, help='Label to fetch results for')
    parser.add_argument('-c', '--csv', action='store_true', default=True, help='Save the results as CSV')
    args = parser.parse_args()

    # no check at the moment
    timestamp = pd.Timestamp.now().strftime("%Y-%m-%d_%H-%M-%S")
    label = ""
    algorithm = ""
    strategy = ""
    if args.ids:
        ids = [int(x.strip()) for x in args.ids.split(",")]
        (df_measurements, df_results) = get_results(ids, args.csv)
    else:
        (df_measurements, df_results) = get_results_from_label(args.label, args.csv)
        label = args.label

    if df_measurements is not None and args.csv:
        print("Collected measurement metadata, writing to csv file...")
        csv = df_measurements.to_csv(index=False)
        save_to_csv(csv, timestamp, "measurements-%s" % label, strategy, algorithm)
    if df_results is not None and args.csv:
        print("Collected results, writing to csv file...")
        csv = df_results.to_csv(index=False)
        save_to_csv(csv, timestamp, label, strategy, algorithm)

if __name__ == "__main__":
    main()
