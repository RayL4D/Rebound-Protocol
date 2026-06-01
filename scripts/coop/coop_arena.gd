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
## Sol à y ≈ 749.22 ; on spawne à y = 751 pour atterrir proprement sans flotter.
const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(354.0, 751.0, -512.0),
	Vector3(364.0, 751.0, -512.0),
	Vector3(354.0, 751.0, -522.0),
	Vector3(364.0, 751.0, -522.0),
]

## { peer_id (int) → Player node }
var _player_nodes: Dictionary = {}

## Guards pour le chemin "retour au menu"
var _returning_to_menu:    bool = false
var _was_fully_connected:  bool = false  # true dès qu'on a vu CONNECTION_CONNECTED

## Overlay "hôte parti" — créé au chargement de la scène, masqué par défaut.
## On le montre au bon moment plutôt que de le créer en pleine déconnexion WebRTC.
var _host_left_overlay: CanvasLayer = null


# ── Cycle de vie ───────────────────────────────────────────────────────────────

func _ready() -> void:
	_prewarm_bullet_shaders()
	
	# ── Supprime le joueur statique placé dans la scène (test/prévisualisation)
	if has_node("Player"):
		$Player.hide()
		$Player.set_process(false)
		$Player.set_physics_process(false)
		$Player.queue_free()

	# ── Corrige les MeshInstance3D sans matériau
	_fix_null_materials(self)

	# ── Spawner de Joueurs ───────────────────────────────────────────────────
	var players_root := Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	var spawner := MultiplayerSpawner.new()
	spawner.name           = "PlayerSpawner"
	spawner.spawn_path     = NodePath("../Players")
	spawner.spawn_function = _spawn_player_from_data
	add_child(spawner)
	CollisionManager.add_missing_collisions(self)
	
	# ── Spawner d'Ennemis ────────────────────────────────────────────────────
	var enemies_root := Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	var enemy_spawner := MultiplayerSpawner.new()
	enemy_spawner.name = "EnemySpawner"
	enemy_spawner.spawn_path = NodePath("../Enemies")
	enemy_spawner.spawn_function = _spawn_enemy_from_data
	add_child(enemy_spawner)

	# ── Spawner de Vaisseaux (Dropships) ─────────────────────────────────────
	var dropships_root := Node3D.new()
	dropships_root.name = "Dropships"
	add_child(dropships_root)

	var dropship_spawner := MultiplayerSpawner.new()
	dropship_spawner.name = "DropshipSpawner"
	dropship_spawner.spawn_path = NodePath("../Dropships")
	dropship_spawner.spawn_function = _spawn_dropship_from_data
	add_child(dropship_spawner)
	
	$Wave_manager_coop.setup_spawners(enemy_spawner, dropship_spawner)
	
	# ── Signaux NetworkManager ────────────────────────────────────────────────
	NetworkManager.player_left.connect(_on_player_left)

	# ── Client : pré-construction de l'overlay + détection du départ de l'hôte ──
	if not multiplayer.is_server():
		_was_fully_connected = true
		_host_left_overlay = _build_host_left_overlay()

		multiplayer.peer_disconnected.connect(func(id: int):
			if id == 1:
				_trigger_host_left()
		)
		multiplayer.server_disconnected.connect(func(): _trigger_host_left())
		NetworkManager.connection_failed.connect(func(_r: String): _trigger_host_left())

	# ── Seul l'hôte déclenche le spawn ────────────────────────────────────────
	if multiplayer.is_server():
		await get_tree().create_timer(0.3).timeout
		_spawn_all_players()


func _prewarm_bullet_shaders() -> void:
	const SCENE = preload("res://scenes/projectiles/bullet_enemy.tscn")
	var dummy: Node3D = SCENE.instantiate() as Node3D
	dummy.position = Vector3(0.0, -500.0, 0.0)
	add_child(dummy)
	await get_tree().process_frame
	if is_instance_valid(dummy):
		dummy.queue_free()


func _process(_delta: float) -> void:
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


# ── Spawn des Joueurs ──────────────────────────────────────────────────────────

