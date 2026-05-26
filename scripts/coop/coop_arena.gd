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


# ── Cycle de vie ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ── Supprime le joueur statique placé dans la scène (test/prévisualisation)
	# Il entrerait en conflit avec les joueurs spawnés dynamiquement.
	if has_node("Player"):
		$Player.queue_free()

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
	CollisionManager.add_missing_collisions(self)

	# ── Signaux NetworkManager ────────────────────────────────────────────────
	NetworkManager.player_left.connect(_on_player_left)

	# ── Client : 3 voies de détection du départ de l'hôte ────────────────────
	if not multiplayer.is_server():
		# Voie 1 – peer_disconnected filtré sur id==1 (le plus fiable avec WebRTC ;
		# server_disconnected n'est pas toujours émis selon l'implémentation WebRTC).
		multiplayer.peer_disconnected.connect(func(id: int):
			if id == 1:
				_trigger_host_left()
		)
		# Voie 2 – server_disconnected (redondant mais fiable sur d'autres transports)
		multiplayer.server_disconnected.connect(func(): _trigger_host_left())
		# Voie 3 – signal NetworkManager (timeout, relay, autres raisons)
		NetworkManager.connection_failed.connect(func(_r: String): _trigger_host_left())

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

	# Slot co-op → modèle + texture différents par joueur.
	# Doit être défini AVANT add_child() pour que _ready() y accède.
	player.set("player_slot", slot)

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


## Overlay "connexion perdue" amélioré : fond, panneau cyberpunk, barre de
## compte à rebours et animation d'entrée (slide-down + fade-in).
func _show_host_left_overlay() -> void:
	var font: FontFile = null
	if ResourceLoader.exists("res://ui_theme/fonts/Xolonium-Regular.ttf"):
		font = load("res://ui_theme/fonts/Xolonium-Regular.ttf") as FontFile

	# ── CanvasLayer ──────────────────────────────────────────────────────────
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)

	# root_ctrl : plein écran, gère le fade-in et le slide-down global.
	# add_child d'abord → puis set_anchors_and_offsets_preset → puis size explicite.
	var root_ctrl := Control.new()
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root_ctrl)
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.size    = get_viewport().get_visible_rect().size
	root_ctrl.modulate.a = 0.0
	root_ctrl.position.y = -14.0   # décalage initial pour l'animation slide-down

	# Fond sombre bleu nuit
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.01, 0.04, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	# CenterContainer pour centrer le panneau
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	# ── Panneau principal ────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color   = Color(0.006, 0.012, 0.026)
	ps.border_color = Color(0.80, 0.14, 0.14)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(0)   # Coins carrés → look cyberpunk
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var outer_vb := VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 0)
	panel.add_child(outer_vb)

	# Ligne cyan fine (accent haut)
	var cyan_line := ColorRect.new()
	cyan_line.color = Color(0.0, 0.85, 1.0, 0.85)
	cyan_line.custom_minimum_size = Vector2(0, 2)
	outer_vb.add_child(cyan_line)

	# Barre rouge header
	var top_bar := ColorRect.new()
	top_bar.color = Color(0.82, 0.14, 0.14)
	top_bar.custom_minimum_size = Vector2(0, 3)
	outer_vb.add_child(top_bar)

	# Contenu avec marges
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left",   30)
	mc.add_theme_constant_override("margin_right",  30)
	mc.add_theme_constant_override("margin_top",    22)
	mc.add_theme_constant_override("margin_bottom", 24)
	outer_vb.add_child(mc)

	var inner_vb := VBoxContainer.new()
	inner_vb.add_theme_constant_override("separation", 0)
	mc.add_child(inner_vb)

	# ── Titre : icône ✕ + texte ──────────────────────────────────────────────
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

	# Espace
	var sp1 := Control.new(); sp1.custom_minimum_size = Vector2(0, 16)
	inner_vb.add_child(sp1)

	# Séparateur cyan subtil
	var sep := ColorRect.new()
	sep.color = Color(0.0, 0.85, 1.0, 0.22)
	sep.custom_minimum_size = Vector2(0, 1)
	inner_vb.add_child(sep)

	# Espace
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(0, 16)
	inner_vb.add_child(sp2)

	# Message principal
	var lbl_msg := Label.new()
	lbl_msg.text = "L'hôte a quitté la partie."
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 14)
	lbl_msg.add_theme_color_override("font_color", Color(0.78, 0.84, 0.90))
	if font: lbl_msg.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_msg)

	# Espace
	var sp3 := Control.new(); sp3.custom_minimum_size = Vector2(0, 22)
	inner_vb.add_child(sp3)

	# ── Barre de compte à rebours ────────────────────────────────────────────
	# bar_container : hauteur fixe, s'étire en largeur dans le VBox
	var bar_container := Control.new()
	bar_container.custom_minimum_size = Vector2(0, 5)
	bar_container.size_flags_horizontal = Control.SIZE_FILL
	inner_vb.add_child(bar_container)

	# Fond sombre de la barre
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.12, 0.02, 0.02)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_container.add_child(bar_bg)

	# Remplissage rouge (anchor_right 1→0 = barre qui se vide de droite à gauche)
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

	# Espace
	var sp4 := Control.new(); sp4.custom_minimum_size = Vector2(0, 13)
	inner_vb.add_child(sp4)

	# Sous-titre
	var lbl_sub := Label.new()
	lbl_sub.text = "Retour au menu principal…"
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 11)
	lbl_sub.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0, 0.50))
	if font: lbl_sub.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_sub)

	# Barre rouge bas (atténuée)
	var bot_bar := ColorRect.new()
	bot_bar.color = Color(0.82, 0.14, 0.14, 0.35)
	bot_bar.custom_minimum_size = Vector2(0, 2)
	outer_vb.add_child(bot_bar)

	# ── Animations ───────────────────────────────────────────────────────────
	var tw := root_ctrl.create_tween()
	tw.set_parallel(true)
	# Fond : fade-in rapide
	tw.tween_property(root_ctrl, "modulate:a", 1.0, 0.22)
	# Panneau : slide-down (position Y -14 → 0, ease out cubic)
	tw.tween_property(root_ctrl, "position:y", 0.0, 0.32) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Barre de compte à rebours : se vide en 2s (délai 0.1s pour laisser le fade finir)
	tw.tween_property(bar_fill, "anchor_right", 0.0, 2.0) \
		.set_delay(0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_LINEAR)


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
