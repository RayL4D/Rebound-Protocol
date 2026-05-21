# =============================================================
# arena_first_level_1.gd — Premier niveau de l'arène (V3 - Chemins Corrigés)
# =============================================================
extends Node3D

# --- RÉFÉRENCES AUX NŒUDS (Chemins mis à jour) ---
@onready var wave_manager_zone1: WaveManager = $Wave_manager_container/WaveManager_Zone1
@onready var wave_manager_zone2: WaveManager = $Wave_manager_container/WaveManager_Zone2
@onready var level_exit: Node = $Zones/LevelExit
@onready var hud: Node = $HUD

# Variables de contrôle
var _zone1_triggered: bool = false
var _zone2_triggered: bool = false

# Chemins des murs pour éviter les répétitions
const WALL_1_PATH = "Zones/Blocking_wall_container/Blocking_wall_1"
const WALL_2_PATH = "Zones/Blocking_wall_container/Blocking_wall_2"

func _ready() -> void:
	
	MusicManager.play("gameplay")
	AmbientManager.play("arena")
	TranslationServer.set_locale(SceneManager.current_lang)
		
	CollisionManager.add_missing_collisions(self)
	_setup_ui()
	_setup_waves()
	_connect_signals()
	
	ScoreManager.start_level()
	
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
	
	# Affiche le message par défaut
	_set_permanent_message("LVL1_INTRO_MSG")

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
		var waves_z1: Array[WaveManager.WaveData] = [
			WaveManager.WaveData.new(5, 1, "WAVE_NAME_OUTPOST", 0)
		]
		wave_manager_zone1.setup_waves(waves_z1)
	
	if wave_manager_zone2:
		var waves_z2: Array[WaveManager.WaveData] = [
			WaveManager.WaveData.new(10, 2, "WAVE_NAME_SQUAD", 0),
			#WaveManager.WaveData.new(15, 3, "WAVE_NAME_REINFORCEMENTS", 1),
			#WaveManager.WaveData.new(20, 3, "WAVE_NAME_MAX_ALERT", 2)
		]
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

func _on_zone_2_finished() -> void:
	if has_node(WALL_2_PATH):
		var wall2 = get_node(WALL_2_PATH)
		wall2.get_node("CollisionShape3D").set_deferred("disabled", true)
		if wall2.has_node("MeshInstance3D"):
			wall2.get_node("MeshInstance3D").visible = false
			
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
