#!/usr/bin/env python3

import resource
import subprocess
import sys


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: check_peak_rss.py MAXIMUM_BYTES COMMAND [ARGUMENT ...]")

    maximum = int(sys.argv[1])
    subprocess.run(sys.argv[2:], check=True)
    peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    peak_bytes = peak if sys.platform == "darwin" else peak * 1024
    print(f"peak RSS: {peak_bytes} bytes (limit: {maximum} bytes)")
    if peak_bytes > maximum:
        raise SystemExit("memory probe exceeded its peak-RSS limit")


if __name__ == "__main__":
    main()
