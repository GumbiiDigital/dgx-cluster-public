#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

echo "== CRS804 management ping =="
ping -c 3 -W 1000 192.0.2.10

echo
echo "== CRS804 service check =="
python3 - <<'PY'
import socket

for port, name in [
    (21, "ftp"),
    (22, "ssh"),
    (23, "telnet"),
    (80, "www"),
    (443, "https"),
    (8291, "winbox"),
    (8728, "api"),
    (8729, "api-ssl"),
]:
    sock = socket.socket()
    sock.settimeout(1)
    result = sock.connect_ex(("192.0.2.10", port))
    sock.close()
    print(f"{port:>5} {name:<8} {'open' if result == 0 else 'closed'}")
PY

echo
echo "== Known host resolution =="
for host in workstation-a.example workstation-b.example spark-b.example spark-a.example compute-gateway.example; do
  printf '%-20s ' "$host"
  dscacheutil -q host -a name "$host" 2>/dev/null | awk '/ip_address/{print $2}' | paste -sd, -
done

echo
echo "== SSH listeners on 192.0.2.10/24 =="
python3 - <<'PY'
import concurrent.futures
import ipaddress
import socket

def has_ssh(ip):
    sock = socket.socket()
    sock.settimeout(0.2)
    try:
        return str(ip), sock.connect_ex((str(ip), 22)) == 0
    finally:
        sock.close()

with concurrent.futures.ThreadPoolExecutor(max_workers=128) as pool:
    for ip, open_ssh in pool.map(has_ssh, ipaddress.ip_network("192.0.2.10/24").hosts()):
        if open_ssh:
            print(ip)
PY
