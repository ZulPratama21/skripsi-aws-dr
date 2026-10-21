#!/usr/bin/env python3
"""Validate DR HTTP root + healthz, including X-DR-Region, with timestamped evidence."""
import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def get(url):
    req = Request(url, headers={"Cache-Control": "no-cache", "User-Agent": "aws-dr-research-probe/1.0"})
    with urlopen(req, timeout=10) as response:
        return {
            "status": response.status,
            "region": response.headers.get("X-DR-Region", ""),
            "body": response.read(100000).decode("utf-8", "replace"),
            "x_cache": response.headers.get("X-Cache", ""),
        }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base-url", required=True)
    p.add_argument("--region", required=True, choices=["region-a", "region-b"])
    p.add_argument("--attempts", type=int, default=12)
    p.add_argument("--interval", type=float, default=5)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    records = []
    success = False
    for i in range(1, args.attempts + 1):
        rec = {"timestamp_utc": utc_now(), "attempt": i}
        try:
            root = get(args.base_url.rstrip("/") + "/")
            health = get(args.base_url.rstrip("/") + "/healthz")
            rec.update({"root_status": root["status"], "root_region": root["region"],
                        "root_x_cache": root["x_cache"], "health_status": health["status"],
                        "health_region": health["region"]})
            success = (root["status"] == 200 and health["status"] == 200
                       and root["region"] == args.region and health["region"] == args.region
                       and "DR LABORATORY WORKLOAD - SERVICE OK" in root["body"]
                       and health["body"].strip() == "ready")
            rec["passed"] = success
        except Exception as e:
            rec.update({"passed": False, "error": repr(e)})
        records.append(rec)
        print(json.dumps(rec), flush=True)
        if success:
            break
        if i < args.attempts:
            time.sleep(args.interval)
    dest = Path(args.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps({"base_url": args.base_url, "expected_region": args.region,
                                "passed": success, "records": records}, indent=2) + "\n", encoding="utf-8")
    if not success:
        raise SystemExit("HTTP verification did not pass")


if __name__ == "__main__":
    main()
