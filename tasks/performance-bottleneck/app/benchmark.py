import requests
import time
import threading
from concurrent.futures import ThreadPoolExecutor

# Number of concurrent requests to simulate
CONCURRENT_REQUESTS = 10

def make_request(url):
    """Makes a single request and returns the status code."""
    try:
        response = requests.get(url)
        return response.status_code
    except requests.exceptions.RequestException:
        return -1

def run_concurrent_benchmark(url):
    """
    Runs a benchmark by sending multiple requests concurrently.
    """
    start_time = time.time()

    with ThreadPoolExecutor(max_workers=CONCURRENT_REQUESTS) as executor:
        futures = [executor.submit(make_request, url) for _ in range(CONCURRENT_REQUESTS)]
        results = [future.result() for future in futures]

    end_time = time.time()

    if all(status == 200 for status in results):
        return end_time - start_time
    else:
        print(f"Error: Some requests failed. Statuses: {results}")
        return -1

if __name__ == "__main__":
    # The query 'item_19999' is chosen to be near the end of the list
    # to maximize the time taken by the inefficient search.
    search_url = "http://localhost:5000/search?q=item_19999"

    print(f"Running benchmark with {CONCURRENT_REQUESTS} concurrent requests...")
    duration = run_concurrent_benchmark(search_url)

    if duration != -1:
        print(f"Total time for {CONCURRENT_REQUESTS} requests: {duration:.4f} seconds")
