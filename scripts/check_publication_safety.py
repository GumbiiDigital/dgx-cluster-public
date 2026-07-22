#!/usr/bin/env python3
"""Fail closed when public repository text contains likely private data."""

from __future__ import annotations

import ipaddress
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SELF = Path("scripts/check_publication_safety.py")
FENCE = chr(96) * 3
REQUIRED_FILES = {
    Path("README.md"),
    Path("docs/CASE-STUDY.md"),
    Path("docs/ARCHITECTURE.md"),
    Path("docs/PUBLICATION-SAFETY.md"),
    Path("docs/SHARE.md"),
    Path(".github/workflows/publication-safety.yml"),
    SELF,
}
TEXT_SUFFIXES = {".md", ".json", ".py", ".yml", ".yaml", ".txt", ".toml"}
FORBIDDEN_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10")
)
ALLOWED_DOCUMENTATION_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")
)
IPV4 = re.compile(r"(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])")
PATTERNS = {
    "private_key_block": re.compile(r"BEGIN [A-Z ]*PRIVATE KEY"),
    "github_token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b"),
    "cloud_key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "slack_token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]+\b"),
    "email": re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "mac_address": re.compile(r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b"),
    "uuid": re.compile(r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"),
    "serial_like": re.compile(r"\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]{10,}\b"),
    "multicast_local_hostname": re.compile(r"\b[A-Za-z0-9-]+[.]local\b", re.IGNORECASE),
    "mac_home_path": re.compile(r"/Users/[A-Za-z0-9._-]+"),
    "posix_home_path": re.compile(r"/home/[A-Za-z0-9._-]+"),
    "windows_home_path": re.compile(r"[A-Za-z]:\\Users\\[^\\\s]+"),
    "secret_assignment": re.compile(
        r"""(?i)\b(?:api[_-]?key|password|secret|access[_-]?token)\b\s*[:=]\s*["'][^"']+["']"""
    ),
    "sensitive_mapping_field": re.compile(
        r"""(?i)["']?(?:device_id|hardware_id|serial_number|mac_address|outlet_map|controller_map|live_topology|service_inventory)["']?\s*[:=]"""
    ),
    "private_source_link": re.compile(r"https://github[.]com/GumbiiDigital/(?![A-Za-z0-9._-]+-public(?:\b|/))"),
    "markdown_image": re.compile(r"!\[[^]]*\]\([^)]+\)"),
}
LINK = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")


def repository_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if ".git" in relative.parts or "__pycache__" in relative.parts:
            continue
        if path.is_symlink():
            raise ValueError(f"symlink is not allowed: {relative}")
        if path.is_file():
            files.append(relative)
    return sorted(files)


def scan_text(relative: Path, text: str, failures: list[str]) -> None:
    for name, pattern in PATTERNS.items():
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            failures.append(f"{relative}:{line}: prohibited pattern {name}")

    for match in IPV4.finditer(text):
        value = match.group(0)
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            failures.append(f"{relative}: invalid IPv4-like value {value}")
            continue
        if any(address in network for network in FORBIDDEN_NETWORKS):
            failures.append(f"{relative}: private or CGNAT address {value}")
        elif not any(address in network for network in ALLOWED_DOCUMENTATION_NETWORKS):
            failures.append(f"{relative}: non-documentation address {value}")

    if relative.suffix == ".md":
        if text.count(FENCE) % 2:
            failures.append(f"{relative}: unbalanced Markdown code fence")
        first = next((line for line in text.splitlines() if line.strip()), "")
        if relative == Path("docs/ARCHITECTURE.md"):
            lines = [line for line in text.splitlines() if line.strip()]
            fence_lines = [line for line in lines if line.startswith(FENCE)]
            if not lines or lines[0] != f"{FENCE}mermaid" or lines[-1] != FENCE or len(fence_lines) != 2:
                failures.append(f"{relative}: architecture must contain one Mermaid fence and no prose")
        elif not first.startswith("#"):
            failures.append(f"{relative}: first non-empty line must be a heading")

        for target in LINK.findall(text):
            if target.startswith("#") or "://" in target:
                continue
            clean = target.split("#", 1)[0]
            resolved = (ROOT / relative.parent / clean).resolve()
            if clean and not resolved.is_relative_to(ROOT.resolve()):
                failures.append(f"{relative}: link escapes repository: {target}")
            elif clean and not resolved.exists():
                failures.append(f"{relative}: broken relative link: {target}")


def main() -> int:
    failures: list[str] = []
    try:
        files = repository_files()
    except ValueError as exc:
        print(f"publication safety: FAIL\n{exc}")
        return 1

    present = set(files)
    missing = sorted(REQUIRED_FILES - present)
    failures.extend(f"missing required file: {path}" for path in missing)

    license_files = [path for path in files if path.name.upper().startswith("LICENSE")]
    failures.extend(f"license file is not authorized: {path}" for path in license_files)

    image_suffixes = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}
    failures.extend(f"image asset is not authorized: {path}" for path in files if path.suffix.lower() in image_suffixes)

    json_files = [path for path in files if path.suffix == ".json"]
    if not json_files:
        failures.append("at least one JSON example is required")

    scanned = 0
    for relative in files:
        if relative == SELF or relative.suffix not in TEXT_SUFFIXES:
            continue
        path = ROOT / relative
        try:
            text = path.read_text(encoding="utf-8")
            text.encode("ascii")
        except (UnicodeDecodeError, UnicodeEncodeError):
            failures.append(f"{relative}: file must be ASCII text")
            continue
        scanned += 1
        scan_text(relative, text, failures)
        if relative.suffix == ".json":
            try:
                payload = json.loads(text)
            except json.JSONDecodeError as exc:
                failures.append(f"{relative}: invalid JSON: {exc}")
                continue
            if not isinstance(payload, dict) or payload.get("synthetic") is not True:
                failures.append(f"{relative}: JSON example must declare synthetic true")

    if failures:
        print("publication safety: FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"publication safety: PASS ({scanned} text files, {len(json_files)} JSON examples)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
