# =============================================================
# arena_first_level_1.gd — Premier niveau de l'arène (V3 - Chemins Corrigés)
# =============================================================
extends Node3D

# --- RÉFÉRENCES AUX NŒUDS (Chemins mis à jour) ---
@onready var wave_manager_zone1: WaveManager = $Wave_manager_container/WaveManager_Zone1
@onready var wave_manager_zone2: WaveManager = $Wave_manager_container/WaveManager_Zone2
@onready var level_exit: Node = $Zones/Instant_exit
@onready var hud: Node = $HUD
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
# Chemins des save point
@onready var hidden_save_point_1 = $SavePoint_container/SavePoint_1
@onready var hidden_save_point_2 = $SavePoint_container/SavePoint_3


# Variables de contrôle
var _zone1_triggered: bool = false
var _zone2_triggered: bool = false

# Chemins des murs pour éviter les répétitions
const WALL_1_PATH = "Zones/Blocking_wall_container/Blocking_wall_1"
const WALL_2_PATH = "Zones/Blocking_wall_container/Blocking_wall_2"

func _ready() -> void:
	_prewarm_bullet_shaders()
	MusicManager.play("gameplay")
	AmbientManager.play("arena")
	TranslationServer.set_locale(SceneManager.current_lang)

	CollisionManager.add_missing_collisions(self)
	CollisionManager.add_missing_collisions(level_exit)
	_setup_ui()
	_setup_waves()
	_connect_signals()
	
	ScoreManager.start_level()
	call_deferred("_bake_navigation")

	# === DÉSACTIVATION DES MURS AU LANCEMENT ===
	if has_node(WALL_1_PATH):
		var wall1 = get_node(WALL_1_PATH)
		wall1.get_node("CollisionShape3D").set_deferred("disabled", true)
		if wall1.has_node("MeshInstance3D"):
			wall1.get_node("MeshInstance3D").visible = false
			
	if has_node(WALL_2_PATH):
		var wall2 = get_node(WALL_2_PATH)
		wall2.get_node("CollisionShape3D").set_deferred("disabled", true)
		if wall2.has_node("MeshInstance3D"):
			wall2.get_node("MeshInstance3D").visible = false
			
	# === DÉSACTIVATION DES SAVE POINTS AU LANCEMENT ===
	if hidden_save_point_1:
		hidden_save_point_1.visible = false
		hidden_save_point_1.process_mode = Node.PROCESS_MODE_DISABLED
		
	if hidden_save_point_2:
		hidden_save_point_2.visible = false
		hidden_save_point_2.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Affiche le message par défaut
	_set_permanent_message("LVL1_INTRO_MSG")
	
	

	# Filet de sécurité : restaurer position + HP après TOUS les _ready() de la scène.
	call_deferred("_deferred_restore_player")

# =============================================================
# CONFIGURATION
# =============================================================

func _setup_ui() -> void:
	if not hud:
		push_error("HUD non trouvé dans la scène !")
		return
	
	var wave_label: Label = hud.find_child("WaveLabel", true, false) as Label
	var message_label: Label = hud.find_child("MessageLabel", true, false) as Label
	var enemies_label: Label = hud.find_child("EnemiesLabel", true, false) as Label
	var panel: Control = hud.find_child("PanelContainer", true, false) as Control
	
	if not panel:
		panel = hud.find_child("Panel", true, false) as Control
	
	if wave_manager_zone1:
		wave_manager_zone1.setup_ui(wave_label, message_label, enemies_label, panel)
	
	if wave_manager_zone2:
		wave_manager_zone2.setup_ui(wave_label, message_label, enemies_label, panel)

