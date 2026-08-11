import sys
import re
import statistics
import os
import glob
import csv
import json

def analyse_logs(file_path):
    # Regex to find a decimal number followed by 's' at the end of a line
    # Matches "0.042425088s" and captures "0.042425088"
    time_pattern = re.compile(r"(\d+\.\d+)s\s*$")
    tc_pattern = re.compile(r'NOERROR.*\btc\b') # bit hacky but should work
    
    values = []

    try:
        with open(file_path, 'r') as file:
            for line in file:
                if tc_pattern.search(line):
                    continue
                match = time_pattern.search(line.strip())
                if match:
                    values.append(float(match.group(1)))
    except FileNotFoundError:
        print(f"Error: The file '{file_path}' was not found.")
        return None
    except Exception as e:
        print(f"An error occurred: {e}")
        return None

    if len(values) <= 2:
        print("No valid time values found in the file.")
        return None
    values = values[1:]
    
    count = len(values)
    avg = statistics.mean(values)
    std_dev = statistics.stdev(values) if count > 1 else 0.0

    return {
        "avg": round(avg * 1000, 2),
        "std_dev": round(std_dev * 1000, 2),
        "count": count
    }

def find_csv_and_calculate_stats(directory):
    """Find a CSV file in the directory and calculate statistics on the 'Query Time' column."""
    csv_files = glob.glob(os.path.join(directory, "*.csv"))
    
    if len(csv_files) != 1:
        print(f"Error: Expected exactly one CSV file in {directory}, found {len(csv_files)}.")
        return None
    
    csv_file = csv_files[0]
    
    try:
        with open(csv_file, 'r') as file:
            reader = csv.reader(file)
            headers = next(reader)
            
            if "Query Time" not in headers:
                print(f"Error: CSV file {csv_file} does not contain a 'Query Time' column.")
                return None
            
            query_time_index = headers.index("Query Time")
            values = []
            
            for i, row in enumerate(reader):
                if i >= 1:  # Skip the first value (start from row 3)
                    try:
                        values.append(float(row[query_time_index]))
                    except (ValueError, IndexError):
                        continue
    except Exception as e:
        print(f"Error reading CSV file {csv_file}: {e}")
        return None
    
    if len(values) < 2:
        print(f"Error: Not enough data points in {csv_file}.")
        return None
    
    avg = round(statistics.mean(values), 2)
    std_dev = round(statistics.stdev(values), 2)
    
    return {"avg_query_time": avg, "std_dev_query_time": std_dev}

def parse_cpu_log(directory):
    """Parse the CPU log file in the 'Res' subdirectory and extract the average CPU usage."""
    res_dir = os.path.join(directory, "Res")
    if not os.path.exists(res_dir):
        print(f"Error: 'Res' subdirectory not found in {directory}.")
        return None
    
    cpu_files = glob.glob(os.path.join(res_dir, "cpu*.log"))
    
    if len(cpu_files) != 1:
        print(f"Error: Expected exactly one CPU log file in {res_dir}, found {len(cpu_files)}.")
        return None
    
    cpu_file = cpu_files[0]
    
    try:
        with open(cpu_file, 'r') as file:
            for line in file:
                if line.startswith("Average:"):
                    parts = line.split()
                    if len(parts) >= 8:
                        return float(parts[2])  
    except Exception as e:
        print(f"Error reading CPU log file {cpu_file}: {e}")
        return None
    
    print(f"Error: Could not parse CPU log file {cpu_file}.")
    return None

def parse_mem_log(directory):
    """Parse the memory log file in the 'Res' subdirectory and extract the % memused."""
    res_dir = os.path.join(directory, "Res")
    if not os.path.exists(res_dir):
        print(f"Error: 'Res' subdirectory not found in {directory}.")
        return None
    
    mem_files = glob.glob(os.path.join(res_dir, "mem*.log"))
    
    if len(mem_files) != 1:
        print(f"Error: Expected exactly one memory log file in {res_dir}, found {len(mem_files)}.")
        return None
    
    mem_file = mem_files[0]
    
    try:
        with open(mem_file, 'r') as file:
            for line in file:
                if line.startswith("Average:"):
                    parts = line.split()
                    # Average:       256867   1283596    375388     19.24      7290   1125802   1648426     84.50    807410    610530      1188
                    if len(parts) >= 10:
                        return float(parts[4])  # Fourth number after "Average:"
    except Exception as e:
        print(f"Error reading memory log file {mem_file}: {e}")
        return None
    
    print(f"Error: Could not parse memory log file {mem_file}.")
    return None

