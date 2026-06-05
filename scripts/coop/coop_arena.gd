extends Node3D
## CoopArena – Scène de survie coopérative en ligne (vagues infinies).
##
## Architecture réseau :
##   HOST (peer 1) : fait tourner les vagues, l'IA des ennemis, la physique.
##   CLIENTS       : reçoivent les mises à jour via RPC (XP, vagues, HP).
##
## Les ennemis existent uniquement sur le host (phase 1).
## La visibilité côté client sera ajoutée via MultiplayerSynchronizer en phase 2.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const HUD_SCENE    := "res://scenes/ui/HUD.tscn"

# Scènes des ennemis et dropship
const DROPSHIP_SCENE    := "res://scenes/enemies/dropship.tscn"
const ENEMY_DOG_SCENE   := "res://scenes/enemies/pet_dog.tscn"
const ENEMY_COW_SCENE   := "res://scenes/enemies/pet_cow.tscn"
const ENEMY_CAT_SCENE   := "res://scenes/enemies/pet_cat.tscn"
const ENEMY_BUNNY_SCENE := "res://scenes/enemies/pet_bunny.tscn"
const ENEMY_FOX_SCENE   := "res://scenes/enemies/pet_fox.tscn"
const ENEMY_PANDA_SCENE := "res://scenes/enemies/pet_panda.tscn"
const ENEMY_BOSS_SCENE  := "res://scenes/enemies/boss_lion.tscn"

## Index dans le catalogue (ordre important)
## 0=chien  1=vache  2=chat  3=lapin  4=renard  5=panda
const _CAT_DOG    := 0
const _CAT_COW    := 1
const _CAT_CAT    := 2
const _CAT_BUNNY  := 3
const _CAT_FOX    := 4
const _CAT_PANDA  := 5

## Positions de spawn des joueurs
const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(354.0, 751.0, -512.0),
	Vector3(364.0, 751.0, -512.0),
	Vector3(354.0, 751.0, -522.0),
	Vector3(364.0, 751.0, -522.0),
]

## Positions des dropships — Y = niveau du sol (≈749).
## L'animation "landing" fait monter le Dropship_container de +50 en local
## puis redescend à +1.5, donc spawner à Y=750 donne un atterrissage visuel correct.
const DROPSHIP_SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(358.0, 750.0, -472.0),  # Centre-sud
	Vector3(295.0, 750.0, -498.0),  # Flanc ouest
	Vector3(415.0, 750.0, -498.0),  # Flanc est
	Vector3(325.0, 750.0, -545.0),  # Nord-ouest
	Vector3(388.0, 750.0, -545.0),  # Nord-est
	Vector3(350.0, 750.0, -425.0),  # Grand-sud
	Vector3(283.0, 750.0, -455.0),  # Sud-ouest lointain
	Vector3(422.0, 750.0, -455.0),  # Sud-est lointain
]

# ── État joueurs ────────────────────────────────────────────────────────────────
## { peer_id (int) -> Player node }
var _player_nodes: Dictionary = {}
## { peer_id (int) -> Vector3 } — position de mort de chaque joueur ce round
var _dead_players:  Dictionary = {}

var _returning_to_menu:   bool = false
var _was_fully_connected: bool = false

var _host_left_overlay: CanvasLayer = null

# ── État vagues (host + répliqué via RPC) ──────────────────────────────────────
var _wave_manager: Node = null       # WaveManager node (host uniquement)
var _wave_number:  int  = 0
var _enemies_alive_coop: int = 0

# ── Coordination pause skill pick (host = arbitre) ─────────────────────────────
## Nombre de joueurs actuellement en train de choisir une compétence.
## Quand > 0 : tout le monde doit rester en pause.
var _skills_pending: int = 0
var _waiting_skill_ui: Node = null   # ref au SkillPickUI local en mode attente

# ── Pièces coop ───────────────────────────────────────────────────────────────
## Compteur pour générer des noms de coins uniques sur le réseau.
var _coin_id_counter: int = 0

# ── HUD co-op ───────────────────────────────────────────────────────────────────
var _coop_hud:        CanvasLayer = null
var _hud_wave_label:  Label       = null
var _hud_enemy_label: Label       = null
## { peer_id -> { bar: ColorRect, bg: ColorRect, label: Label } }
var _hp_bars: Dictionary = {}


# ── Cycle de vie ───────────────────────────────────────────────────────────────

