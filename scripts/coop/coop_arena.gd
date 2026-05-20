extends Node3D
## CoopArena – Scène de survie coopérative en ligne (vagues infinies).
##
## L'hôte spawne les deux joueurs via MultiplayerSpawner + spawn_function custom.
## La spawn_function est exécutée DES DEUX CÔTÉS (hôte et client), ce qui permet
## d'appeler set_multiplayer_authority() sur le client — sans ça, tous les joueurs
## auraient l'autorité 1 par défaut sur le client → caméras désactivées → écran gris.
##
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

	# ── Spawner avec fonction custom ─────────────────────────────────────────
	# IMPORTANT : on utilise spawn_function au lieu de add_spawnable_scene().
	# Cela permet de passer le peer_id dans les données de spawn et d'appeler
	# set_multiplayer_authority() sur TOUS les pairs (hôte ET client).
	# Sans ça, le client ne sait pas quel joueur lui appartient → écran gris.
	var spawner := MultiplayerSpawner.new()
	spawner.name        = "PlayerSpawner"
	spawner.spawn_path  = NodePath("../Players")
	spawner.spawn_function = _spawn_player_from_data
	add_child(spawner)

	# ── Signaux NetworkManager ────────────────────────────────────────────────
	NetworkManager.player_left.connect(_on_player_left)

	# ── Seul l'hôte déclenche le spawn (le spawner propage vers les clients) ──
	if multiplayer.is_server():
		await get_tree().create_timer(0.3).timeout
		_spawn_all_players()


# ── Spawn ──────────────────────────────────────────────────────────────────────

func _spawn_all_players() -> void:
	var keys: Array = NetworkManager.players.keys()
	for i: int in keys.size():
		# spawn() appelle _spawn_player_from_data sur l'hôte ET envoie les données
		# au client qui appelle aussi _spawn_player_from_data de son côté.
		$PlayerSpawner.spawn({ "peer_id": int(keys[i]), "slot": i })


## Fonction de spawn appelée sur TOUS les pairs (hôte et clients) par le MultiplayerSpawner.
## Retourne le nœud créé — le spawner l'ajoute lui-même dans spawn_path ($/Players).
func _spawn_player_from_data(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var slot:    int = data["slot"]

	var player: Node = load(PLAYER_SCENE).instantiate()

	# Nom unique et stable (requis par MultiplayerSpawner pour le path)
	player.name = str(peer_id)

	# IMPORTANT : authority définie AVANT que le spawner ajoute le nœud à l'arbre.
	# Comme cette fonction tourne sur le client aussi, le client connaît l'autorité
	# correcte dès le début → is_multiplayer_authority() retourne true pour le bon joueur.
	player.set_multiplayer_authority(peer_id, true)

	# Position avant insertion dans l'arbre (évite la physique parasite)
	player.position = SPAWN_POSITIONS[min(slot, SPAWN_POSITIONS.size() - 1)]

	# Référence locale (utile pour get_alive_players et _on_player_left)
	_player_nodes[peer_id] = player

	return player
	# Note : NE PAS appeler add_child ici — le MultiplayerSpawner le fait automatiquement
	# dans le nœud désigné par spawn_path (Players).


# ── Départ d'un joueur ────────────────────────────────────────────────────────

func _on_player_left(id: int) -> void:
	if _player_nodes.has(id):
		# Variable non typée intentionnellement : si le MultiplayerSpawner a déjà
		# libéré le nœud avant que ce signal ne déclenche, assigner une instance
		# freed à une variable Node typée provoque une erreur GDScript.
		var node = _player_nodes[id]
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
