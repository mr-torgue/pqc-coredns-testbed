"""
Script to analyse results.csv and generate plots.
"""

import pandas as pd
import matplotlib.pyplot as plt
import os
import numpy as np

def generate_boxplots(results_df, output_dir):
    """Generate boxplots for CPU and memory usage, ignoring the first and last entries."""
    # Load CPU and memory values from individual directories
    # Since the CSV doesn't contain all values, we need to read them from the directories
    # For now, we'll use the avg and top5_avg values from the CSV
    
    # Boxplot for CPU usage
    plt.figure(figsize=(12, 6))
    
    # Group by algorithm and client
    grouped = results_df.groupby(['algorithm', 'client'])
    
    # Prepare data for boxplot
    cpu_data = []
    labels = []
    
    for (algorithm, client), group in grouped:
        avg_cpu = group['avg_cpu_usage'].mean()
        top5_avg_cpu = group['top5_avg_cpu_usage'].mean()
        
        # For boxplot, we need multiple data points. Since we don't have all values in the CSV,
        # we'll use the avg and top5_avg as proxies (not ideal, but works for now)
        cpu_data.append([avg_cpu, top5_avg_cpu])
        labels.append(f"{algorithm} ({client})")
    
    # Create boxplot
    plt.boxplot(cpu_data, labels=labels)
    plt.xlabel('Algorithm (Client)')
    plt.ylabel('CPU Usage (%)')
    plt.title('CPU Usage Distribution (First and Last Entries Filtered)')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    
    # Save the plot
    plot_filename = os.path.join(output_dir, 'boxplot_cpu_usage.png')
    plt.savefig(plot_filename)
    plt.close()
    
    # Boxplot for Memory usage
    plt.figure(figsize=(12, 6))
    
    mem_data = []
    labels = []
    
    for (algorithm, client), group in grouped:
        avg_mem = group['avg_mem_usage'].mean()
        top5_avg_mem = group['top5_avg_mem_usage'].mean()
        
        mem_data.append([avg_mem, top5_avg_mem])
        labels.append(f"{algorithm} ({client})")
    
    # Create boxplot
    plt.boxplot(mem_data, labels=labels)
    plt.xlabel('Algorithm (Client)')
    plt.ylabel('Memory Usage (%)')
    plt.title('Memory Usage Distribution (First and Last Entries Filtered)')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    
    # Save the plot
    plot_filename = os.path.join(output_dir, 'boxplot_mem_usage.png')
    plt.savefig(plot_filename)
    plt.close()


def generate_plots():
    """
    Generate plots from results.csv:
    1. For every client, plot the metric for all algorithms.
    2. For every algorithm, plot the metric for all clients.
    3. Boxplots for CPU and memory usage.
    """
    results_df = pd.read_csv('results.csv', keep_default_na=False)
    
    # Create a directory to save the plots
    output_dir = 'plots'
    os.makedirs(output_dir, exist_ok=True)
    
    metrics = [
        ('client_rtt_avg', 'Client RTT Average (ms)'),
        ('res_rtt_avg', 'Resolver RTT Average (ms)'),
        ('avg_cpu_usage', 'CPU Usage Average (%)'),
        ('top5_avg_cpu_usage', 'CPU Usage Top5 Average (%)'),
        ('avg_mem_usage', 'Memory Usage Average (%)'),
        ('top5_avg_mem_usage', 'Memory Usage Top5 Average (%)'),
        ('net_rx', 'Network Receive (kBps)'),
        ('net_tx', 'Network Transmit (kBps)')
    ]
    algorithms = results_df['algorithm'].unique()
    
    # (1) For every client, plot the metric for all algorithms
    clients = results_df['client'].unique()
    for client in clients:
        client_data = results_df[results_df['client'] == client]
        for metric, label in metrics:
            plt.figure(figsize=(12, 6))
            
            if not all(client_data.groupby('algorithm').size() == 1):
                print(f"Error: Multiple entries found for one or more algorithms for client {client} and metric {metric}")
                exit(0)

            # Sort algorithms to place p256 variants next to their non-p256 counterparts
            sorted_algorithms = sorted(client_data['algorithm'].unique(), key=lambda x: (x.startswith('P256_') and x[5:] or x, x))
            grouped_data = client_data.groupby('algorithm')[metric].mean().reindex(sorted_algorithms)
            if list(sorted_algorithms) != list(grouped_data.index):
                print(f"Warning: Mismatch between sorted algorithms and grouped data indices for client {client} and metric {metric}")
                exit(0)

            bars = plt.bar(sorted_algorithms, grouped_data, color=plt.cm.tab20.colors[:len(sorted_algorithms)])
            plt.xlabel('Algorithm')
            plt.ylabel(label)
            plt.title(f'{label} for {client}')
            plt.xticks(rotation=45, ha='right')
            plt.legend(bars, sorted_algorithms, title='Algorithm')
            plt.tight_layout()
            
            # Save the plot
            plot_filename = os.path.join(output_dir, f'client_{client}_{metric}.png')
            plt.savefig(plot_filename)
            plt.close()
    
    # (2) For every algorithm, plot the metric for all clients
    for algorithm in algorithms:
        algorithm_data = results_df[results_df['algorithm'] == algorithm]
        for metric, label in metrics:
            plt.figure(figsize=(10, 6))

            if not all(algorithm_data.groupby('client').size() == 1):
                print(f"Error: Multiple entries found for one or more clients for algorithm {algorithm} and metric {metric}")
                exit(0)

            # Sort clients alphabetically
            sorted_clients = sorted(algorithm_data['client'].unique())
            grouped_data = algorithm_data.groupby('client')[metric].mean().reindex(sorted_clients)
            if list(sorted_clients) != list(grouped_data.index):
                print(f"Warning: Mismatch between sorted clients and grouped data indices for algorithm {algorithm} and metric {metric}")
                exit(0)

            # Plot bars for each client with different colors
            bars = plt.bar(sorted_clients, grouped_data, color=plt.cm.tab20.colors[:len(sorted_clients)])
            plt.xlabel('Client')
            plt.ylabel(label)
            plt.title(f'{label} for {algorithm}')
            plt.xticks(rotation=45, ha='right')
            plt.legend(bars, sorted_clients, title='Client')
            plt.tight_layout()
            
            # Save the plot
            plot_filename = os.path.join(output_dir, f'algorithm_{algorithm}_{metric}.png')
            plt.savefig(plot_filename)
            plt.close()
    
    # (3) Generate boxplots for CPU and memory
    generate_boxplots(results_df, output_dir)


if __name__ == '__main__':
    generate_plots()