func _ready() -> void:
	_prewarm_bullet_shaders()

	if has_node("Player"):
		$Player.hide()
		$Player.set_process(false)
		$Player.set_physics_process(false)
		$Player.queue_free()

	_fix_null_materials(self)

	# ── HUD co-op (tous les pairs) ───────────────────────────────────────────
	_coop_hud = _build_coop_hud()

	# ── Racine des joueurs ───────────────────────────────────────────────────
	var players_root := Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	# ── Spawner joueurs ──────────────────────────────────────────────────────
	var spawner := MultiplayerSpawner.new()
	spawner.name           = "PlayerSpawner"
	spawner.spawn_path     = NodePath("../Players")
	spawner.spawn_function = _spawn_player_from_data
	add_child(spawner)

	# ── Racine des ennemis (TOUS les pairs) ──────────────────────────────────
	var enemies_root := Node3D.new()
	enemies_root.name = "EnemiesRoot"
	add_child(enemies_root)

	# ── Spawner ennemis — réplique dropships + ennemis sur tous les clients ──
	var enemy_spawner := MultiplayerSpawner.new()
	enemy_spawner.name = "EnemySpawner"
	enemy_spawner.spawn_path = NodePath("../EnemiesRoot")
	enemy_spawner.add_spawnable_scene(DROPSHIP_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_DOG_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_COW_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_CAT_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_BUNNY_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_FOX_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_PANDA_SCENE)
	enemy_spawner.add_spawnable_scene(ENEMY_BOSS_SCENE)
	add_child(enemy_spawner)

	CollisionManager.add_missing_collisions(self)

	# ── Signaux réseau ────────────────────────────────────────────────────────
	NetworkManager.player_left.connect(_on_player_left)

	# ── Coordination pause skill pick ─────────────────────────────────────────
	# Tous les pairs écoutent leur XpManager local pour notifier le host.
	if multiplayer.has_multiplayer_peer():
		var xpm := get_node_or_null("/root/XpManager")
		if xpm:
			xpm.skill_pick_started.connect(_on_local_skill_pick_started)
			xpm.skill_pick_ended.connect(func(ui: Node): _on_local_skill_pick_ended(ui))

	# ── Detection des ennemis spawnés par le WaveManager (host uniquement) ──
	if multiplayer.is_server():
		get_tree().node_added.connect(_on_node_added_for_enemies)

	# ── Client : overlay départ hôte ─────────────────────────────────────────
	if not multiplayer.is_server():
		_was_fully_connected = true
		_host_left_overlay = _build_host_left_overlay()
		multiplayer.peer_disconnected.connect(func(id: int):
			if id == 1: _trigger_host_left()
		)
		multiplayer.server_disconnected.connect(func(): _trigger_host_left())
		NetworkManager.connection_failed.connect(func(_r: String): _trigger_host_left())

	# ── Hôte : spawn joueurs + démarrage des vagues ───────────────────────────
	if multiplayer.is_server():
		await get_tree().create_timer(0.3).timeout
		_spawn_all_players()
		await get_tree().create_timer(1.5).timeout
		_setup_coop_waves()


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


# ── Spawn joueurs ──────────────────────────────────────────────────────────────

func _spawn_all_players() -> void:
	var keys: Array = NetworkManager.players.keys()
	for i: int in keys.size():
		$PlayerSpawner.spawn({ "peer_id": int(keys[i]), "slot": i })


