extends Node
## NetworkManager – Autoload WebRTC (internet) + WebSocket (LAN) + relay HTTP.
##
## HÔTE  → NetworkManager.host_game("NomJoueur")  → signal room_code_ready(code)
## CLIENT → NetworkManager.join_game("ABC123", "NomJoueur") → signal connection_success
##         ou signal connection_failed(reason)
##
## Mode LAN : host_lan / join_lan  (WebSocket TCP, même réseau)
## Mode Internet : host_game / join_game  (WebRTC + STUN, cross-réseau)

# ── Config ─────────────────────────────────────────────────────────────────────
const RELAY_URL_DEFAULT := "https://rebound-protocol.onrender.com"

var relay_url: String = RELAY_URL_DEFAULT
const GAME_PORT   := 7777
const MAX_PLAYERS := 2

## Serveurs STUN gratuits Google – permettent la traversée NAT sans port forwarding.
const STUN_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
]

# ── Signaux ────────────────────────────────────────────────────────────────────
signal room_code_ready(code: String)
signal connection_success()
signal connection_failed(reason: String)
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal players_updated(players: Dictionary)
signal game_started()
signal relay_awake(ok: bool)

# ── État ───────────────────────────────────────────────────────────────────────
var players: Dictionary = {}
var local_player_name: String = ""
var room_code: String = ""
var is_host: bool = false

var _busy: bool = false
var _webrtc_conn: WebRTCPeerConnection = null


# ── Cycle de vie ───────────────────────────────────────────────────────────────
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	## WebRTC nécessite un appel à poll() chaque frame pour traiter les événements.
	if _webrtc_conn != null and is_instance_valid(_webrtc_conn):
		_webrtc_conn.poll()


# ── Requête HTTP générique ────────────────────────────────────────────────────
func _http_request(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET,
		headers: PackedStringArray = [], body: String = "") -> Array:
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return [HTTPRequest.RESULT_CONNECTION_ERROR, 0, [], PackedByteArray()]
	var result: Array = await req.request_completed
	req.queue_free()
	return result


# ── API publique ───────────────────────────────────────────────────────────────

func ping_relay() -> void:
	var result: Array = await _http_request(relay_url + "/ping")
	relay_awake.emit(result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200)


func get_lan_ip() -> String:
	var addrs: Array = Array(IP.get_local_addresses()).filter(
		func(a: String) -> bool:
			return not a.begins_with("127.") and not a.begins_with("169.254.") \
				and not a.begins_with("::1") and ":" not in a
	)
	for a in addrs:
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
	return addrs.front() if not addrs.is_empty() else "127.0.0.1"


# ── Mode LAN (WebSocket TCP) ───────────────────────────────────────────────────

func host_lan(player_name: String) -> void:
	if _busy:
		return
	_busy = true
	local_player_name = player_name
	is_host = true

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT)
	if err != OK:
		_busy = false
		is_host = false
		connection_failed.emit("Impossible d'ouvrir le port %d (err %d)" % [GAME_PORT, err])
		return
	multiplayer.multiplayer_peer = peer

	players[1] = {"name": player_name}
	players_updated.emit(players.duplicate(true))

	room_code = get_lan_ip()
	room_code_ready.emit(room_code)
	_busy = false


func join_lan(host_ip: String, player_name: String) -> void:
	if _busy:
		return
	_busy = true
	local_player_name = player_name
	is_host = false
	room_code = host_ip.strip_edges()

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client("ws://%s:%d" % [room_code, GAME_PORT])
	_busy = false
	if err != OK:
		connection_failed.emit("Connexion impossible à %s:%d (err %d)" % [room_code, GAME_PORT, err])
		return
	multiplayer.multiplayer_peer = peer


# ── Mode Internet (WebRTC + STUN) ─────────────────────────────────────────────

