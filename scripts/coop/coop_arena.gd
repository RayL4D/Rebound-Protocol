extends Node3D
## CoopArena – Scène de survie coopérative en ligne (vagues infinies).
##
## L'hôte spawne les joueurs via MultiplayerSpawner + spawn_function custom.
## La spawn_function tourne sur TOUS les pairs → set_multiplayer_authority() correct
## partout → caméras actives sur le bon joueur.
##
## Détection du départ de l'hôte (3 niveaux pour être robuste avec WebRTC) :
##   1. multiplayer.server_disconnected  (signal direct, le plus rapide)
##   2. NetworkManager.connection_failed (signal indirect, capture aussi les timeouts)
##   3. _process polling                 (fallback si les signaux ne se déclenchent pas)

const PLAYER_SCENE := "res://scenes/player/player.tscn"

## Positions de départ : slot 0 = hôte (peer 1), slots 1–3 = clients.
const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-3.0, 1.0,  0.0),
	Vector3( 3.0, 1.0,  0.0),
	Vector3( 0.0, 1.0, -3.0),
	Vector3( 0.0, 1.0,  3.0),
]

## { peer_id (int) → Player node }
var _player_nodes: Dictionary = {}

## Guards pour le chemin "retour au menu"
var _returning_to_menu:    bool = false
var _was_fully_connected:  bool = false  # true dès qu'on a vu CONNECTION_CONNECTED


# ── Cycle de vie ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ── Nœud racine des joueurs (requis par MultiplayerSpawner) ──────────────
	var players_root := Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	# ── Spawner avec fonction custom ─────────────────────────────────────────
	var spawner := MultiplayerSpawner.new()
	spawner.name           = "PlayerSpawner"
	spawner.spawn_path     = NodePath("../Players")
	spawner.spawn_function = _spawn_player_from_data
	add_child(spawner)

	# ── Signaux NetworkManager ────────────────────────────────────────────────
	NetworkManager.player_left.connect(_on_player_left)

	# ── Client : 3 voies de détection du départ de l'hôte ────────────────────
	if not multiplayer.is_server():
		# Voie 1 – signal direct du MultiplayerAPI (le plus réactif avec WebRTC)
		multiplayer.server_disconnected.connect(
			func(): _trigger_host_left()
		)
		# Voie 2 – signal NetworkManager (timeout, relay, autres raisons)
		NetworkManager.connection_failed.connect(
			func(_r: String): _trigger_host_left()
		)

	# ── Seul l'hôte déclenche le spawn ────────────────────────────────────────
	if multiplayer.is_server():
		await get_tree().create_timer(0.3).timeout
		_spawn_all_players()


func _process(_delta: float) -> void:
	# ── Voie 3 – polling de secours (WebRTC peut ne pas émettre les signaux) ──
	if _returning_to_menu or multiplayer.is_server():
		return

	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return

	var status: int = peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		_was_fully_connected = true
	elif _was_fully_connected and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_trigger_host_left()


# ── Spawn ──────────────────────────────────────────────────────────────────────

func _spawn_all_players() -> void:
	var keys: Array = NetworkManager.players.keys()
	for i: int in keys.size():
		$PlayerSpawner.spawn({ "peer_id": int(keys[i]), "slot": i })


## Fonction de spawn appelée sur TOUS les pairs par le MultiplayerSpawner.
func _spawn_player_from_data(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var slot:    int = data["slot"]

	var player: Node = load(PLAYER_SCENE).instantiate()
	player.name = str(peer_id)

	# Authority définie AVANT add_child → is_multiplayer_authority() correct dès l'insertion.
	player.set_multiplayer_authority(peer_id, true)
	player.position = SPAWN_POSITIONS[min(slot, SPAWN_POSITIONS.size() - 1)]
	_player_nodes[peer_id] = player

	return player


# ── Départ de l'hôte ──────────────────────────────────────────────────────────

## Point d'entrée unique pour toutes les voies de détection.
## Le flag _returning_to_menu garantit qu'on ne passe qu'une seule fois.
func _trigger_host_left() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	_show_host_left_overlay()
	await get_tree().create_timer(2.0).timeout
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Overlay "connexion perdue" affiché pendant 2 secondes.
func _show_host_left_overlay() -> void:
	var font: FontFile = null
	if ResourceLoader.exists("res://ui_theme/fonts/Xolonium-Regular.ttf"):
		font = load("res://ui_theme/fonts/Xolonium-Regular.ttf") as FontFile

	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)

	# Control intermédiaire pour le fade-in (CanvasLayer n'a pas de modulate)
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.modulate.a = 0.0
	layer.add_child(root_ctrl)

	# Fond sombre
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	# Panneau centré
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.012, 0.022, 0.038)
	ps.border_color = Color(0.95, 0.22, 0.22)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(4)
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var outer_vb := VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 0)
	panel.add_child(outer_vb)

	# Barre rouge en haut
	var top_bar := ColorRect.new()
	top_bar.color = Color(0.95, 0.22, 0.22, 0.90)
	top_bar.custom_minimum_size = Vector2(0, 4)
	outer_vb.add_child(top_bar)

	# Contenu avec marges
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   28)
	mc.add_theme_constant_override("margin_right",  28)
	mc.add_theme_constant_override("margin_top",    20)
	mc.add_theme_constant_override("margin_bottom", 22)
	outer_vb.add_child(mc)

	var inner_vb := VBoxContainer.new()
	inner_vb.add_theme_constant_override("separation", 10)
	mc.add_child(inner_vb)

	var lbl_title := Label.new()
	lbl_title.text = "CONNEXION PERDUE"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 24)
	lbl_title.add_theme_color_override("font_color", Color(0.95, 0.22, 0.22))
	if font: lbl_title.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_title)

	var sep := ColorRect.new()
	sep.color = Color(0.0, 0.851, 1.0, 0.18)
	sep.custom_minimum_size = Vector2(0, 1)
	inner_vb.add_child(sep)

	var lbl_msg := Label.new()
	lbl_msg.text = "L'hôte a quitté la partie."
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 14)
	lbl_msg.add_theme_color_override("font_color", Color(0.88, 0.92, 0.96))
	if font: lbl_msg.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_msg)

	var lbl_sub := Label.new()
	lbl_sub.text = "Retour au menu principal…"
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 11)
	lbl_sub.add_theme_color_override("font_color", Color(0.0, 0.851, 1.0, 0.50))
	if font: lbl_sub.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_sub)

	# Barre rouge en bas
	var bot_bar := ColorRect.new()
	bot_bar.color = Color(0.95, 0.22, 0.22, 0.55)
	bot_bar.custom_minimum_size = Vector2(0, 3)
	outer_vb.add_child(bot_bar)

	# Fade-in
	var tw := root_ctrl.create_tween()
	tw.tween_property(root_ctrl, "modulate:a", 1.0, 0.30)


# ── Départ d'un joueur ────────────────────────────────────────────────────────

func _on_player_left(id: int) -> void:
	if _player_nodes.has(id):
		# Variable non typée : évite l'erreur si le nœud est déjà freed.
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
	if _returning_to_menu:
		return
	_returning_to_menu = true
	await get_tree().create_timer(2.5).timeout
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ── Accesseur pour le WaveManager ─────────────────────────────────────────────

func get_alive_players() -> Array:
	var result: Array = []
	for pid: int in _player_nodes:
		var node: Node = _player_nodes[pid]
		if is_instance_valid(node) and not node.get("is_dead"):
			result.append(node)
	return result