func _spawn_player_from_data(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var slot:    int = data["slot"]

	var player: Node = load(PLAYER_SCENE).instantiate()
	player.name = str(peer_id)
	player.set("player_slot", slot)
	player.set_multiplayer_authority(peer_id, true)
	player.position = SPAWN_POSITIONS[mini(slot, SPAWN_POSITIONS.size() - 1)]
	_player_nodes[peer_id] = player

	_add_name_label(player, peer_id)

	# Connecter les signaux de mort et HP après l'insertion dans la scène
	var _on_ready_cb := func():
		_add_player_hp_bar(player, peer_id)
		if peer_id == multiplayer.get_unique_id():
			player.player_died.connect(_on_local_player_died)
			# Le HUD.tscn n'a pas encore trouvé le joueur (spawné après _ready)
			# → on le connecte manuellement
			if _coop_hud != null and _coop_hud.has_method("connect_to_player"):
				_coop_hud.connect_to_player(player)
	player.ready.connect(_on_ready_cb, CONNECT_ONE_SHOT)

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


# ── Vagues d'ennemis (host uniquement) ────────────────────────────────────────

func _setup_coop_waves() -> void:
	if not multiplayer.is_server():
		return

	# EnemiesRoot est créé dans _ready() pour tous les pairs
	var enemies_root: Node3D = get_node("EnemiesRoot") as Node3D

	# Charger le WaveManager
	var wm_script: GDScript = load("res://scripts/levels/wave_manager.gd")
	var wm: Node = wm_script.new()
	wm.name              = "CoopWaveManager"
	wm.dropship_scene    = load(DROPSHIP_SCENE)
	wm.enemy_scene       = load(ENEMY_DOG_SCENE)
	wm.spawn_root        = enemies_root  # les dropships/ennemis vont dans EnemiesRoot
	wm.ignore_player_death = true
	var catalog: Array[PackedScene] = [
		load(ENEMY_DOG_SCENE),    # 0
		load(ENEMY_COW_SCENE),    # 1
		load(ENEMY_CAT_SCENE),    # 2
		load(ENEMY_BUNNY_SCENE),  # 3
		load(ENEMY_FOX_SCENE),    # 4
		load(ENEMY_PANDA_SCENE),  # 5
	]
	wm.enemy_catalog      = catalog
	wm.time_between_waves = 4.0

	# Ajouter d'abord le WaveManager dans l'arbre, PUIS configurer les marqueurs
	# (nécessaire pour que global_position soit valide)
	add_child(wm)

	var spawn_paths: Array[NodePath] = []
	for i in DROPSHIP_SPAWN_POSITIONS.size():
		var marker := Marker3D.new()
		marker.name = "DS_Spawn%d" % i
		wm.add_child(marker)
		# wm est un Node sans transform → position locale = position monde
		marker.position = DROPSHIP_SPAWN_POSITIONS[i]
		spawn_paths.append(NodePath("DS_Spawn%d" % i))
	wm.dropship_spawn_points = spawn_paths

	_wave_manager = wm

	# Connecter les signaux
	wm.wave_started.connect(_on_coop_wave_started)
	wm.all_waves_finished.connect(_on_coop_all_waves_finished)

	_wave_number = 1
	_start_next_wave()


func _start_next_wave() -> void:
	if _wave_manager == null:
		return
	var waves: Array[WaveManager.WaveData] = _make_coop_waves(_wave_number)
	_wave_manager.setup_waves(waves)
	_wave_manager.start()


## Progression des vagues :
##   1-2   → chiens uniquement
##   3-4   → chiens + lapins (rapides)
##   5     → BOSS lion + escorte chiens
##   6-7   → chiens + vaches (tankier)
##   8-9   → chiens + chats + lapins
##   10    → BOSS lion + escorte mixte
##   11-14 → mix élite (renard, panda, vache, chat)
##   15+   → BOSS + élite à chaque cycle de 5
## Difficulté : +2 ennemis / vague, jusqu'à 50 max.
func _make_coop_waves(wave_num: int) -> Array[WaveManager.WaveData]:
	var waves: Array[WaveManager.WaveData] = []

	# ── Vague boss (toutes les 5 vagues) ─────────────────────────────────────
	if wave_num % 5 == 0:
		# 1) Le boss arrive seul dans un dropship
		var boss_w := WaveManager.WaveData.new(1, 1, "BOSS_WAVE_%d" % wave_num)
		boss_w.enemy_scene = load(ENEMY_BOSS_SCENE)
		waves.append(boss_w)

		# 2) Puis une escorte proportionnelle à la vague
		var escort_count := mini(4 + wave_num, 20)
		var escort_ships := mini(2 + wave_num / 5, 4)
		var escort_w := WaveManager.WaveData.new(escort_count, escort_ships, "BOSS_ESCORT_%d" % wave_num)
		var escort_mix: Array[int] = _get_enemy_mix(wave_num)
		escort_w.enemy_mix = escort_mix
		waves.append(escort_w)
		return waves

	# ── Vague normale ────────────────────────────────────────────────────────
	var count := mini(4 + wave_num * 2, 50)
	var ships := mini(1 + wave_num / 3, 8)
	var w := WaveManager.WaveData.new(count, ships, "WAVE_COOP_%d" % wave_num)

	if wave_num <= 2:
		# Chiens uniquement
		w.enemy_index = _CAT_DOG
	else:
		var mix: Array[int] = _get_enemy_mix(wave_num)
		w.enemy_mix = mix

	waves.append(w)
	return waves


## Retourne le mix d'ennemis (indices catalogue) selon la vague.
func _get_enemy_mix(wave_num: int) -> Array[int]:
	if wave_num <= 4:
		var m: Array[int] = [_CAT_DOG, _CAT_BUNNY]
		return m
	elif wave_num <= 7:
		var m: Array[int] = [_CAT_DOG, _CAT_COW, _CAT_BUNNY]
		return m
	elif wave_num <= 10:
		var m: Array[int] = [_CAT_DOG, _CAT_COW, _CAT_CAT, _CAT_BUNNY]
		return m
	elif wave_num <= 14:
		var m: Array[int] = [_CAT_DOG, _CAT_CAT, _CAT_FOX, _CAT_COW]
		return m
	else:
		var m: Array[int] = [_CAT_DOG, _CAT_CAT, _CAT_FOX, _CAT_PANDA, _CAT_COW]
		return m


func _on_coop_wave_started(wave_index: int) -> void:
	_enemies_alive_coop = _get_enemies_alive_count()
	_rpc_update_wave_hud.rpc(_wave_number, _enemies_alive_coop)


func _on_coop_all_waves_finished() -> void:
	_wave_number += 1

	# Respawn des joueurs morts avant la prochaine vague
	if not _dead_players.is_empty():
		_respawn_dead_players()

	# Pause de 5 secondes entre les vagues (les joueurs respawnés ont le temps de se repositionner)
	await get_tree().create_timer(5.0).timeout
	_start_next_wave()


## Déclenche le respawn de tous les joueurs morts (host uniquement).
## Chaque joueur réapparaît à sa position de spawn initiale avec la moitié de ses HP.
func _respawn_dead_players() -> void:
	if not multiplayer.is_server():
		return
	for peer_id: int in _dead_players.keys():
		var player := _player_nodes.get(peer_id) as Player
		if player == null or not is_instance_valid(player):
			continue
		# Respawn à l'endroit où le joueur est mort (position stockée dans _dead_players)
		var spawn_pos: Vector3 = _dead_players[peer_id]
		if spawn_pos == Vector3.ZERO:
			# Fallback sur la position initiale de slot si la position est invalide
			var slot := clampi(int(player.get("player_slot")), 0, SPAWN_POSITIONS.size() - 1)
			spawn_pos = SPAWN_POSITIONS[slot]
		_rpc_respawn_player.rpc(peer_id, spawn_pos)
	_dead_players.clear()


## Reçu par tous les pairs. Seul le pair ciblé (peer_id) effectue le respawn.
@rpc("authority", "call_local", "reliable")
func _rpc_respawn_player(peer_id: int, spawn_pos: Vector3) -> void:
	if multiplayer.get_unique_id() != peer_id:
		return
	# Chercher le joueur local (celui dont on est l'authority)
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Player and is_instance_valid(p) and (p as Node).is_multiplayer_authority():
			(p as Player).coop_respawn(spawn_pos)
			break


## Détecte les ennemis spawnés dynamiquement et connecte leurs signaux.
func _on_node_added_for_enemies(node: Node) -> void:
	# Correction matériaux
	if node is MeshInstance3D:
		_fix_null_materials(node)
		return
	# Connexion des signaux ennemi
	# node_added se déclenche AVANT _ready() → is_in_group("enemies") serait false.
	# On utilise `node is Enemy` (classe connue à la compilation) pour être fiable.
	if node is Enemy and node.has_signal("enemy_died"):
		var xp:       int = node.get("xp_reward")     if node.get("xp_reward")     != null else 10
		var coin_min: int = node.get("coin_drop_min") if node.get("coin_drop_min") != null else 1
		var coin_max: int = node.get("coin_drop_max") if node.get("coin_drop_max") != null else 2
		# Capturer la position au moment de la mort (node encore valide quand enemy_died est émis)
		node.enemy_died.connect(func():
			var pos: Vector3 = (node as Node3D).global_position if is_instance_valid(node) else Vector3.ZERO
			_on_coop_enemy_killed(xp, randi_range(coin_min, coin_max), pos)
		)
		_enemies_alive_coop += 1
		_rpc_update_wave_hud.rpc(_wave_number, _enemies_alive_coop)


func _on_coop_enemy_killed(xp_reward: int, coin_reward: int, enemy_pos: Vector3) -> void:
	_enemies_alive_coop = maxi(0, _enemies_alive_coop - 1)
	_rpc_add_xp.rpc(xp_reward)
	# Positions pré-calculées sur le serveur → identiques pour tous les clients
	if coin_reward > 0:
		var count   := mini(coin_reward, 5)
		var val     := maxi(1, coin_reward / count)
		var ids: Array     = []
		var positions: Array = []
		var values: Array  = []
		for i in count:
			_coin_id_counter += 1
			ids.append("CC%d" % _coin_id_counter)
			positions.append(enemy_pos + Vector3(randf_range(-1.5, 1.5), 0.1, randf_range(-1.5, 1.5)))
			values.append(val)
		_rpc_spawn_coins.rpc(ids, positions, values)
	_rpc_update_wave_hud.rpc(_wave_number, _enemies_alive_coop)


func _get_enemies_alive_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			count += 1
	return count


# ── Mort des joueurs ───────────────────────────────────────────────────────────

func _on_local_player_died() -> void:
	var local_player := _player_nodes.get(multiplayer.get_unique_id()) as Player
	# Envoyer la position de mort au host pour le respawn sur place
	var death_pos := local_player.global_position if is_instance_valid(local_player) else Vector3.ZERO
	_rpc_player_died.rpc_id(1, multiplayer.get_unique_id(), death_pos)
	# Afficher l'écran de mort coop
	var death_screen  = load("res://scripts/coop/coop_death_screen.gd").new()
	death_screen.name           = "CoopDeathScreen"
	death_screen._local_player  = local_player
	get_tree().root.add_child(death_screen)


@rpc("any_peer", "call_local", "reliable")
func _rpc_player_died(peer_id: int, death_pos: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	_dead_players[peer_id] = death_pos  # stocke la position pour respawn sur place
	# Marquer dans le HUD
	_rpc_mark_player_dead.rpc(peer_id)
	# Vérifier si tous morts
	var all_dead := true
	for pid in _player_nodes:
		if not _dead_players.has(pid):
			all_dead = false
			break
	if all_dead:
		await get_tree().create_timer(2.0).timeout
		# Vérifier que la connexion est encore active avant d'envoyer le RPC
		if not is_inside_tree():
			return
		var peer := multiplayer.multiplayer_peer
		if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_rpc_game_over_coop.rpc()
		else:
			_rpc_game_over_coop()  # connexion morte — exécution locale seulement


@rpc("authority", "call_local", "reliable")
func _rpc_mark_player_dead(peer_id: int) -> void:
	if _hp_bars.has(peer_id):
		var bar_data: Dictionary = _hp_bars[peer_id]
		bar_data["bar"].color    = Color(0.4, 0.1, 0.1)
		bar_data["label"].text   = bar_data["label"].text.split(" ")[0] + " — MORT"
		bar_data["label"].add_theme_color_override("font_color", Color(0.6, 0.3, 0.3))


@rpc("authority", "call_local", "reliable")
func _rpc_game_over_coop() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	await get_tree().create_timer(2.5).timeout
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ── RPC synchronisation ────────────────────────────────────────────────────────

## Ajoute de l'XP à chaque joueur — XP partagé, skills individuels.
@rpc("authority", "call_local", "reliable")
func _rpc_add_xp(amount: int) -> void:
	if get_tree().root.has_node("XpManager"):
		XpManager.add_xp(amount)


## Fallback pièces directes (non utilisé en temps normal — coins physiques préférés).
@rpc("authority", "call_local", "reliable")
func _rpc_add_coins(amount: int) -> void:
	SaveData.add_coins(amount)


## Spawne les pièces aux mêmes positions sur tous les clients.
## Les IDs permettent l'exclusivité : le premier à ramasser supprime la pièce pour tous.
@rpc("authority", "call_local", "reliable")
func _rpc_spawn_coins(ids: Array, positions: Array, values: Array) -> void:
	var root := get_tree().current_scene
	for i in ids.size():
		Coin.spawn(root, positions[i], values[i], ids[i])


## Appelé par Coin quand un joueur local la touche.
## Notifie le serveur pour attribution exclusive.
func _network_collect_coin(coin_name: String, coin_value: int) -> void:
	var me := multiplayer.get_unique_id()
	if multiplayer.is_server():
		# L'hôte EST le serveur — appel direct pour éviter le loopback RPC ignoré
		_rpc_coin_collected(coin_name, coin_value, me)
	else:
		_rpc_coin_collected.rpc_id(1, coin_name, coin_value, me)


## Serveur reçoit la demande de collecte du premier joueur qui touche la pièce.
@rpc("any_peer", "reliable")
func _rpc_coin_collected(coin_name: String, coin_value: int, collector_peer: int) -> void:
	if not multiplayer.is_server():
		return
	# Vérifie que la pièce existe encore (pas déjà ramassée)
	if get_node_or_null(coin_name) == null:
		return
	# Attribue la pièce et la supprime pour tout le monde
	_rpc_remove_coin.rpc(coin_name, coin_value, collector_peer)


## Supprime la pièce sur tous les clients. Seul le collecteur reçoit les pièces + effets.
@rpc("authority", "call_local", "reliable")
func _rpc_remove_coin(coin_name: String, coin_value: int, collector_peer: int) -> void:
	var coin := get_node_or_null(coin_name) as Coin
	if multiplayer.get_unique_id() == collector_peer:
		SaveData.add_coins(coin_value)
		if coin != null and is_instance_valid(coin):
			coin.play_collect_effects()
	# Supprimer la pièce sur toutes les machines
	if coin != null and is_instance_valid(coin):
		coin.queue_free()


## Met à jour les infos de vague sur tous les pairs.
@rpc("authority", "call_local", "reliable")
func _rpc_update_wave_hud(wave: int, enemies: int) -> void:
	_wave_number        = wave
	_enemies_alive_coop = enemies
	if _hud_wave_label:
		_hud_wave_label.text  = "Vague %d" % wave
	if _hud_enemy_label:
		_hud_enemy_label.text = "Ennemis : %d" % enemies


# ── HUD co-op ──────────────────────────────────────────────────────────────────

# ── Coordination pause skill pick ────────────────────────────────────────────

# ── HUD co-op ──────────────────────────────────────────────────────────────────

func _build_coop_hud() -> CanvasLayer:
	# Instancie le HUD existant (HP, XP, WaveLabel, EnemiesLabel)
	var hud: CanvasLayer = load(HUD_SCENE).instantiate() as CanvasLayer
	get_tree().root.add_child(hud)

	# Récupère les labels vague/ennemis déjà présents dans HUD.tscn
	_hud_wave_label  = hud.get_node_or_null("%WaveLabel")  as Label
	_hud_enemy_label = hud.get_node_or_null("%EnemiesLabel") as Label

	if _hud_wave_label:
		_hud_wave_label.text = "Vague 1"
	if _hud_enemy_label:
		_hud_enemy_label.text = "Ennemis : 0"

	return hud


## Barre HP désactivée — HUD.tscn gère le joueur local via connect_to_player().
## Gardé comme no-op pour ne pas casser les appels existants.
func _add_player_hp_bar(_player: Node, _peer_id: int) -> void:
	pass


func _on_local_skill_pick_started() -> void:
	if multiplayer.is_server():
		_handle_skill_add()
	else:
		_rpc_skill_add.rpc_id(1)

func _on_local_skill_pick_ended(ui: Node) -> void:
	_waiting_skill_ui = ui
	# Pré-marquer l'UI en mode attente AVANT d'envoyer le RPC.
	# Sans ça, la lambda _finish de SkillPickUI appelle queue_free() avant que
	# _rpc_show_waiting_skill n'arrive, et l'UI disparaît trop tôt.
	if ui != null and is_instance_valid(ui):
		ui.set("_is_waiting", true)
	if multiplayer.is_server():
		_handle_skill_done()
	else:
		_rpc_skill_done.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_skill_add() -> void:
	if not multiplayer.is_server():
		return
	_handle_skill_add()

@rpc("any_peer", "reliable")
func _rpc_skill_done() -> void:
	if not multiplayer.is_server():
		return
	_handle_skill_done()

func _handle_skill_add() -> void:
	_skills_pending += 1
	if _skills_pending == 1:
		_rpc_pause_coop.rpc()   # premier joueur → mettre tout le monde en pause

func _handle_skill_done() -> void:
	_skills_pending = maxi(0, _skills_pending - 1)
	if _skills_pending == 0:
		_rpc_resume_coop.rpc()      # tous ont choisi → tout le monde reprend
	else:
		# Des joueurs choisissent encore :
		# - re-pause ceux qui auraient pu se dépauseré localement
		# - affiche "en attente" sur leur écran
		_rpc_pause_coop.rpc()
		_rpc_show_waiting_skill.rpc()

## Pause synchronisée pour TOUS les pairs (pendant le choix de compétence).
@rpc("authority", "call_local", "reliable")
func _rpc_pause_coop() -> void:
	get_tree().paused = true

## Reprise synchronisée pour TOUS les pairs (tous ont choisi leur compétence).
@rpc("authority", "call_local", "reliable")
func _rpc_resume_coop() -> void:
	get_tree().paused = false
	_remove_waiting_overlay()
	# Fermer l'UI de skills si elle est encore ouverte en mode attente
	if _waiting_skill_ui != null and is_instance_valid(_waiting_skill_ui):
		_waiting_skill_ui.queue_free()
	_waiting_skill_ui = null

## Affiché sur l'écran du joueur qui a déjà choisi sa compétence et attend les autres.
@rpc("authority", "call_local", "reliable")
func _rpc_show_waiting_skill() -> void:
	# Garde la fenêtre de skills ouverte avec le message d'attente
	if _waiting_skill_ui != null and is_instance_valid(_waiting_skill_ui):
		if _waiting_skill_ui.has_method("enter_waiting_mode"):
			_waiting_skill_ui.enter_waiting_mode()


func _show_waiting_overlay() -> void:
	if get_tree().root.has_node("WaitingSkillOverlay"):
		return
	var layer := CanvasLayer.new()
	layer.name  = "WaitingSkillOverlay"
	layer.layer = 62   # juste au-dessus du jeu, sous le SkillPickUI (layer 60)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)

	var lbl := Label.new()
	lbl.text = "⏳  En attente des coéquipiers…"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.85))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.offset_top = 60
	layer.add_child(lbl)


