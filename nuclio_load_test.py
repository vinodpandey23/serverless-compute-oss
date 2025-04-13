import requests
import threading
import time
import argparse
from concurrent.futures import ThreadPoolExecutor

def invoke_function(url, function_name, payload, request_count):
    headers = {
        "x-nuclio-function-name": function_name,
        "Content-Type": "application/json"
    }
    
    for _ in range(request_count):
        try:
            response = requests.post(url, headers=headers, json=payload)
            print(f"Response: {response.status_code} - {response.text.strip()}")
        except Exception as e:
            print(f"Request failed: {str(e)}")

def load_test(args):
    payload = {
        "base_currency": "USD",
        "target_currency": "SGD",
        "amount": "100"
    }
    
    print(f"Starting load test with {args.threads} threads, {args.requests_per_thread} requests each")
    print(f"Target function: {args.function_name}")
    print(f"Total requests: {args.threads * args.requests_per_thread}")
    
    start_time = time.time()
    
    with ThreadPoolExecutor(max_workers=args.threads) as executor:
        for _ in range(args.threads):
            executor.submit(
                invoke_function,
                args.url,
                args.function_name,
                payload,
                args.requests_per_thread
            )
    
    duration = time.time() - start_time
    print(f"\nLoad test completed in {duration:.2f} seconds")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Nuclio Function Load Tester")
    parser.add_argument("--url", default="http://127.0.0.1:8080/invoke", help="Function invocation URL")
    parser.add_argument("--function-name", default="currency-converter", help="Nuclio function name")
    parser.add_argument("--threads", type=int, default=10, help="Number of concurrent threads")
    parser.add_argument("--requests-per-thread", type=int, default=10, help="Requests per thread")
    
    args = parser.parse_args()
    load_test(args)
