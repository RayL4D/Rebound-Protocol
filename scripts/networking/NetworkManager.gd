extends Node

const DEFAULT_PORT : int = 7070
const MAX_PLAYERS : int = 4

signal connection_failed
signal connection_success
signal player_list_changed

var players : Dictionary = {}
var local_player_data : Dictionary = {"name": "Joueur", "skin": "default"}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game() -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	_register_player(1, local_player_data)
	return OK

func join_game(ip_address : String) -> Error:
	if ip_address.is_empty(): ip_address = "127.0.0.1"
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, DEFAULT_PORT)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	return OK

func _register_player(id : int, data : Dictionary) -> void:
	players[id] = data
	player_list_changed.emit()

@rpc("any_peer", "reliable")
func _rpc_send_player_info(data : Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	_register_player(sender_id, data)
	if multiplayer.is_server():
		_rpc_update_total_player_list.rpc(players)

@rpc("authority", "reliable")
func _rpc_update_total_player_list(server_players_dict : Dictionary) -> void:
	players = server_players_dict
	player_list_changed.emit()

func _on_player_connected(_id : int) -> void: pass
func _on_player_disconnected(id : int) -> void: players.erase(id); player_list_changed.emit()
func _on_connected_ok() -> void: connection_success.emit(); _rpc_send_player_info.rpc(local_player_data)
func _on_connected_fail() -> void: connection_failed.emit(); multiplayer.multiplayer_peer = null
func _on_server_disconnected() -> void: players.clear()

# Permet au serveur de forcer tous les clients à charger l'arène
@rpc("authority", "call_local", "reliable")
func load_arena_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