func _spawn_all_players() -> void:
	var keys: Array = NetworkManager.players.keys()
	for i: int in keys.size():
		$PlayerSpawner.spawn({ "peer_id": int(keys[i]), "slot": i })
		
	await get_tree().process_frame
	$Wave_manager_coop.start()


func _spawn_player_from_data(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var slot:    int = data["slot"]

	var player: Node = load(PLAYER_SCENE).instantiate()
	player.name = str(peer_id)

	player.set("player_slot", slot)
	player.set_multiplayer_authority(peer_id, true)
	player.position = SPAWN_POSITIONS[min(slot, SPAWN_POSITIONS.size() - 1)]
	_player_nodes[peer_id] = player

	_add_name_label(player, peer_id)

	return player


func _add_name_label(player: Node, peer_id: int) -> void:
	var info: Dictionary    = NetworkManager.players.get(peer_id, {})
	var player_name: String = info.get("name", "Joueur %d" % peer_id)
	var is_local: bool      = (peer_id == multiplayer.get_unique_id())

	var label := Label3D.new()
	label.name             = "NameLabel"
	label.text             = player_name
	label.position         = Vector3(0.0, 1.9, 0.0)
	label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test    = true
	label.font_size        = 48
	label.pixel_size       = 0.006
	label.outline_size     = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate         = Color(0.4, 1.0, 0.85, 1.0) if is_local else Color(1.0, 1.0, 1.0, 0.9)
	player.add_child(label)


# ── Spawn des Vaisseaux et Ennemis (MultiplayerSpawner Custom) ────────────────

func _spawn_dropship_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data["ship_path"])
	var ship = scene.instantiate()
	ship.global_position = data["pos"]
	
	# Le serveur configure la cargaison, le client lit juste l'animation
	if multiplayer.is_server():
		ship.mob_scene = load(data["mob_path"])
		ship.spawn_count = data["amount"]
		ship.enemy_spawner = $EnemySpawner
		
	return ship

func _spawn_enemy_from_data(data: Dictionary) -> Node:
	var scene: PackedScene = load(data["path"])
	var mob = scene.instantiate()
	
	# Position et rotation exactes partagées par le réseau
	mob.global_position = data["pos"]
	mob.global_rotation.y = data["rot_y"]
	
	return mob


# ── Départ de l'hôte ──────────────────────────────────────────────────────────