func _setup_waves() -> void:
	if wave_manager_zone1:
		# Vague 1 : 12 chiens (6 par dropship)
		var w1a := WaveManager.WaveData.new(12, 2, "WAVE_NAME_OUTPOST", 0)

		# Vague 2 : chaque spawn point reçoit 3 chiens ET 3 vaches
		# Format : [enemy_index, count, position_index]
		var w1b := WaveManager.WaveData.new(0, 0, "WAVE_NAME_OUTPOST")
		w1b.dropship_groups = [
			[0, 3, 0],   # pos 0 → 3 chiens
			[1, 3, 0],   # pos 0 → 3 vaches
			[0, 3, 1],   # pos 1 → 3 chiens
			[1, 3, 1],   # pos 1 → 3 vaches
		]

		# Utiliser append() évite les problèmes de parsing des typed array literals
		# avec des inner classes en GDScript
		var waves_z1: Array[WaveManager.WaveData] = []
		waves_z1.append(w1a)
		waves_z1.append(w1b)
		wave_manager_zone1.setup_waves(waves_z1)

	if wave_manager_zone2:
		var w2a := WaveManager.WaveData.new(8, 2, "WAVE_NAME_SQUAD")
		w2a.enemy_mix = [0, 1]

		var w2b := WaveManager.WaveData.new(9, 3, "WAVE_NAME_REINFORCEMENTS")
		w2b.enemy_mix = [1, 2, 2]

		var w2c := WaveManager.WaveData.new(12, 3, "WAVE_NAME_MAX_ALERT")
		w2c.enemy_mix = [0, 1, 2]

		var waves_z2: Array[WaveManager.WaveData] = []
		waves_z2.append(w2a)
		waves_z2.append(w2b)
		waves_z2.append(w2c)
		wave_manager_zone2.setup_waves(waves_z2)

func _connect_signals() -> void:
	if wave_manager_zone1:
		if not wave_manager_zone1.all_waves_finished.is_connected(_on_zone_1_finished):
			wave_manager_zone1.all_waves_finished.connect(_on_zone_1_finished)
			
	if wave_manager_zone2:
		if not wave_manager_zone2.all_waves_finished.is_connected(_on_zone_2_finished):
			wave_manager_zone2.all_waves_finished.connect(_on_zone_2_finished)

# =============================================================
# TRIGGERS DES ZONES
# =============================================================

func _on_trigger_zone_1_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _zone1_triggered:
		_zone1_triggered = true
		
		var trigger = get_node_or_null("Wave_manager_container/Trigger_Zone1")
		if trigger:
			trigger.queue_free()
			
		if wave_manager_zone1:
			wave_manager_zone1.start()
		
		await get_tree().create_timer(3.0).timeout
		
		if has_node(WALL_1_PATH):
			var wall1 = get_node(WALL_1_PATH)
			wall1.get_node("CollisionShape3D").set_deferred("disabled", false)
			if wall1.has_node("MeshInstance3D"):
				wall1.get_node("MeshInstance3D").visible = true
				

func _bake_navigation() -> void:
	if not is_instance_valid(_nav_region):
		return

	# Configurer le NavigationMesh pour les ennemis du jeu (rayon ~0.5 m)
	var nav_mesh := _nav_region.navigation_mesh
	nav_mesh.cell_size                        = 0.25
	nav_mesh.cell_height                      = 0.20
	nav_mesh.agent_radius                     = 0.5
	nav_mesh.agent_height                     = 2.0
	nav_mesh.agent_max_climb                  = 0.5
	nav_mesh.agent_max_slope                  = 45.0
	nav_mesh.region_min_size                  = 4.0
	# Scanner TOUS les corps statiques ET meshes — corps statiques = décors avec collision
	nav_mesh.geometry_parsed_geometry_type    = NavigationMesh.PARSED_GEOMETRY_BOTH
	# Source : enfants du nœud passé à parse_source_geometry_data (= self = racine scène)
	nav_mesh.geometry_source_geometry_mode    = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	# Parser la géométrie depuis la RACINE de la scène (et non le NavigationRegion3D)
	# → les décors/obstacles frères sont inclus dans le mesh de navigation
	var source_geo := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geo, self)

	# Bake asynchrone : ne bloque pas le thread principal
	# callback : applique le mesh baked à la région dès que c'est terminé
	NavigationServer3D.bake_from_source_geometry_data_async(
		nav_mesh, source_geo,
		Callable(self, "_on_navigation_baked")
	)


