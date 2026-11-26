#!/usr/bin/env python3
"""
ShopLite Load Test Harness (Question 8.1)
Generates >= 20 requests/sec mixed traffic (/products, /products/{id}, POST /orders)
without external CLI dependencies (uses Python standard library).
Usage: python3 scripts/load-test.py --url http://<ALB-DNS> --rps 25 --duration 900
"""

import argparse
import concurrent.futures
import json
import random
import time
import urllib.error
import urllib.request
from collections import Counter


def send_request(base_url: str) -> str:
    """Issue one randomized catalog or order HTTP request and return status category."""
    roll = random.random()
    try:
        if roll < 0.45:
            req = urllib.request.Request(f"{base_url}/api/products", method="GET")
        elif roll < 0.80:
            pid = random.randint(1, 10)
            req = urllib.request.Request(f"{base_url}/api/products/{pid}", method="GET")
        else:
            payload = json.dumps({"product_id": random.randint(1, 10), "quantity": 1}).encode("utf-8")
            req = urllib.request.Request(
                f"{base_url}/api/orders",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return str(resp.status)
    except urllib.error.HTTPError as err:
        return str(err.code)
    except Exception:
        return "conn_err"


def main():
    parser = argparse.ArgumentParser(description="ShopLite Load Generator (>=20 RPS)")
    parser.add_argument("--url", required=True, help="Base ALB URL (e.g. http://shoplite-alb-...amazonaws.com)")
    parser.add_argument("--rps", type=int, default=25, help="Target requests per second (default: 25)")
    parser.add_argument("--duration", type=int, default=900, help="Duration in seconds (default: 900 = 15m)")
    args = parser.parse_args()

    base_url = args.url.rstrip("/")
    counts = Counter()
    start = time.time()
    print(f"Starting load test against {base_url} at {args.rps} RPS for {args.duration}s...")

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(50, max(10, args.rps))) as pool:
        sec_idx = 0
        while time.time() - start < args.duration:
            tick = time.time()
            futures = [pool.submit(send_request, base_url) for _ in range(args.rps)]
            for fut in concurrent.futures.as_completed(futures):
                counts[fut.result()] += 1
            sec_idx += 1
            if sec_idx % 15 == 0:
                elapsed = int(time.time() - start)
                print(f"[{elapsed}s/{args.duration}s] Status counts: {dict(counts)}")
            sleep_for = max(0.0, 1.0 - (time.time() - tick))
            time.sleep(sleep_for)

    total = sum(counts.values())
    print(f"Load test completed. Total requests: {total}, Breakdown: {dict(counts)}")


if __name__ == "__main__":
    main()