func _trigger_host_left() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true

	if is_instance_valid(_host_left_overlay):
		_host_left_overlay.visible = true

	await get_tree().create_timer(2.5).timeout

	if is_instance_valid(_host_left_overlay):
		_host_left_overlay.queue_free()
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _build_host_left_overlay() -> CanvasLayer:
	var font: FontFile = null
	if ResourceLoader.exists("res://ui_theme/fonts/Xolonium-Regular.ttf"):
		font = load("res://ui_theme/fonts/Xolonium-Regular.ttf") as FontFile

	var layer := CanvasLayer.new()
	layer.layer   = 128
	layer.visible = false
	get_tree().root.add_child(layer)

	var root_ctrl := Control.new()
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root_ctrl)
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.size       = get_viewport().get_visible_rect().size
	root_ctrl.modulate.a = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.01, 0.04, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color   = Color(0.006, 0.012, 0.026)
	ps.border_color = Color(0.80, 0.14, 0.14)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(0)
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var outer_vb := VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 0)
	panel.add_child(outer_vb)

	var cyan_line := ColorRect.new()
	cyan_line.color = Color(0.0, 0.85, 1.0, 0.85)
	cyan_line.custom_minimum_size = Vector2(0, 2)
	outer_vb.add_child(cyan_line)

	var top_bar := ColorRect.new()
	top_bar.color = Color(0.82, 0.14, 0.14)
	top_bar.custom_minimum_size = Vector2(0, 3)
	outer_vb.add_child(top_bar)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   30)
	mc.add_theme_constant_override("margin_right",  30)
	mc.add_theme_constant_override("margin_top",    22)
	mc.add_theme_constant_override("margin_bottom", 24)
	outer_vb.add_child(mc)

	var inner_vb := VBoxContainer.new()
	inner_vb.add_theme_constant_override("separation", 0)
	mc.add_child(inner_vb)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 9)
	inner_vb.add_child(title_row)

	var lbl_icon := Label.new()
	lbl_icon.text = "✕"
	lbl_icon.add_theme_font_size_override("font_size", 20)
	lbl_icon.add_theme_color_override("font_color", Color(0.92, 0.22, 0.22))
	lbl_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font: lbl_icon.add_theme_font_override("font", font)
	title_row.add_child(lbl_icon)

	var lbl_title := Label.new()
	lbl_title.text = "CONNEXION PERDUE"
	lbl_title.add_theme_font_size_override("font_size", 22)
	lbl_title.add_theme_color_override("font_color", Color(0.92, 0.22, 0.22))
	lbl_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font: lbl_title.add_theme_font_override("font", font)
	title_row.add_child(lbl_title)

	var sp1 := Control.new(); sp1.custom_minimum_size = Vector2(0, 16)
	inner_vb.add_child(sp1)

	var sep := ColorRect.new()
	sep.color = Color(0.0, 0.85, 1.0, 0.22)
	sep.custom_minimum_size = Vector2(0, 1)
	inner_vb.add_child(sep)

	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(0, 16)
	inner_vb.add_child(sp2)

	var lbl_msg := Label.new()
	lbl_msg.text = "L'hôte a quitté la partie."
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 14)
	lbl_msg.add_theme_color_override("font_color", Color(0.78, 0.84, 0.90))
	if font: lbl_msg.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_msg)

	var sp3 := Control.new(); sp3.custom_minimum_size = Vector2(0, 22)
	inner_vb.add_child(sp3)

	var bar_container := Control.new()
	bar_container.custom_minimum_size = Vector2(0, 5)
	bar_container.size_flags_horizontal = Control.SIZE_FILL
	inner_vb.add_child(bar_container)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.12, 0.02, 0.02)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_container.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.color = Color(0.85, 0.16, 0.16)
	bar_fill.anchor_left   = 0.0
	bar_fill.anchor_top    = 0.0
	bar_fill.anchor_right  = 1.0
	bar_fill.anchor_bottom = 1.0
	bar_fill.offset_left   = 0.0
	bar_fill.offset_right  = 0.0
	bar_fill.offset_top    = 0.0
	bar_fill.offset_bottom = 0.0
	bar_container.add_child(bar_fill)

	var sp4 := Control.new(); sp4.custom_minimum_size = Vector2(0, 13)
	inner_vb.add_child(sp4)

	var lbl_sub := Label.new()
	lbl_sub.text = "Retour au menu principal…"
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 11)
	lbl_sub.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0, 0.50))
	if font: lbl_sub.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_sub)

	var bot_bar := ColorRect.new()
	bot_bar.color = Color(0.82, 0.14, 0.14, 0.35)
	bot_bar.custom_minimum_size = Vector2(0, 2)
	outer_vb.add_child(bot_bar)

	return layer


# ── Départ d'un joueur ────────────────────────────────────────────────────────

func _on_player_left(id: int) -> void:
	if _player_nodes.has(id):
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


# ── Correction matériaux nuls ─────────────────────────────────────────────────

func _fix_null_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var count := mi.mesh.get_surface_count()
			for i in count:
				var has_override := mi.get_surface_override_material(i) != null
				var has_mesh_mat := mi.mesh.surface_get_material(i) != null
				if not has_override and not has_mesh_mat:
					var fallback := StandardMaterial3D.new()
					fallback.albedo_color = Color(0.45, 0.42, 0.38)
					mi.set_surface_override_material(i, fallback)
	for child in node.get_children():
		_fix_null_materials(child)


# ── Accesseur pour le WaveManager ─────────────────────────────────────────────

func get_alive_players() -> Array:
	var result: Array = []
	for pid: int in _player_nodes:
		var node: Node = _player_nodes[pid]
		if is_instance_valid(node) and not node.get("is_dead"):
			result.append(node)
	return result
