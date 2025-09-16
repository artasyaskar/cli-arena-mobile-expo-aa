import requests
import time

def run_benchmark(url):
    """
    Makes a request to the given URL and returns the response time.
    """
    start_time = time.time()
    try:
        response = requests.get(url)
        response.raise_for_status() # Raise an exception for bad status codes
    except requests.exceptions.RequestException as e:
        print(f"Error during request: {e}")
        return -1
    end_time = time.time()
    return end_time - start_time

if __name__ == "__main__":
    # The query 'item_19999' is chosen to be near the end of the list
    # to maximize the time taken by the inefficient search.
    search_url = "http://localhost:5000/search?q=item_19999"
    duration = run_benchmark(search_url)
    if duration != -1:
        print(f"Response time: {duration:.4f} seconds")
