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
	# ── INITIALISATION DU SYSTÈME DE SCORE ────────────────────────────────────
	# Prépare les structures de score pour le nombre exact de joueurs connectés
	ScoreManager.start_level(NetworkManager.players.size())

	_prewarm_bullet_shaders()
	# ── Supprime le joueur statique placé dans la scène (test/prévisualisation)
	# Il entrerait en conflit avec les joueurs spawnés dynamiquement.
	# On le cache d'abord pour éviter la race condition renderer (material null)
	# entre queue_free() et le rendu du frame courant.
	if has_node("Player"):
		$Player.hide()
		$Player.set_process(false)
		$Player.set_physics_process(false)
		$Player.queue_free()

	# ── Corrige les MeshInstance3D sans matériau (évite les erreurs C++ renderer)
	# La coop arena a des meshes de décor (PrismMesh, etc.) sans matériau assigné.
	_fix_null_materials(self)

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

	# ── Client : pré-construction de l'overlay + détection du départ de l'hôte ──
	if not multiplayer.is_server():
		# Si on est dans l'arène c'est qu'on était connecté → ne pas attendre _process
		_was_fully_connected = true

		# Construire l'overlay MAINTENANT pendant que la scène est stable,
		# plutôt qu'au moment de la déconnexion (moment instable pour créer des nœuds).
		_host_left_overlay = _build_host_left_overlay()

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

	# ── ACTIVATION DU CHAT UNIQUEMENT EN MULTIJOUEUR ──────────────────────────
	if multiplayer.has_multiplayer_peer() and NetworkManager.players.size() > 1:
		var local_id := multiplayer.get_unique_id()
		var local_info: Dictionary = NetworkManager.players.get(local_id, {})
		var local_name: String = local_info.get("name", "Joueur %d" % local_id)
		
		# Vérification de sécurité pour atteindre ton nœud EasyChat dans le HUD
		if has_node("HUD/WaveContainer/EasyChat"):
			$HUD/WaveContainer/EasyChat.set_player_name(local_name)
			$HUD/WaveContainer/EasyChat.enable()
			
		# ── ENREGISTREMENT DES ÉMOTES SUR EASYCHAT (MÉTHODE NATIVE) ───────────
		var chat_node = $HUD/WaveContainer/EasyChat
		
		# Sécurité : s'assurer que la ressource de configuration de l'add-on existe
		if chat_node.config == null:
			chat_node.config = load("res://addons/easychat/easychat_config.gd").new()

		var emotes = {
			"fire": "🔥",
			"gg": "👍",
			"rip": "💀",
			"love": "❤️",
			"sixseven": "⁶🤷‍♂️⁷"
		}
		
		for cmd_name in emotes:
			var emote_text = emotes[cmd_name]
			
			# On crée une ressource de commande officielle attendue par l'add-on
			var new_cmd = ChatCommand.new()
			new_cmd.command_name = cmd_name
			new_cmd.description = "Affiche l'hologramme " + emote_text
			
			# On connecte son signal d'exécution avec la recherche dynamique du joueur
			new_cmd.executed.connect(func(_args): 
				var my_id := multiplayer.get_unique_id()
				var local_player = _player_nodes.get(my_id)
				
				if is_instance_valid(local_player):
					local_player.trigger_emote(emote_text)
			)
			
			# On l'injecte directement dans la liste officielle de l'add-on
			chat_node.config.commands.append(new_cmd)


func _prewarm_bullet_shaders() -> void:
	const SCENE = preload("res://scenes/projectiles/bullet_enemy.tscn")
	var dummy: Node3D = SCENE.instantiate() as Node3D
	dummy.position = Vector3(0.0, -500.0, 0.0)
	add_child(dummy)
	await get_tree().process_frame
	if is_instance_valid(dummy):
		dummy.queue_free()


func _process(_delta: float) -> void:
	if _returning_to_menu:
		return

	# 💀 DÉTECTION DU GAME OVER (VAGUES INFINIES SUR LE SERVEUR)
	# Si la partie a commencé et que la liste des survivants est vide -> Fin de partie !
	if multiplayer.is_server():
		if not _player_nodes.is_empty() and get_alive_players().is_empty():
			_rpc_return_to_menu.rpc(ScoreManager.players_stats, ScoreManager.waves_cleared, ScoreManager.time_elapsed)
			return

	# ── Voie 3 – polling de secours (WebRTC peut ne pas émettre les signaux) ──
	if multiplayer.is_server():
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

	# ── Label de nom au-dessus de la tête ─────────────────────────────────────
	_add_name_label(player, peer_id)

	return player


## Ajoute un Label3D simple au-dessus de la tête du joueur avec son nom réseau.
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


