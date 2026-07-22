#!/usr/bin/env python3
"""Classify NCCL RoCE GID pairs for the Sparks 5-8 switchless square."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


PAIR_RE = re.compile(
    r"on dev (?P<dev>[^:, ]+).*?local GID (?P<local>::ffff:(?P<local_ip>\d+\.\d+\.\d+\.\d+)), "
    r"remote GID (?P<remote>::ffff:(?P<remote_ip>\d+\.\d+\.\d+\.\d+))"
)
HOST_RE = re.compile(r"^(?P<host>[^:\s]+):\d+:\d+")

VALID_PAIRS = {
    frozenset(("192.0.2.10", "192.0.2.10")): "s5-s6-f0",
    frozenset(("192.0.2.10", "192.0.2.10")): "s5-s6-f0-rail1",
    frozenset(("192.0.2.10", "192.0.2.10")): "s6-s8-f1",
    frozenset(("192.0.2.10", "192.0.2.10")): "s6-s8-f1-rail1",
    frozenset(("192.0.2.10", "192.0.2.10")): "s8-s7-f0",
    frozenset(("192.0.2.10", "192.0.2.10")): "s8-s7-f0-rail1",
    frozenset(("192.0.2.10", "192.0.2.10")): "s7-s5-f1",
    frozenset(("192.0.2.10", "192.0.2.10")): "s7-s5-f1-rail1",
}


def classify(local_ip: str, remote_ip: str) -> tuple[str, str]:
    if local_ip == remote_ip:
        return "self", "self"
    pair = frozenset((local_ip, remote_ip))
    if pair in VALID_PAIRS:
        return "valid_neighbor", VALID_PAIRS[pair]
    if local_ip.startswith("198.51.100.") or local_ip.startswith("203.0.113."):
        return "non_neighbor", "missing_direct_edge"
    return "unknown", "outside_test_plan"


def parse_file(path: pathlib.Path) -> list[tuple[str, str, str, str, str, str, str]]:
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        match = PAIR_RE.search(line)
        if not match:
            continue
        host_match = HOST_RE.match(line)
        host = host_match.group("host") if host_match else ""
        local_ip = match.group("local_ip")
        remote_ip = match.group("remote_ip")
        edge_class, edge = classify(local_ip, remote_ip)
        rows.append((str(path), host, match.group("dev"), local_ip, remote_ip, edge_class, edge))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("logs", nargs="+", help="NCCL log files to classify")
    args = parser.parse_args()

    print("log\thost\tdev\tlocal_ip\tremote_ip\tclass\tedge")
    total = 0
    non_neighbor = 0
    for item in args.logs:
        for row in parse_file(pathlib.Path(item)):
            total += 1
            if row[5] == "non_neighbor":
                non_neighbor += 1
            print("\t".join(row))
    print(f"# total={total} non_neighbor={non_neighbor}", file=sys.stderr)
    return 2 if non_neighbor else 0


if __name__ == "__main__":
    raise SystemExit(main())