def parse_net_log(directory):
    """Parse the network log file in the 'Res' subdirectory and extract rx/tx (kBps)."""
    res_dir = os.path.join(directory, "Res")
    if not os.path.exists(res_dir):
        print(f"Error: 'Res' subdirectory not found in {directory}.")
        return None
    
    net_files = glob.glob(os.path.join(res_dir, "net*.log"))
    
    if len(net_files) != 1:
        print(f"Error: Expected exactly one network log file in {res_dir}, found {len(net_files)}.")
        return None
    
    net_file = net_files[0]
    
    try:
        with open(net_file, 'r') as file:
            for line in file:
                if line.startswith("Average:") and not re.search(r"Average:.*IFACE", line):
                    parts = line.split()
                    # Average:        IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s   %ifutil
                    # Average:         ens5     44.53     44.60     13.96      9.36      0.00      0.00      0.00      0.00
                    if len(parts) >= 10:
                        rx = float(parts[4])  # rxkB/s
                        tx = float(parts[5])  # txkB/s
                        return f"{rx}/{tx}"
    except Exception as e:
        print(f"Error reading network log file {net_file}: {e}")
        return None
    
    print(f"Error: Could not parse network log file {net_file}.")
    return None

def parse_coredns_log(directory):
    """Parse the coredns.txt file in the 'Res' subdirectory."""
    res_dir = os.path.join(directory, "Res")
    if not os.path.exists(res_dir):
        print(f"Error: 'Res' subdirectory not found in {directory}.")
        return None
    
    coredns_file = os.path.join(res_dir, "coredns.txt")
    
    if not os.path.exists(coredns_file):
        print(f"Error: 'coredns.txt' file not found in {res_dir}.")
        return None
    
    coredns_stats = analyse_logs(coredns_file)
    if coredns_stats:
        return {
            "res_rtt_avg": coredns_stats["avg"],
            "res_rtt_std_dev": coredns_stats["std_dev"]
        }
    return None

def analyse_directory(directory):
    """Analyse a single directory and return statistics."""
    stats = {}
    
    # Calculate CSV statistics
    csv_stats = find_csv_and_calculate_stats(directory)
    if csv_stats:
        stats.update(csv_stats)
    
    # Parse CPU log
    cpu_usage = parse_cpu_log(directory)
    if cpu_usage is not None:
        stats["avg_cpu_usage"] = cpu_usage
    
    # Parse memory log
    mem_usage = parse_mem_log(directory)
    if mem_usage is not None:
        stats["mem_usage_percent"] = mem_usage
    
    # Parse network log
    net_usage = parse_net_log(directory)
    if net_usage is not None:
        stats["net_rx_tx"] = net_usage
    
    # Parse coredns log
    coredns_stats = parse_coredns_log(directory)
    if coredns_stats:
        stats.update(coredns_stats)
    
    return stats

# load_json loads the json file and does a sanity check to make sure the results are correct
# 1. check if there is only one json file
# 2. check if is a txt file and csv file with the same name
# 3. check if Res has five files: coredns.txt, cpu*.log, net*.log, mem*.log, and *.pcap (TBD)
# 4. check if NS has three files: cpu*.log, net*.log, and mem*.log (TBD)
# 5. check if the PCAP file in Res contains the Algorithm name and Client in its name (TBD)
# 6. check if the label value in the json file is included in the file names as well
def load_json(directory):
    json_files = glob.glob(os.path.join(directory, "*.json"))
    if len(json_files) != 1:
        print(f"Error: Expected exactly one JSON file in {directory}, found {len(json_files)}.")
        sys.exit(1)
    json_file = json_files[0]
    base_name = os.path.splitext(os.path.basename(json_file))[0]
    if not (os.path.exists(os.path.join(directory, f"{base_name}.txt")) and
            os.path.exists(os.path.join(directory, f"{base_name}.csv"))):
        print(f"Error: Missing corresponding .txt or .csv file for {json_file}")
        sys.exit(1)
    json_data = {}
    if os.path.exists(json_file):
        try:
            with open(json_file, 'r') as f:
                json_data = json.load(f)
        except Exception as e:
            print(f"Error reading JSON file {json_file}: {e}")
    # check 6
    if not json_data['label'].lower() in base_name.lower():
        print(f"Error: Label '{json_data['label']}' not found in base name '{base_name}'")
        sys.exit(1)
    # check 5
    return json_data