func host_game(player_name: String) -> void:
	if _busy:
		return
	_busy = true
	local_player_name = player_name
	is_host = true

	# 1 – Réserve un code salon sur le relay
	var hdrs: PackedStringArray = ["Content-Type: application/json"]
	var body := JSON.stringify({"ip": "webrtc", "lan_ip": get_lan_ip(),
		"port": 0, "player_name": player_name})
	var relay_resp: Array = await _http_request(
		relay_url + "/host", HTTPClient.METHOD_POST, hdrs, body)
	if relay_resp[0] != HTTPRequest.RESULT_SUCCESS or relay_resp[1] != 200:
		_busy = false
		is_host = false
		connection_failed.emit("Relay injoignable. Vérifie ta connexion internet.")
		return
	var parsed: Variant = JSON.parse_string(relay_resp[3].get_string_from_utf8())
	if parsed == null or not (parsed as Dictionary).has("code"):
		_busy = false
		is_host = false
		connection_failed.emit("Relay : réponse invalide")
		return
	room_code = (parsed as Dictionary)["code"]

	# 2 – Crée le peer WebRTC (serveur = peer 1)
	var mp := WebRTCMultiplayerPeer.new()
	mp.create_server()
	multiplayer.multiplayer_peer = mp

	_webrtc_conn = WebRTCPeerConnection.new()
	_webrtc_conn.initialize({"iceServers": STUN_SERVERS})
	mp.add_peer(_webrtc_conn, 2)  # Le client aura l'ID 2

	players[1] = {"name": player_name}
	players_updated.emit(players.duplicate(true))

	# 3 – Collecte l'offer SDP et les candidats ICE
	var offer_sdp  := ""
	var offer_type := ""
	var ice_list:   Array = []

	_webrtc_conn.session_description_created.connect(
		func(type: String, sdp: String):
			_webrtc_conn.set_local_description(type, sdp)
			offer_type = type
			offer_sdp  = sdp
	)
	_webrtc_conn.ice_candidate_created.connect(
		func(media: String, index: int, cand: String):
			ice_list.append({"media": media, "index": index, "candidate": cand})
	)
	_webrtc_conn.create_offer()

	# Attend la création de l'offer (max 5s)
	var deadline := Time.get_ticks_msec() + 5000
	while offer_sdp.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if offer_sdp.is_empty():
		_busy = false
		is_host = false
		connection_failed.emit("Échec création offre WebRTC. Réseau indisponible ?")
		return

	# Attend la fin du gathering ICE (max 5s supplémentaires)
	deadline = Time.get_ticks_msec() + 5000
	while _webrtc_conn.get_gathering_state() \
			!= WebRTCPeerConnection.GATHERING_STATE_COMPLETE \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	# 4 – Envoie offer + ICE candidates au relay
	var offer_body := JSON.stringify(
		{"type": offer_type, "sdp": offer_sdp, "candidates": ice_list})
	var sr := await _http_request(
		relay_url + "/signal/" + room_code + "/offer",
		HTTPClient.METHOD_POST, hdrs, offer_body)
	_busy = false
	if sr[0] != HTTPRequest.RESULT_SUCCESS or sr[1] != 200:
		connection_failed.emit("Échec envoi offre WebRTC au relay")
		return

	room_code_ready.emit(room_code)

	# 5 – Attend la réponse du client en arrière-plan
	_poll_for_webrtc_answer()


func _poll_for_webrtc_answer() -> void:
	var hdrs: PackedStringArray = ["Content-Type: application/json"]
	for _i in 60:  # 30 secondes max
		await get_tree().create_timer(0.5).timeout
		if _webrtc_conn == null or not is_instance_valid(_webrtc_conn):
			return

		var result := await _http_request(
			relay_url + "/signal/" + room_code + "/answer")
		if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
			continue

		var data: Variant = JSON.parse_string(result[3].get_string_from_utf8())
		if data == null or not (data as Dictionary).has("sdp"):
			continue

		# Applique la réponse du client
		_webrtc_conn.set_remote_description(
			(data as Dictionary)["type"], (data as Dictionary)["sdp"])
		for cand in (data as Dictionary).get("candidates", []):
			_webrtc_conn.add_ice_candidate(
				cand["media"], cand["index"], cand["candidate"])
		return

	connection_failed.emit("Timeout : aucun joueur n'a rejoint (30s).")