func _remove_waiting_overlay() -> void:
	var overlay := get_tree().root.get_node_or_null("WaitingSkillOverlay")
	if overlay:
		overlay.queue_free()


# ── Départ d'un joueur ────────────────────────────────────────────────────────

func _on_player_left(id: int) -> void:
	if _player_nodes.has(id):
		var node = _player_nodes[id]
		_player_nodes.erase(id)
		if is_instance_valid(node):
			node.queue_free()
		if _hp_bars.has(id):
			var data: Dictionary = _hp_bars[id]
			if is_instance_valid(data.get("bg")):
				data["bg"].get_parent().queue_free()
			_hp_bars.erase(id)
		_dead_players.erase(id)
	_check_game_over()


func _check_game_over() -> void:
	# Garde contre multiplayer null (peut arriver après déconnexion)
	if not is_inside_tree():
		return
	var mp := multiplayer
	if mp == null or not mp.has_multiplayer_peer():
		return
	if not mp.is_server():
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


# ── Utilitaires ────────────────────────────────────────────────────────────────

func _prewarm_bullet_shaders() -> void:
	const SCENE = preload("res://scenes/projectiles/bullet_enemy.tscn")
	var dummy: Node3D = SCENE.instantiate() as Node3D
	dummy.position = Vector3(0.0, -500.0, 0.0)
	add_child(dummy)
	await get_tree().process_frame
	if is_instance_valid(dummy):
		dummy.queue_free()


