# =============================================================
# arena_first_level_1.gd — Premier niveau de l'arène (corrigé et optimisé)
# =============================================================
extends Node3D

# --- RÉFÉRENCES AUX NŒUDS ---
@onready var wave_manager_zone1: WaveManager = $WaveManager_Zone1
@onready var wave_manager_zone2: WaveManager = $WaveManager_Zone2
@onready var wave_manager_boss: WaveManager = $WaveManager_Boss
@onready var level_exit: Node = $Zones/LevelExit
@onready var hud: Node = $HUD

# Variables de contrôle
var _zone1_triggered: bool = false
var _zone2_triggered: bool = false


func _ready() -> void:
	# 1. Génération des collisions pour le niveau
	CollisionManager.add_missing_collisions(self)
	
	# 2. Configuration de l'HUD pour les gestionnaires de vagues
	_setup_ui()
	
	# 3. Configuration des vagues
	_setup_waves()
	
	# 4. Connexion des signaux de progression
	_connect_signals()


# =============================================================
# CONFIGURATION
# =============================================================

func _setup_ui() -> void:
	"""Configure l'interface utilisateur"""
	if not hud:
		push_error("HUD non trouvé dans la scène !")
		return
	
	# Récupération des labels via Scene Unique Names
	var wave_label: Label = hud.get_node_or_null("%WaveLabel")
	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	var enemies_label: Label = hud.get_node_or_null("%EnemiesLabel")
	var panel: Control = hud.get_node_or_null("%PanelContainer")
	
	# Configuration UI pour chaque zone
	if wave_manager_zone1:
		wave_manager_zone1.setup_ui(wave_label, message_label, enemies_label, panel)
	
	if wave_manager_zone2:
		wave_manager_zone2.setup_ui(wave_label, message_label, enemies_label, panel)
	
	if wave_manager_boss:
		wave_manager_boss.setup_ui(wave_label, message_label, enemies_label, panel)


func _setup_waves() -> void:
	"""Configure les vagues pour chaque zone"""
	
	# Zone 1 (Optionnelle - Entraînement)
	if wave_manager_zone1:
		var waves_z1: Array[WaveManager.WaveData] = [
			WaveManager.WaveData.new(2, 1, "Vague d'entraînement")
		]
		wave_manager_zone1.setup_waves(waves_z1)
	
	# Zone 2 (3 Vagues obligatoires progressives)
	if wave_manager_zone2:
		var waves_z2: Array[WaveManager.WaveData] = [
			WaveManager.WaveData.new(3, 1, "Vague 1/3 - Premiers ennemis"),
			WaveManager.WaveData.new(4, 2, "Vague 2/3 - Renfort"),
			WaveManager.WaveData.new(5, 2, "Vague 3/3 - Assaut final")
		]
		wave_manager_zone2.setup_waves(waves_z2)
	
	# Boss (Vague unique)
	if wave_manager_boss:
		var waves_boss: Array[WaveManager.WaveData] = [
			WaveManager.WaveData.new(1, 1, "⚠️ ALERTE : BOSS EN APPROCHE !")
		]
		wave_manager_boss.setup_waves(waves_boss)


func _connect_signals() -> void:
	"""Connecte tous les signaux nécessaires"""
	
	# Signaux de fin de vagues
	if wave_manager_zone2:
		if not wave_manager_zone2.all_waves_finished.is_connected(_on_zone_2_finished):
			wave_manager_zone2.all_waves_finished.connect(_on_zone_2_finished)
	
	if wave_manager_boss:
		if not wave_manager_boss.all_waves_finished.is_connected(_on_boss_defeated):
			wave_manager_boss.all_waves_finished.connect(_on_boss_defeated)


# =============================================================
# TRIGGERS DES ZONES
# =============================================================

func _on_trigger_zone_1_body_entered(body: Node3D) -> void:
	"""Trigger de la zone optionnelle"""
	if body.is_in_group("player") and not _zone1_triggered:
		_zone1_triggered = true
		
		if wave_manager_zone1:
			wave_manager_zone1.start()
		
		# Suppression du trigger
		var trigger = get_node_or_null("Trigger_Zone1")
		if trigger:
			trigger.queue_free()


func _on_trigger_zone_2_body_entered(body: Node3D) -> void:
	"""Trigger de la zone principale"""
	if body.is_in_group("player") and not _zone2_triggered:
		_zone2_triggered = true
		
		if wave_manager_zone2:
			wave_manager_zone2.start()
		
		# Suppression du trigger
		var trigger = get_node_or_null("Trigger_Zone2")
		if trigger:
			trigger.queue_free()


# =============================================================
# CALLBACKS DE PROGRESSION
# =============================================================

func _on_zone_2_finished() -> void:
	"""Appelé quand les 3 vagues de la zone 2 sont terminées"""
	print("✓ Zone 2 nettoyée ! Lancement de la phase Boss...")
	
	# Petit délai dramatique avant le boss
	await get_tree().create_timer(2.0).timeout
	
	if wave_manager_boss:
		wave_manager_boss.start()


func _on_boss_defeated() -> void:
	"""Appelé quand le boss est vaincu"""
	print("✓ Boss vaincu ! Activation du portail de sortie.")
	
	# Activation du portail de sortie
	if level_exit and level_exit.has_method("activate"):
		level_exit.activate()
	
	# Message de victoire
	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	var panel: Control = hud.get_node_or_null("%PanelContainer")
	
	if message_label:
		message_label.text = "🎉 MISSION ACCOMPLIE !"
	if panel:
		panel.visible = true