func join_game(code: String, player_name: String) -> void:
	if _busy:
		return
	_busy = true
	local_player_name = player_name
	is_host = false
	room_code = code.to_upper().strip_edges()

	# 1 – Récupère l'offer WebRTC du relay (polling max 10s)
	var offer_data: Variant = null
	for _i in 20:
		var result := await _http_request(
			relay_url + "/signal/" + room_code + "/offer")
		if result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
			var d: Variant = JSON.parse_string(result[3].get_string_from_utf8())
			if d != null and (d as Dictionary).has("sdp"):
				offer_data = d
				break
		await get_tree().create_timer(0.5).timeout

	if offer_data == null:
		_busy = false
		connection_failed.emit("Salon introuvable ou expiré (code : %s)" % room_code)
		return

	# 2 – Crée le peer WebRTC (client = peer 2)
	var mp := WebRTCMultiplayerPeer.new()
	mp.create_client(2)
	multiplayer.multiplayer_peer = mp

	_webrtc_conn = WebRTCPeerConnection.new()
	_webrtc_conn.initialize({"iceServers": STUN_SERVERS})
	mp.add_peer(_webrtc_conn, 1)  # L'hôte est le peer 1

	# 3 – Collecte answer SDP et candidats ICE
	var answer_sdp  := ""
	var answer_type := ""
	var ice_list:   Array = []

	_webrtc_conn.session_description_created.connect(
		func(type: String, sdp: String):
			_webrtc_conn.set_local_description(type, sdp)
			answer_type = type
			answer_sdp  = sdp
	)
	_webrtc_conn.ice_candidate_created.connect(
		func(media: String, index: int, cand: String):
			ice_list.append({"media": media, "index": index, "candidate": cand})
	)

	# Applique l'offer de l'hôte → déclenche la création de l'answer
	_webrtc_conn.set_remote_description(
		(offer_data as Dictionary)["type"], (offer_data as Dictionary)["sdp"])
	for cand in (offer_data as Dictionary).get("candidates", []):
		_webrtc_conn.add_ice_candidate(
			cand["media"], cand["index"], cand["candidate"])

	# Attend la création de l'answer (max 5s)
	var deadline := Time.get_ticks_msec() + 5000
	while answer_sdp.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if answer_sdp.is_empty():
		_busy = false
		connection_failed.emit("Échec création réponse WebRTC")
		return

	# Attend la fin du gathering ICE (max 5s)
	deadline = Time.get_ticks_msec() + 5000
	while _webrtc_conn.get_gathering_state() \
			!= WebRTCPeerConnection.GATHERING_STATE_COMPLETE \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	# 4 – Envoie answer + ICE candidates au relay
	var hdrs: PackedStringArray = ["Content-Type: application/json"]
	var answer_body := JSON.stringify(
		{"type": answer_type, "sdp": answer_sdp, "candidates": ice_list})
	var sr := await _http_request(
		relay_url + "/signal/" + room_code + "/answer",
		HTTPClient.METHOD_POST, hdrs, answer_body)
	_busy = false
	if sr[0] != HTTPRequest.RESULT_SUCCESS or sr[1] != 200:
		connection_failed.emit("Échec envoi réponse WebRTC")
		return
	# La connexion se finalise via multiplayer.connected_to_server → _on_connected_to_server


func start_game() -> void:
	if not is_host:
		return
	_rpc_start_game.rpc()


func disconnect_from_game() -> void:
	_busy = false
	if _webrtc_conn != null and is_instance_valid(_webrtc_conn):
		_webrtc_conn.close()
	_webrtc_conn = null
	if room_code != "" and is_host:
		var req := HTTPRequest.new()
		add_child(req)
		req.request(relay_url + "/host/" + room_code, [], HTTPClient.METHOD_DELETE)
		await req.request_completed
		req.queue_free()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	room_code = ""
	is_host = false


# ── Handlers multiplayer ──────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_receive_players.rpc_id(id, players)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_left.emit(id)
		players_updated.emit(players.duplicate(true))
		if multiplayer.is_server():
			_rpc_player_left.rpc(id)


func _on_connected_to_server() -> void:
	_rpc_register_player.rpc_id(1, local_player_name)
	connection_success.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("Connexion refusée par l'hôte.")


func _on_server_disconnected() -> void:
	players.clear()
	connection_failed.emit("Connexion perdue avec l'hôte.")


# ── RPC ────────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var pinfo: Dictionary = {"name": player_name}
	players[sender_id] = pinfo
	player_joined.emit(sender_id, pinfo)
	players_updated.emit(players.duplicate(true))
	_rpc_player_joined.rpc(sender_id, pinfo)
	_rpc_players_list.rpc(players)


@rpc("authority", "reliable")
func _rpc_receive_players(existing: Dictionary) -> void:
	for id: int in existing:
		players[id] = existing[id]
	players_updated.emit(players.duplicate(true))


@rpc("authority", "reliable")
func _rpc_player_joined(id: int, info: Dictionary) -> void:
	if not players.has(id):
		players[id] = info
		player_joined.emit(id, info)
		players_updated.emit(players.duplicate(true))


@rpc("authority", "reliable")
func _rpc_player_left(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_left.emit(id)
		players_updated.emit(players.duplicate(true))


@rpc("authority", "reliable")
func _rpc_players_list(all_players: Dictionary) -> void:
	players = all_players.duplicate(true)
	players_updated.emit(players.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	game_started.emit()
