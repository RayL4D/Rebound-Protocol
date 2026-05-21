#!/usr/bin/env python3
"""
Rebound Protocol – Relay Server (v2 – multi-joueurs jusqu'à 4)
---------------------------------
Maps random 6-character room codes to host info so players behind NAT
can find each other without knowing the host's public IP.
Acts as WebRTC signaling server with per-peer offer/answer.

Endpoints
---------
POST /host
    Body (JSON): {"ip": "webrtc", "lan_ip": "...", "port": 0,
                  "player_name": "Rayan", "max_players": 4}
    Response:    {"code": "ABC123"}

GET  /join/<code>
    Atomically assigns a peer_id (2, 3, 4, …) and queues the peer.
    Response: {"peer_id": 2, "ip": "...", "port": ..., "player_name": "..."}
    Or 404:   {"error": "Room not found"}
    Or 409:   {"error": "Room full"}

DELETE /host/<code>
    Response: {"ok": true}

-- WebRTC signaling (per-peer) --
GET  /signal/<code>/pending
    Returns AND clears the list of newly joined peer_ids waiting for an offer.
    Response: {"peers": [2, 3, ...]}

POST /signal/<code>/offer/<peer_id>
    Host stores its offer for peer N.
    Body: {type, sdp, candidates:[]}

GET  /signal/<code>/offer/<peer_id>
    Client N fetches the host's offer.
    Response: offer JSON or 404

POST /signal/<code>/answer/<peer_id>
    Client N stores its answer.
    Body: {type, sdp, candidates:[]}

GET  /signal/<code>/answer/<peer_id>
    Host fetches the answer from peer N.
    Response: answer JSON or 404

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
_rooms: dict = {}


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

    def _parse_signal_path(self):
        """
        Parse /signal/<code>/<kind>[/<peer_id>]
        Returns:
          (code, "pending", None)         for /signal/<code>/pending
          (code, "offer"|"answer", int)   for /signal/<code>/offer/<peer_id>
          None                            on error
        """
        if not self.path.startswith("/signal/"):
            return None
        tail = self.path[8:]  # strip "/signal/"
        parts = [p for p in tail.split("/") if p]
        if len(parts) < 2:
            return None
        code = parts[0].upper().strip()
        kind = parts[1].lower().strip()
        if kind == "pending":
            return code, kind, None
        if kind not in ("offer", "answer"):
            return None
        if len(parts) < 3:
            return None
        try:
            peer_id = int(parts[2])
        except ValueError:
            return None
        return code, kind, peer_id

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        # ── GET /join/<code> ──────────────────────────────────────────────────
        if self.path.startswith("/join/"):
            code = self.path[6:].upper().strip()
            with _lock:
                room = _rooms.get(code)
                if room is None:
                    self._send(404, {"error": "Room not found"})
                    return
                max_p = room.get("max_players", 4)
                # peer_id 1 = host, clients get 2, 3, 4, …
                if room["next_peer_id"] > max_p:
                    self._send(409, {"error": "Room full"})
                    return
                peer_id = room["next_peer_id"]
                room["next_peer_id"] += 1
                room["pending_peers"].append(peer_id)
                room["created"] = time.time()  # refresh TTL
            print(f"[relay] Peer {peer_id} joining room {code}")
            self._send(200, {
                "peer_id":     peer_id,
                "ip":          room["ip"],
                "lan_ip":      room.get("lan_ip", ""),
                "port":        room["port"],
                "player_name": room["player_name"],
            })
            return

        # ── GET /signal/… ─────────────────────────────────────────────────────
        if self.path.startswith("/signal/"):
            parsed = self._parse_signal_path()
            if parsed is None:
                self._send(404, {"error": "Not found"})
                return
            code, kind, peer_id = parsed

            with _lock:
                room = _rooms.get(code)
            if room is None:
                self._send(404, {"error": "Room not found"})
                return

            if kind == "pending":
                # Returns AND clears the pending list (atomic)
                with _lock:
                    peers = list(room["pending_peers"])
                    room["pending_peers"] = []
                self._send(200, {"peers": peers})
                return

            # offer or answer — keyed by peer_id
            data = room.get("webrtc_" + kind, {}).get(peer_id)
            if data is None:
                self._send(404, {"error": "Not ready"})
                return
            self._send(200, data)
            return

        # ── GET /ping or / ────────────────────────────────────────────────────
        if self.path in ("/ping", "/"):
            self._send(200, {"ok": True, "rooms": len(_rooms)})
            return

        self._send(404, {"error": "Not found"})

    def do_POST(self):
        # ── POST /host ────────────────────────────────────────────────────────
        if self.path == "/host":
            data = self._body()
            ip     = data.get("ip", "")
            lan_ip = data.get("lan_ip", "")
            port   = data.get("port", 0)
            name   = data.get("player_name", "Host")
            max_p  = int(data.get("max_players", 4))
            if not ip:
                self._send(400, {"error": "ip required"})
                return
            with _lock:
                code = _generate_code()
                _rooms[code] = {
                    "ip":           ip,
                    "lan_ip":       lan_ip,
                    "port":         int(port),
                    "player_name":  name,
                    "created":      time.time(),
                    "max_players":  max_p,
                    "next_peer_id": 2,       # host is always peer 1
                    "pending_peers": [],
                    "webrtc_offer":  {},     # {peer_id: offer_data}
                    "webrtc_answer": {},     # {peer_id: answer_data}
                }
            print(f"[relay] Created room {code} → {ip} ({name}, max {max_p})")
            self._send(200, {"code": code})
            return

        # ── POST /signal/… ────────────────────────────────────────────────────
        if self.path.startswith("/signal/"):
            parsed = self._parse_signal_path()
            if parsed is None:
                self._send(404, {"error": "Not found"})
                return
            code, kind, peer_id = parsed
            if kind == "pending" or peer_id is None:
                self._send(400, {"error": "peer_id required"})
                return
            with _lock:
                if code not in _rooms:
                    self._send(404, {"error": "Room not found"})
                    return
                _rooms[code]["webrtc_" + kind][peer_id] = self._body()
            print(f"[relay] Signal {kind} stored for room {code} peer {peer_id}")
            self._send(200, {"ok": True})
            return

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