func _on_any_node_added(node: Node) -> void:
	if node is MeshInstance3D:
		_fix_null_materials(node)


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


func get_alive_players() -> Array:
	var result: Array = []
	for pid: int in _player_nodes:
		var node: Node = _player_nodes[pid]
		if is_instance_valid(node) and not _dead_players.has(pid):
			result.append(node)
	return result


# ── Overlay "hôte parti" ──────────────────────────────────────────────────────

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
	ps.bg_color     = Color(0.006, 0.012, 0.026)
	ps.border_color = Color(0.80, 0.14, 0.14)
	ps.set_border_width_all(1)
	ps.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var lbl_title := Label.new()
	lbl_title.text = "CONNEXION PERDUE"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 22)
	lbl_title.add_theme_color_override("font_color", Color(0.92, 0.22, 0.22))
	if font:
		lbl_title.add_theme_font_override("font", font)
	vb.add_child(lbl_title)

	var lbl_msg := Label.new()
	lbl_msg.text = "L'hôte a quitté la partie.\nRetour au menu principal…"
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 14)
	lbl_msg.add_theme_color_override("font_color", Color(0.78, 0.84, 0.90))
	if font:
		lbl_msg.add_theme_font_override("font", font)
	vb.add_child(lbl_msg)

	return layer
