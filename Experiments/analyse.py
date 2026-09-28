import sys
import re
import statistics

def analyse_logs(file_path):
    # Regex to find a decimal number followed by 's' at the end of a line
    # Matches "0.042425088s" and captures "0.042425088"
    time_pattern = re.compile(r"(\d+\.\d+)s\s*$")
    
    values = []

    try:
        with open(file_path, 'r') as file:
            for line in file:
                match = time_pattern.search(line.strip())
                if match:
                    # Convert the captured string group to a float
                    values.append(float(match.group(1)))
    except FileNotFoundError:
        print(f"Error: The file '{file_path}' was not found.")
        return
    except Exception as e:
        print(f"An error occurred: {e}")
        return

    if len(values) <= 2:
        print("No valid time values found in the file.")
        return
    values = values[1:]
    


    # Calculations
    count = len(values)
    avg = statistics.mean(values)
    # Standard deviation requires at least two data points
    std_dev = statistics.stdev(values) if count > 1 else 0.0

    # Output results
    print(f"Values found:    {count}")
    print(f"Average:         {avg * 1000:.2f}ms")
    print(f"Std Deviation:   {std_dev * 1000:.2f}ms")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python analyse.py [textfile]")
    else:
        analyse_logs(sys.argv[1])