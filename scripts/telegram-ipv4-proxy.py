"""
telegram-ipv4-proxy.py — tiny local CONNECT proxy that forces IPv4.

Why: on some Thai ISPs the IPv6 route to api.telegram.org is intermittent
(connect timeouts). Python/httpx prefers IPv6 per RFC 6724, so the gateway
hangs ~10s per request on the broken IPv6 path and heartbeat stalls.
This proxy resolves every hostname with socket.AF_INET (IPv4 only) and
relays bytes — point the Hermes Telegram transport at it via:

    set TELEGRAM_PROXY=http://127.0.0.1:8899

Stdlib only. Usage:
    python telegram-ipv4-proxy.py [--port 8899] [--log path]
If the port is already bound (another instance running), it exits silently.
"""

import argparse
import socket
import socketserver
import sys
import threading


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="IPv4-forcing CONNECT proxy")
    p.add_argument("--port", type=int, default=8899)
    p.add_argument("--log", default="")
    return p.parse_args()


LOGGER = None


def log(msg: str) -> None:
    if LOGGER:
        try:
            with open(LOGGER, "a", encoding="utf-8") as f:
                f.write(msg + "\n")
        except OSError:
            pass


class ProxyHandler(socketserver.BaseRequestHandler):
    # Bound buffers; proxy only relays, never inspects payloads.
    BUFSIZE = 65536

    def handle(self) -> None:
        try:
            first = self._read_until(b"\r\n\r\n", 64 * 1024)
        except OSError:
            return
        if not first:
            return
        head = first.decode("latin-1", "replace")
        lines = head.split("\r\n")
        if not lines:
            return
        method, target, *_ = lines[0].split(" ")

        if method.upper() == "CONNECT":
            self._handle_connect(target)
        else:
            # Plain HTTP request — parse absolute URL, relay, ignore response body
            # streaming complexity (only CONNECT is used by the gateway anyway).
            try:
                import urllib.parse

                parsed = urllib.parse.urlsplit(target if target.startswith("http") else "http://" + target)
                host = parsed.hostname or "localhost"
                port = parsed.port or 80
                self._relay(host, port, first)
            except Exception as exc:  # noqa: BLE001
                log(f"HTTP relay error: {exc}")

    def _handle_connect(self, target: str) -> None:
        try:
            host, port_s = target.rsplit(":", 1)
            port = int(port_s)
        except ValueError:
            self.request.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            return
        try:
            # IPv4 ONLY — the whole point of this proxy.
            infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        except OSError as exc:
            log(f"resolve {host}:{port} -> {exc}")
            self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            return
        addr = infos[0][4]
        try:
            upstream = socket.create_connection(addr, timeout=15)
        except OSError as exc:
            log(f"connect {addr} -> {exc}")
            self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            return
        self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        log(f"CONNECT {host}:{port} -> {addr[0]}")
        self._pump(upstream)

    def _relay(self, host: str, port: int, first: bytes) -> None:
        infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        upstream = socket.create_connection(infos[0][4], timeout=15)
        upstream.sendall(first)
        self._pump(upstream)

    def _pump(self, upstream: socket.socket) -> None:
        upstream.settimeout(30)
        self.request.settimeout(30)
        stop = threading.Event()

        def forward(src: socket.socket, dst: socket.socket) -> None:
            try:
                while not stop.is_set():
                    data = src.recv(self.BUFSIZE)
                    if not data:
                        break
                    dst.sendall(data)
            except OSError:
                pass
            finally:
                stop.set()
                try:
                    dst.shutdown(socket.SHUT_WR)
                except OSError:
                    pass

        t = threading.Thread(target=forward, args=(upstream, self.request), daemon=True)
        t.start()
        try:
            while not stop.is_set():
                data = self.request.recv(self.BUFSIZE)
                if not data:
                    break
                upstream.sendall(data)
        except OSError:
            pass
        finally:
            stop.set()
            try:
                upstream.close()
            except OSError:
                pass
            t.join(timeout=2)

    def _read_until(self, marker: bytes, limit: int) -> bytes:
        data = b""
        while len(data) < limit:
            chunk = self.request.recv(4096)
            if not chunk:
                break
            data += chunk
            if marker in data:
                return data
        return data


class ThreadedProxy(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    args = parse_args()
    global LOGGER
    LOGGER = args.log
    try:
        server = ThreadedProxy(("127.0.0.1", args.port), ProxyHandler)
    except OSError as exc:
        # Port already bound = another instance is running — exit silently.
        if "in use" in str(exc).lower() or "address already in use" in str(exc).lower():
            return 0
        log(f"bind failed: {exc}")
        return 1
    log(f"telegram-ipv4-proxy listening on 127.0.0.1:{args.port} (IPv4 only)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
