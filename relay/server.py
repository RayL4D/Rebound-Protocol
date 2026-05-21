#!/usr/bin/env python3
"""
Rebound Protocol – Relay Server
---------------------------------
Maps random 6-character room codes to (ip, port) so players behind NAT
can find each other without knowing the host's public IP.

Endpoints
---------
POST /host
    Body (JSON): {"ip": "1.2.3.4", "port": 7777, "player_name": "Rayan"}
    Response:    {"code": "ABC123"}

GET  /join/<code>
    Response:    {"ip": "1.2.3.4", "port": 7777, "player_name": "Rayan"}
    Or 404:      {"error": "Room not found"}

DELETE /host/<code>
    Response:    {"ok": true}

Rooms expire after 30 minutes.
Run: python3 relay/server.py [--host 0.0.0.0] [--port 9090]
"""

import json
import os
import random
import string
import time
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOM_TTL         = 1800   # 30 minutes
CLEANUP_INTERVAL = 60
CODE_LENGTH      = 6
CODE_CHARS       = string.ascii_uppercase + string.digits

_lock  = threading.Lock()
_rooms: dict[str, dict] = {}


def _generate_code() -> str:
    while True:
        code = "".join(random.choices(CODE_CHARS, k=CODE_LENGTH))
        if code not in _rooms:
            return code


def _cleanup():
    now = time.time()
    with _lock:
        expired = [c for c, r in _rooms.items() if now - r["created"] > ROOM_TTL]
        for c in expired:
            del _rooms[c]
    t = threading.Timer(CLEANUP_INTERVAL, _cleanup)
    t.daemon = True
    t.start()


class RelayHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"[relay] {self.address_string()} – {fmt % args}")

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except Exception:
            return {}

    def _send(self, status: int, payload: dict):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/join/"):
            code = self.path[6:].upper().strip()
            with _lock:
                room = _rooms.get(code)
            if room is None:
                self._send(404, {"error": "Room not found"})
                return
            with _lock:
                if code in _rooms:
                    _rooms[code]["created"] = time.time()  # refresh TTL
            self._send(200, {"ip": room["ip"], "lan_ip": room.get("lan_ip", ""),
                             "port": room["port"], "player_name": room["player_name"]})
        elif self.path in ("/ping", "/"):
            self._send(200, {"ok": True, "rooms": len(_rooms)})
        else:
            self._send(404, {"error": "Not found"})

    def do_POST(self):
        if self.path == "/host":
            data = self._body()
            ip     = data.get("ip", "")
            lan_ip = data.get("lan_ip", "")
            port   = data.get("port", 0)
            name   = data.get("player_name", "Host")
            if not ip or not port:
                self._send(400, {"error": "ip and port required"})
                return
            with _lock:
                code = _generate_code()
                _rooms[code] = {"ip": ip, "lan_ip": lan_ip, "port": int(port),
                                "player_name": name, "created": time.time()}
            print(f"[relay] Created room {code} → {ip} / LAN {lan_ip}:{port} ({name})")
            self._send(200, {"code": code})
        else:
            self._send(404, {"error": "Not found"})

    def do_DELETE(self):
        if self.path.startswith("/host/"):
            code = self.path[6:].upper().strip()
            with _lock:
                removed = _rooms.pop(code, None)
            if removed:
                print(f"[relay] Removed room {code}")
                self._send(200, {"ok": True})
            else:
                self._send(404, {"error": "Room not found"})
        else:
            self._send(404, {"error": "Not found"})


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    # Render (et la plupart des clouds) injectent la variable PORT automatiquement.
    # En local, on tombe sur 9090 par défaut.
    parser.add_argument("--port", type=int,
                        default=int(os.environ.get("PORT", 9090)))
    args = parser.parse_args()

    _cleanup()
    server = HTTPServer((args.host, args.port), RelayHandler)
    print(f"[relay] Listening on {args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[relay] Shutting down.")
        server.server_close()