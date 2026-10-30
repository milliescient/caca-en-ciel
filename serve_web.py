#!/usr/bin/env python3
"""Serve the exported web build of tadoussac to the LAN over HTTPS.

Godot's web export refuses to start outside a secure context, and the Web Audio
worklet it needs is secure-context-only too, so plain http will not do. The cert
is self-signed, which means a browser warning on first visit that has to be
clicked through once per device.
"""

import functools
import http.server
import socketserver
import ssl
import sys
import threading
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8443
REDIRECT_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
ROOT = Path(__file__).parent / "build" / "web"
CERT_DIR = Path.home() / ".local" / "share" / "totoro-web"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class RedirectHandler(http.server.BaseHTTPRequestHandler):
    """Bounce anyone who types a bare address over to the https port."""

    def do_GET(self):
        host = self.headers.get("Host", "").split(":")[0]
        self.send_response(301)
        self.send_header("Location", f"https://{host}:{PORT}/index.html")
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    redirect = Server(("0.0.0.0", REDIRECT_PORT), RedirectHandler)
    threading.Thread(target=redirect.serve_forever, daemon=True).start()
    print(f"Redirecting http port {REDIRECT_PORT} -> https {PORT}", flush=True)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT_DIR / "cert.pem", CERT_DIR / "key.pem")

    handler = functools.partial(Handler, directory=str(ROOT))
    with Server(("0.0.0.0", PORT), handler) as httpd:
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
        print(f"Serving {ROOT} at https://0.0.0.0:{PORT}", flush=True)
        httpd.serve_forever()
