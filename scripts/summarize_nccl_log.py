#!/usr/bin/env python3
"""Summarize fixed-size nccl-tests rows from a local log file."""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path

DATA_ROW = re.compile(
    r"^\s*(?P<size>\d+)\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+"
    r"(?P<oop_alg>[-+0-9.eE]+)\s+(?P<oop_bus>[-+0-9.eE]+)\s+(?P<oop_wrong>\d+)\s+"
    r"(?P<ip_alg>[-+0-9.eE]+)\s+(?P<ip_bus>[-+0-9.eE]+)\s+(?P<ip_wrong>\d+)"
)
AVG_ROW = re.compile(r"Avg bus bandwidth\s*:\s*(?P<avg>[-+0-9.eE]+)")


def parse_log(text: str) -> dict[str, object]:
    rows: list[dict[str, object]] = []
    averages: list[float] = []
    for line in text.splitlines():
        match = DATA_ROW.match(line)
        if match:
            values = match.groupdict()
            rows.append(
                {
                    "size_bytes": int(values["size"]),
                    "out_of_place_alg_gb_per_second": float(values["oop_alg"]),
                    "out_of_place_bus_gb_per_second": float(values["oop_bus"]),
                    "out_of_place_wrong": int(values["oop_wrong"]),
                    "in_place_alg_gb_per_second": float(values["ip_alg"]),
                    "in_place_bus_gb_per_second": float(values["ip_bus"]),
                    "in_place_wrong": int(values["ip_wrong"]),
                }
            )
        average = AVG_ROW.search(line)
        if average:
            averages.append(float(average.group("avg")))

    wrong = sum(
        int(row["out_of_place_wrong"]) + int(row["in_place_wrong"])
        for row in rows
    )
    summary: dict[str, object] = {
        "data_rows": len(rows),
        "reported_average_count": len(averages),
        "wrong_total": wrong,
        "rows": rows,
    }
    if averages:
        summary["reported_average_gb_per_second"] = {
            "values": averages,
            "mean": statistics.fmean(averages),
            "median": statistics.median(averages),
            "minimum": min(averages),
            "maximum": max(averages),
        }
    return summary


def self_test() -> None:
    sample = """
 268435456  67108864  float  sum  -1  0  20.00  19.00  0  21.00  20.00  0
 # Avg bus bandwidth    : 19.5000
"""
    result = parse_log(sample)
    assert result["data_rows"] == 1
    assert result["wrong_total"] == 0
    averages = result["reported_average_gb_per_second"]
    assert isinstance(averages, dict)
    assert averages["mean"] == 19.5


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("summarize_nccl_log: PASS")
        return 0
    if args.log is None:
        parser.error("a local log path is required unless --self-test is used")
    print(json.dumps(parse_log(args.log.read_text(encoding="utf-8")), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
