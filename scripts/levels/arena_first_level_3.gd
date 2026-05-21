# =============================================================
# arena_first_level_3.gd — Troisième niveau de l'arène
# =============================================================
extends Node3D

# --- RÉFÉRENCES AUX NŒUDS ---
@onready var wave_manager_zone2: WaveManager = $Wave_manager_container/WaveManager_Zone2
@onready var level_exit: Node = $WorldObjects_container/portal_container/LevelExit
@onready var hud: Node = $HUD

# Variables de contrôle
var _zone2_triggered: bool = false


func _ready() -> void:
	
	MusicManager.play("gameplay")
	AmbientManager.play("arena")
	TranslationServer.set_locale(SceneManager.current_lang)
	CollisionManager.add_missing_collisions(self)
	_setup_ui()
	_setup_waves()
	_connect_signals()


# =============================================================
# CONFIGURATION
# =============================================================

func _setup_ui() -> void:
	"""Configure l'interface utilisateur via le HUD"""
	if not hud: return
	
	var wave_label = hud.get_node_or_null("%WaveLabel")
	var message_label = hud.get_node_or_null("%MessageLabel")
	var enemies_label = hud.get_node_or_null("%EnemiesLabel")
	var panel = hud.get_node_or_null("%PanelContainer")
	
	if message_label:
		message_label.text = tr("ARENA_LVL3_INTRO")
	
	if wave_manager_zone2:
		wave_manager_zone2.setup_ui(wave_label, message_label, enemies_label, panel)


func _setup_waves() -> void:
	"""Configure les vagues avec les nouveaux IDs de traduction"""
	if not wave_manager_zone2: return
		
	var waves_z2: Array[WaveManager.WaveData] = [
		## Chiens (Index 0)
		WaveManager.WaveData.new(8, 2, tr("ARENA_LVL3_WAVE_DOGS"), 0),
		WaveManager.WaveData.new(10, 2, "", 0),
		
		# Vaches (Index 1)
		WaveManager.WaveData.new(12, 2, tr("ARENA_LVL3_WAVE_COWS"), 1),
		WaveManager.WaveData.new(14, 3, "", 1),
		
		# Chats (Index 2)
		WaveManager.WaveData.new(15, 3, tr("ARENA_LVL3_WAVE_CATS"), 2),
		WaveManager.WaveData.new(18, 3, "", 2),
		WaveManager.WaveData.new(20, 4, "", 2),
		
		# Mix (Index 0 ou 2 selon tes préférences)
		WaveManager.WaveData.new(22, 4, tr("ARENA_LVL3_WAVE_MIX"), 0),
		WaveManager.WaveData.new(25, 4, "", 2),
		
		# Boss (Index 3 - Lion)
		WaveManager.WaveData.new(1, 1, tr("ARENA_LVL3_WAVE_BOSS"), 3)
	]
	wave_manager_zone2.setup_waves(waves_z2)


func _connect_signals() -> void:
	"""Connecte la fin des vagues à l'ouverture du portail"""
	if wave_manager_zone2:
		if not wave_manager_zone2.all_waves_finished.is_connected(_on_zone_2_finished):
			wave_manager_zone2.all_waves_finished.connect(_on_zone_2_finished)


# =============================================================
# TRIGGERS
# =============================================================

func _on_trigger_zone_2_body_entered(body: Node3D) -> void:
	"""Déclenche l'intro narrative puis le combat"""
	if body.is_in_group("player") and not _zone2_triggered:
		_zone2_triggered = true
		
		# Affichage du message narratif (ARENA_LVL3_INTRO)
		var message_label = hud.get_node_or_null("%MessageLabel")
		var panel = hud.get_node_or_null("%PanelContainer")
		
		if message_label and panel:
			message_label.text = tr("ARENA_LVL3_INTRO")
			panel.visible = true
			# On laisse le message 4 secondes avant de lancer les ennemis
			await get_tree().create_timer(4.0).timeout
			panel.visible = false
		
		if wave_manager_zone2:
			wave_manager_zone2.start()
		
		# Nettoyage du trigger
		var trigger = get_node_or_null("Wave_manager_container/Trigger_Zone2")
		if trigger: trigger.queue_free()


# =============================================================
# CALLBACKS
# =============================================================

func _on_zone_2_finished() -> void:
	"""Victoire : Ouverture du portail et message final"""
	
	if level_exit and level_exit.has_method("activate"):
		level_exit.activate()
	
	var message_label = hud.get_node_or_null("%MessageLabel")
	var panel = hud.get_node_or_null("%PanelContainer")
	
	if message_label:
		message_label.text = tr("ARENA_LVL3_WIN")
	if panel:
		panel.visible = true
		await get_tree().create_timer(5.0).timeout
		panel.visible = false
