extends Node
## NetworkManager – Autoload ENet listen-server + relay HTTP.
##
## Enregistrer dans project.godot :
##   NetworkManager="*res://scripts/autoloads/network_manager.gd"
##
## HÔTE  → NetworkManager.host_game("NomJoueur")  → signal room_code_ready(code)
## CLIENT → NetworkManager.join_game("ABC123", "NomJoueur") → signal connection_success
##         ou signal connection_failed(reason)
##
## Une fois les 2 joueurs dans le lobby, l'hôte appelle NetworkManager.start_game().

# ── Config ─────────────────────────────────────────────────────────────────────
## Changer RELAY_URL pour l'adresse publique du serveur en production.
const RELAY_URL  := "http://127.0.0.1:9090"
const GAME_PORT  := 7777
const MAX_PLAYERS := 2

# ── Signaux ────────────────────────────────────────────────────────────────────
signal room_code_ready(code: String)
signal connection_success()
signal connection_failed(reason: String)
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal players_updated(players: Dictionary)
signal game_started()

# ── État ───────────────────────────────────────────────────────────────────────
## { peer_id (int) → { "name": String } }
var players: Dictionary = {}
var local_player_name: String = ""
var room_code: String = ""
var is_host: bool = false

var _busy: bool = false


# ── Cycle de vie ───────────────────────────────────────────────────────────────
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ── Requête HTTP générique (nœud frais à chaque appel) ────────────────────────
## Retourne [result_code, http_status, headers, body_bytes]
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

func host_game(player_name: String) -> void:
	if _busy:
		return
	_busy = true
	local_player_name = player_name
	is_host = true

	# 1 – Démarre le serveur ENet
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		_busy = false
		connection_failed.emit("Impossible d'ouvrir le port %d (err %d)" % [GAME_PORT, err])
		return
	multiplayer.multiplayer_peer = peer

	# 2 – Ajoute l'hôte localement
	players[1] = {"name": player_name}
	players_updated.emit(players.duplicate(true))

	# 3 – Récupère l'IP publique
	var public_ip := ""
	var ip_result: Array = await _http_request("https://api64.ipify.org")
	if ip_result[0] == HTTPRequest.RESULT_SUCCESS and ip_result[1] == 200:
		public_ip = ip_result[3].get_string_from_utf8().strip_edges()
	else:
		var addrs: Array = Array(IP.get_local_addresses()).filter(
			func(a: String) -> bool:
				return not a.begins_with("127.") and not a.begins_with("::1") and ":" not in a
		)
		public_ip = addrs.front() if not addrs.is_empty() else "127.0.0.1"

	# 4 – Enregistre le salon auprès du relay
	var body := JSON.stringify({"ip": public_ip, "port": GAME_PORT, "player_name": player_name})
	var hdrs: PackedStringArray = ["Content-Type: application/json"]
	var relay: Array = await _http_request(RELAY_URL + "/host", HTTPClient.METHOD_POST, hdrs, body)
	_busy = false
	if relay[0] != HTTPRequest.RESULT_SUCCESS:
		connection_failed.emit("Relay injoignable (réseau, code %d). Le serveur relay tourne-t-il ?" % relay[0])
		return
	if relay[1] != 200:
		connection_failed.emit("Relay a répondu HTTP %d : %s" % [relay[1], relay[3].get_string_from_utf8()])
		return

	var parsed: Variant = JSON.parse_string(relay[3].get_string_from_utf8())
	if parsed == null or not (parsed as Dictionary).has("code"):
		connection_failed.emit("Réponse invalide du relay : %s" % relay[3].get_string_from_utf8())
		return

	room_code = (parsed as Dictionary)["code"]
	room_code_ready.emit(room_code)


func join_game(code: String, player_name: String) -> void:
	if _busy:
		return
	_busy = true
	local_player_name = player_name
	is_host = false
	room_code = code.to_upper().strip_edges()

	# 1 – Récupère l'adresse de l'hôte
	var result: Array = await _http_request(RELAY_URL + "/join/" + room_code)
	_busy = false
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		connection_failed.emit("Relay injoignable (code %d). Le serveur relay tourne-t-il ?" % result[0])
		return
	if result[1] == 404:
		connection_failed.emit("Salon introuvable (code : %s)." % room_code)
		return
	if result[1] != 200:
		connection_failed.emit("Relay HTTP %d : %s" % [result[1], result[3].get_string_from_utf8()])
		return

	var parsed: Variant = JSON.parse_string(result[3].get_string_from_utf8())
	if parsed == null:
		connection_failed.emit("Réponse invalide du relay.")
		return
	var info: Dictionary = parsed as Dictionary
	if not info.has("ip") or not info.has("port"):
		connection_failed.emit("Réponse invalide du relay.")
		return

	# 2 – Connexion ENet
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(info["ip"], int(info["port"]))
	if err != OK:
		connection_failed.emit("Connexion impossible à %s:%d (err %d)" % [info["ip"], int(info["port"]), err])
		return
	multiplayer.multiplayer_peer = peer
	# _on_connected_to_server se déclenche en cas de succès


func start_game() -> void:
	if not is_host:
		return
	_rpc_start_game.rpc()


func disconnect_from_game() -> void:
	_busy = false
	if room_code != "" and is_host:
		# Best-effort, fire and forget
		var req := HTTPRequest.new()
		add_child(req)
		req.request(RELAY_URL + "/host/" + room_code, [], HTTPClient.METHOD_DELETE)
		await req.request_completed
		req.queue_free()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	room_code = ""
	is_host = false


# ── Handlers ENet ──────────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Envoie la liste des joueurs existants au nouveau venu
	_rpc_receive_players.rpc_id(id, players)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_left.emit(id)
		players_updated.emit(players.duplicate(true))
		if multiplayer.is_server():
			_rpc_player_left.rpc(id)


func _on_connected_to_server() -> void:
	# On est client : on s'enregistre auprès de l'hôte
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
