extends Node3D
## CoopArena – Scène de survie coopérative en ligne (vagues infinies).
##
## L'hôte spawne les deux joueurs via MultiplayerSpawner.
## La sync de position/HP est gérée par Player._rpc_sync_transform() (RPC unreliable).
## Le WaveManager (Étape 3) s'attache à ce nœud.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

## Positions de départ : slot 0 = hôte (peer 1), slot 1 = client.
const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-3.0, 1.0, 0.0),
	Vector3( 3.0, 1.0, 0.0),
]

## { peer_id (int) → Player node }
var _player_nodes: Dictionary = {}


# ── Cycle de vie ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ── Nœud racine des joueurs (requis par MultiplayerSpawner) ──────────────
	var players_root := Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	# ── Spawner : propage les instantiations hôte → clients automatiquement ──
	var spawner := MultiplayerSpawner.new()
	spawner.name         = "PlayerSpawner"
	spawner.spawn_path   = NodePath("../Players")
	spawner.add_spawnable_scene(PLAYER_SCENE)
	add_child(spawner)

	# ── Signaux NetworkManager ────────────────────────────────────────────────
	NetworkManager.player_left.connect(_on_player_left)

	# ── Seul l'hôte spawne (le spawner propage vers les clients) ─────────────
	if multiplayer.is_server():
		await get_tree().create_timer(0.3).timeout
		_spawn_all_players()


# ── Spawn ──────────────────────────────────────────────────────────────────────

func _spawn_all_players() -> void:
	var keys: Array = NetworkManager.players.keys()
	for i: int in keys.size():
		_spawn_player(int(keys[i]), i)


func _spawn_player(peer_id: int, slot: int) -> void:
	var player: Node = load(PLAYER_SCENE).instantiate()

	# Nom unique et stable (requis par MultiplayerSpawner pour le path)
	player.name = str(peer_id)

	# IMPORTANT : authority AVANT add_child() → _ready() du joueur voit l'authority
	player.set_multiplayer_authority(peer_id, true)

	# Position avant insertion dans l'arbre (évite la physique parasite)
	player.position = SPAWN_POSITIONS[min(slot, SPAWN_POSITIONS.size() - 1)]

	$Players.add_child(player)
	_player_nodes[peer_id] = player
	# La sync position/HP est gérée par @rpc dans Player.gd (_rpc_sync_transform).


# ── Départ d'un joueur ────────────────────────────────────────────────────────

func _on_player_left(id: int) -> void:
	if _player_nodes.has(id):
		var node: Node = _player_nodes[id]
		_player_nodes.erase(id)
		if is_instance_valid(node):
			node.queue_free()
	_check_game_over()


func _check_game_over() -> void:
	if not multiplayer.is_server():
		return
	if _player_nodes.is_empty():
		_rpc_return_to_menu.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_return_to_menu() -> void:
	await get_tree().create_timer(2.5).timeout
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ── Accesseur pour le WaveManager (Étape 3) ───────────────────────────────────

## Retourne la liste des nœuds joueurs actuellement en vie.
func get_alive_players() -> Array:
	var result: Array = []
	for pid: int in _player_nodes:
		var node: Node = _player_nodes[pid]
		if is_instance_valid(node) and not node.get("is_dead"):
			result.append(node)
	return result
