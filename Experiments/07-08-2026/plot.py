"""
Script to analyse results.csv and generate plots.
"""

import pandas as pd
import matplotlib.pyplot as plt
import os

def generate_plots():
    """
    Generate plots from results.csv:
    1. For every client, plot the metric for all algorithms.
    2. For every algorithm, plot the metric for all clients.
    """
    results_df = pd.read_csv('results.csv', keep_default_na=False)
    
    # Create a directory to save the plots
    output_dir = 'plots'
    os.makedirs(output_dir, exist_ok=True)
    
    metrics = ['client_rtt_avg', 'res_rtt_avg', 'cpu', 'mem', 'net_rx', 'net_tx']
    algorithms = results_df['algorithm'].unique()
    
    # (1) For every client, plot the metric for all algorithms
    clients = results_df['client'].unique()
    for client in clients:
        client_data = results_df[results_df['client'] == client]
        for metric in metrics:
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
            plt.ylabel(metric)
            plt.title(f'{metric} for {client}')
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
        for metric in metrics:
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
            plt.ylabel(metric)
            plt.title(f'{metric} for {algorithm}')
            plt.xticks(rotation=45, ha='right')
            plt.legend(bars, sorted_clients, title='Client')
            plt.tight_layout()
            
            # Save the plot
            plot_filename = os.path.join(output_dir, f'algorithm_{algorithm}_{metric}.png')
            plt.savefig(plot_filename)
            plt.close()


if __name__ == '__main__':
    generate_plots()