# ── Départ de l'hôte ──────────────────────────────────────────────────────────

## Point d'entrée unique pour toutes les voies de détection.
## Le flag _returning_to_menu garantit qu'on ne passe qu'une seule fois.
func _trigger_host_left() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true

	# Afficher l'overlay pré-construit (créé au chargement, donc toujours valide)
	if is_instance_valid(_host_left_overlay):
		_host_left_overlay.visible = true

	# Attendre 2,5s pour laisser le joueur lire le message
	await get_tree().create_timer(2.5).timeout

	if is_instance_valid(_host_left_overlay):
		_host_left_overlay.queue_free()
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Construit l'overlay "connexion perdue" et l'ajoute à root (masqué).
## Appelé au chargement de la scène — contexte stable, pas à la déconnexion.
func _build_host_left_overlay() -> CanvasLayer:
	var font: FontFile = null
	if ResourceLoader.exists("res://ui_theme/fonts/Xolonium-Regular.ttf"):
		font = load("res://ui_theme/fonts/Xolonium-Regular.ttf") as FontFile

	# ── CanvasLayer ajouté sur root (pas sur self) ────────────────────────────
	# Masqué par défaut — on l'affiche via _trigger_host_left().
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
	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(0, 16)
	inner_vb.add_child(sp1)

	# Séparateur cyan subtil
	var sep := ColorRect.new()
	sep.color = Color(0.0, 0.85, 1.0, 0.22)
	sep.custom_minimum_size = Vector2(0, 1)
	inner_vb.add_child(sep)

	# Espace
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 16)
	inner_vb.add_child(sp2)

	# Message principal
	var lbl_msg := Label.new()
	lbl_msg.text = tr("UI_HOST_LEFT")
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 14)
	lbl_msg.add_theme_color_override("font_color", Color(0.78, 0.84, 0.90))
	if font: lbl_msg.add_theme_font_override("font", font)
	inner_vb.add_child(lbl_msg)

	# Espace
	var sp3 := Control.new()
	sp3.custom_minimum_size = Vector2(0, 22)
	inner_vb.add_child(sp3)

	# ── Barre de compte à rebours ────────────────────────────────────────────
	var bar_container := Control.new()
	bar_container.custom_minimum_size = Vector2(0, 5)
	bar_container.size_flags_horizontal = Control.SIZE_FILL
	inner_vb.add_child(bar_container)

	# Fond sombre de la barre
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.12, 0.02, 0.02)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_container.add_child(bar_bg)

	# Remplissage rouge (anchor_right 1→0 = barre qui se vide)
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
	var sp4 := Control.new()
	sp4.custom_minimum_size = Vector2(0, 13)
	inner_vb.add_child(sp4)

	# Sous-titre
	var lbl_sub := Label.new()
	lbl_sub.text = tr("UI_BACK_MAIN_MENU")
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

	return layer


# ── Départ d'un joueur ────────────────────────────────────────────────────────

func _on_player_left(id: int) -> void:
	if _player_nodes.has(id):
		var node = _player_nodes[id]
		_player_nodes.erase(id)
		if is_instance_valid(node):
			node.queue_free()
	
	# Si un joueur quitte brusquement la partie réseau, on relance la vérification sur le serveur
	if multiplayer.is_server() and not _returning_to_menu:
		if _player_nodes.is_empty() or get_alive_players().is_empty():
			_rpc_return_to_menu.rpc(ScoreManager.players_stats, ScoreManager.waves_cleared, ScoreManager.time_elapsed)


# ── FIN DE PARTIE ET SYNCHRONISATION ──────────────────────────────────────────

## Cet RPC reçoit les données exactes du serveur pour écraser les données locales
## avant d'ouvrir les tableaux de scores. Indispensable pour éviter la désynchronisation.
@rpc("authority", "call_local", "reliable")
func _rpc_return_to_menu(final_stats: Array, final_waves: int, final_time: float) -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	
	# Appliquer les statistiques officielles calculées par l'hôte à tous les clients
	ScoreManager.players_stats = final_stats
	ScoreManager.waves_cleared = final_waves
	ScoreManager.time_elapsed = final_time
	
	await get_tree().create_timer(2.5).timeout
	
	# On coupe proprement la connexion réseau
	NetworkManager.disconnect_from_game()
	
	# On ouvre l'écran de fin (ScoreManager s'occupera d'ouvrir score_summary)
	ScoreManager.end_level()


# ── Correction matériaux nuls ─────────────────────────────────────────────────

## Parcourt tous les MeshInstance3D de la scène et assigne un matériau gris
## neutre sur les surfaces qui n'ont ni override ni matériau dans le mesh.
## Évite les erreurs C++ "Parameter 'material' is null" du renderer Godot.
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