def analyse_directories(keyword):
    """Find directories starting with the keyword and analyse them."""
    directories = [d for d in os.listdir(".") if os.path.isdir(d) and d.startswith(keyword)]
    
    if not directories:
        print(f"Error: No directories found starting with '{keyword}'.")
        return
    
    results = []

    for directory in directories:
        print(f"\nAnalysing directory: {directory}")
        stats = analyse_directory(directory)
        
        # Read JSON file
        json_data = load_json(directory)

        if stats:
            print("Statistics:")
            for key, value in stats.items():
                print(f"  {key}: {value}")

            # Prepare data for CSV
            client_rtt_avg = stats.get('avg_query_time', 'N/A')
            client_rtt_std_dev = stats.get('std_dev_query_time', 'N/A')
            res_rtt_avg = stats.get('res_rtt_avg', 'N/A')
            res_rtt_std_dev = stats.get('res_rtt_std_dev', 'N/A')
            cpu = stats.get('avg_cpu_usage', 'N/A')
            mem = stats.get('mem_usage_percent', 'N/A')
            net_rx, net_tx = stats.get('net_rx_tx', 'N/A/N/A').split('/') if 'net_rx_tx' in stats else ('N/A', 'N/A')
            results.append({
                'directory': directory,
                'count': json_data.get('count', 'N/A'),
                'nodnssec': json_data.get('nodnssec', 'N/A'),
                'domain': json_data.get('domain', 'N/A'),
                'algorithm': json_data.get('algorithm', 'N/A'),
                'client': json_data.get('client', 'N/A'),
                'label': json_data.get('label', 'N/A'),
                'client_rtt_avg': client_rtt_avg,
                'client_rtt_std_dev': client_rtt_std_dev,
                'res_rtt_avg': res_rtt_avg,
                'res_rtt_std_dev': res_rtt_std_dev,
                'cpu': cpu,
                'mem': mem,
                'net_rx': net_rx,
                'net_tx': net_tx
            })
        else:
            print("No statistics could be calculated for this directory.")

    # Write results to CSV file
    if results:
        for result in results:
            if 'UDP-DoQ' in result['label']:
                result['client'] = 'UDP-DoQ'
                result['label'] = result['label'].replace('UDP-DoQ', '').replace('--', '-').strip('-')
        with open('results.csv', 'w', newline='') as csvfile:
            fieldnames = ['directory', 'count', 'nodnssec', 'domain', 'algorithm', 'client', 'label',
                         'client_rtt_avg', 'client_rtt_std_dev', 'res_rtt_avg', 'res_rtt_std_dev',
                         'cpu', 'mem', 'net_rx', 'net_tx']
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            for result in results:
                writer.writerow(result)
        # Convert CSV to LaTeX table
        if results:
            latex_content = r"""
\begin{tabular}{|l|l|l|l|l|l|l|l|}
\hline
Algorithm & Client & Mode & \textbf{Client RTT (ms)} & \textbf{Res RTT (ms)} & CPU (\%) & Mem (\%) & Network (rx/tx kBps) \\
\hline
"""
            for result in results:
                client_rtt = f"{result['client_rtt_avg']:.2f} ({result['client_rtt_std_dev']:.2f})" if result['client_rtt_avg'] != 'N/A' else 'N/A'
                res_rtt = f"{result['res_rtt_avg']:.2f} ({result['res_rtt_std_dev']:.2f})" if result['res_rtt_avg'] != 'N/A' else 'N/A'
                net_rx_tx = f"{result['net_rx']}/{result['net_tx']}" if result['net_rx'] != 'N/A' else 'N/A'

                latex_content += f"{result['algorithm'].replace('_', '\\_')} & {result['client'].replace('_', '\\_')} & {result['label'].replace('_', '\\_')} & {client_rtt} & {res_rtt} & {result['cpu']} & {result['mem']} & {net_rx_tx} \\\\\n"

            latex_content += r"""\hline
\end{tabular}
"""
            with open('results.tex', 'w') as texfile:
                texfile.write(latex_content)
                

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python analyse.py [keyword]")
    else:
        keyword = sys.argv[1]
        analyse_directories(keyword)