func _on_navigation_baked() -> void:
	if is_instance_valid(_nav_region):
		NavigationServer3D.region_set_navigation_mesh(
			_nav_region.get_region_rid(), _nav_region.navigation_mesh
		)
	print("[Level1] Navigation mesh baked.")


func _prewarm_bullet_shaders() -> void:
	const SCENE = preload("res://scenes/projectiles/bullet_enemy.tscn")
	var dummy: Node3D = SCENE.instantiate() as Node3D
	dummy.position = Vector3(0.0, -500.0, 0.0)
	add_child(dummy)
	await get_tree().process_frame
	if is_instance_valid(dummy):
		dummy.queue_free()


func _on_trigger_zone_2_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _zone2_triggered:
		_zone2_triggered = true
		
		# On supprime le trigger d'entrée immédiatement (chemin mis à jour)
		var trigger = get_node_or_null("Wave_manager_container/Trigger_Zone2")
		if trigger:
			trigger.queue_free()
			
		if wave_manager_zone2:
			wave_manager_zone2.start()

		await get_tree().create_timer(3.0).timeout
		
		if has_node(WALL_2_PATH):
			var wall2 = get_node(WALL_2_PATH)
			wall2.get_node("CollisionShape3D").set_deferred("disabled", false)
			if wall2.has_node("MeshInstance3D"):
				wall2.get_node("MeshInstance3D").visible = true
				

# =============================================================
# CALLBACKS DE PROGRESSION
# =============================================================

func _on_zone_1_finished() -> void:
	if has_node(WALL_1_PATH):
		var wall1 = get_node(WALL_1_PATH)
		wall1.get_node("CollisionShape3D").set_deferred("disabled", true)
		if wall1.has_node("MeshInstance3D"):
			wall1.get_node("MeshInstance3D").visible = false
			
	if hidden_save_point_1:
		hidden_save_point_1.visible = true
		hidden_save_point_1.process_mode = Node.PROCESS_MODE_INHERIT

func _on_zone_2_finished() -> void:
	if has_node(WALL_2_PATH):
		var wall2 = get_node(WALL_2_PATH)
		wall2.get_node("CollisionShape3D").set_deferred("disabled", true)
		if wall2.has_node("MeshInstance3D"):
			wall2.get_node("MeshInstance3D").visible = false
			
	if hidden_save_point_2:
		hidden_save_point_2.visible = true
		hidden_save_point_2.process_mode = Node.PROCESS_MODE_INHERIT
			
	if level_exit and level_exit.has_method("activate"):
		level_exit.activate()
	
	_set_permanent_message("LVL1_EXIT_OPENED_MSG")

# =============================================================
# UTILITAIRES
# =============================================================

func _set_permanent_message(translation_key: String) -> void:
	var message_label: Label = hud.find_child("MessageLabel", true, false) as Label
	var panel: Control = hud.find_child("PanelContainer", true, false) as Control
	if not panel:
		panel = hud.find_child("Panel", true, false) as Control
	
	if message_label:
		message_label.text = translation_key
		
	if panel:
		panel.visible = true


func _deferred_restore_player() -> void:
	if SaveData.active_slot < 0:
		return  # Mode co-op ou aucun slot chargé — pas de restauration checkpoint
	var player: Player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# Si le checkpoint sauvegardé appartient à un AUTRE niveau (ex. le tutoriel),
	# ne pas restaurer la position : le joueur spawnerait hors de cette map.
	# On restaure seulement les HP pour conserver l'état de santé du joueur.
	var saved_level := SaveData.get_current_level()
	if saved_level != "" and saved_level != "arena_first_level_1":
		print("[Level1] _deferred_restore_player — checkpoint d'un autre niveau (", saved_level, "), restore HP uniquement.")
		player.restore_hp_only()
	else:
		print("[Level1] _deferred_restore_player — appel restore_from_checkpoint()")
		player.restore_from_checkpoint()
