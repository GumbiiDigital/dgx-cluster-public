#!/usr/bin/env python3
"""Minimal direct-edge ring all-reduce correctness harness.

This intentionally uses TCP sockets bound to the direct QSFP /30 IPs. It is a
software topology proof, not a production NCCL or RDMA implementation.
"""

from __future__ import annotations

import argparse
import array
import socket
import struct
import threading
import time


def exact_recv(conn: socket.socket, size: int) -> bytes:
    chunks = []
    remaining = size
    while remaining:
        chunk = conn.recv(remaining)
        if not chunk:
            raise RuntimeError(f"socket closed with {remaining} bytes remaining")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def recv_msg(conn: socket.socket) -> bytes:
    header = exact_recv(conn, 8)
    (size,) = struct.unpack("!Q", header)
    return exact_recv(conn, size)


def send_msg(conn: socket.socket, payload: bytes) -> None:
    conn.sendall(struct.pack("!Q", len(payload)))
    conn.sendall(payload)


def connect_with_retry(src_ip: str, dst_ip: str, port: int, deadline: float) -> socket.socket:
    last_error: Exception | None = None
    while time.time() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            sock.bind((src_ip, 0))
            sock.connect((dst_ip, port))
            return sock
        except OSError as exc:
            last_error = exc
            sock.close()
            time.sleep(0.2)
    raise RuntimeError(f"connect {src_ip} -> {dst_ip}:{port} failed: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rank", type=int, required=True)
    parser.add_argument("--world", type=int, default=4)
    parser.add_argument("--recv-ip", required=True)
    parser.add_argument("--send-src-ip", required=True)
    parser.add_argument("--next-ip", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--elements", type=int, default=65536)
    args = parser.parse_args()

    listen = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listen.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listen.bind((args.recv_ip, args.port))
    listen.listen(1)

    accepted: dict[str, socket.socket | tuple[str, int]] = {}

    def accept_prev() -> None:
        conn, peer = listen.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        accepted["conn"] = conn
        accepted["peer"] = peer

    accept_thread = threading.Thread(target=accept_prev, daemon=True)
    accept_thread.start()
    deadline = time.time() + 20
    send_conn = connect_with_retry(args.send_src_ip, args.next_ip, args.port, deadline)
    accept_thread.join(timeout=max(0.0, deadline - time.time()))
    if "conn" not in accepted:
        raise RuntimeError(f"rank {args.rank} did not accept prev connection on {args.recv_ip}:{args.port}")
    recv_conn = accepted["conn"]
    assert isinstance(recv_conn, socket.socket)

    value = args.rank + 1
    current = array.array("I", [value]) * args.elements
    total = array.array("I", current)
    payload = current.tobytes()
    bytes_per_msg = len(payload)

    start = time.monotonic()
    for _step in range(args.world - 1):
        send_error: list[BaseException] = []

        def do_send(data: bytes) -> None:
            try:
                send_msg(send_conn, data)
            except BaseException as exc:  # preserve background exception
                send_error.append(exc)

        sender = threading.Thread(target=do_send, args=(payload,))
        sender.start()
        payload = recv_msg(recv_conn)
        sender.join()
        if send_error:
            raise send_error[0]
        incoming = array.array("I")
        incoming.frombytes(payload)
        if len(incoming) != args.elements:
            raise RuntimeError(f"rank {args.rank} received {len(incoming)} elements")
        for i, item in enumerate(incoming):
            total[i] += item
    elapsed = time.monotonic() - start

    expected = args.world * (args.world + 1) // 2
    ok = all(item == expected for item in total)
    mib_moved = (bytes_per_msg * (args.world - 1) * 2) / (1024 * 1024)
    print(
        "RESULT "
        f"rank={args.rank} ok={int(ok)} expected={expected} first={total[0]} last={total[-1]} "
        f"bytes_per_msg={bytes_per_msg} elapsed_sec={elapsed:.6f} moved_mib={mib_moved:.3f} "
        f"send_src={send_conn.getsockname()[0]} next={args.next_ip} recv_ip={args.recv_ip} "
        f"prev_peer={accepted['peer']}"
    )
    send_conn.close()
    recv_conn.close()
    listen.close()
    return 0 if ok else 4


if __name__ == "__main__":
    raise SystemExit(main())
