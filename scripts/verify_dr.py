#!/usr/bin/env python3
"""Verify actual DR endpoint readiness; this is not an RTO measurement."""
import argparse
import datetime
import json
import pathlib
import time
import urllib.error
import urllib.request


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--url', required=True)
    p.add_argument('--expected-header', default='region-b')
    p.add_argument('--timeout', type=int, default=120)
    p.add_argument('--output', default='evidence/validation.json')
    args = p.parse_args()
    target = args.url.rstrip('/') + '/'
    deadline = time.monotonic() + args.timeout
    results = []
    ok = False
    while time.monotonic() < deadline:
        at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            with urllib.request.urlopen(urllib.request.Request(target, headers={'Cache-Control': 'no-cache'}), timeout=8) as r:
                body = r.read(64 * 1024).decode('utf-8', errors='replace')
                region = r.headers.get('X-DR-Region', '')
                ok = r.status == 200 and 'DR LABORATORY WORKLOAD - SERVICE OK' in body and region == args.expected_header
                results.append({'at': at, 'status': r.status, 'region': region, 'valid': ok})
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            results.append({'at': at, 'error': str(exc), 'valid': False})
        if ok:
            break
        time.sleep(3)
    out = pathlib.Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({'target': target, 'ready': ok, 'attempts': results}, indent=2), encoding='utf-8')
    if not ok:
        raise SystemExit('Recovery validation FAILED; see ' + str(out))
    print('Recovery validated at', results[-1]['at'])


if __name__ == '__main__':
    main()
