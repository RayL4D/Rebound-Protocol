extends Node3D

# --- RÉFÉRENCES AUX NŒUDS ---
@onready var wave_manager_zone1 = $WaveManager_Zone1
@onready var wave_manager_zone2 = $WaveManager_Zone2
@onready var wave_manager_boss = $WaveManager_Boss
@onready var level_exit = $Zones/LevelExit
@onready var hud = $HUD # Assure-toi que le nœud HUD est bien présent dans ta scène

func _ready() -> void:
	# 1. Génération des collisions pour le niveau
	CollisionManager.add_missing_collisions(self)
	
	# 2. Configuration de l'HUD pour les gestionnaires de vagues
	# On récupère les labels via leurs "Scene Unique Names" (%)
	var wave_label: Label = hud.get_node_or_null("%WaveLabel")
	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	var enemies_label: Label = hud.get_node_or_null("%EnemiesLabel")
	var panel: Control = hud.get_node_or_null("%PanelContainer")
	
	# On lie l'UI à chaque manager pour que l'affichage s'actualise
	wave_manager_zone1.setup_ui(wave_label, message_label, enemies_label, panel)
	wave_manager_zone2.setup_ui(wave_label, message_label, enemies_label, panel)
	wave_manager_boss.setup_ui(wave_label, message_label, enemies_label, panel)
	
	# 3. Configuration des vagues (Utilisation de tableaux typés pour éviter l'erreur de base)
	
	# Zone 1 (Optionnelle)
	var waves_z1: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(2, 1, "Vague Optionnelle !")
	]
	wave_manager_zone1.setup_waves(waves_z1)
	
	# Zone 2 (3 Vagues obligatoires)
	var waves_z2: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(3, 1, "Vague 1/3"),
		WaveManager.WaveData.new(4, 2, "Vague 2/3"),
		WaveManager.WaveData.new(5, 2, "Vague 3/3")
	]
	wave_manager_zone2.setup_waves(waves_z2)
	
	# Boss (Vague unique)
	var waves_boss: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(1, 1, "ALERTE : BOSS EN APPROCHE !")
	]
	# Note : Si tu veux que ce soit le Lion, assure-toi que l'enemy_scene 
	# du WaveManager_Boss est bien réglée sur boss_lion.tscn dans l'inspecteur.
	wave_manager_boss.setup_waves(waves_boss)

	# 4. Connexion des signaux de progression
	wave_manager_zone2.all_waves_finished.connect(_on_zone_2_finished)
	wave_manager_boss.all_waves_finished.connect(_on_boss_defeated)


# --- LOGIQUE DES TRIGGERS ---

func _on_trigger_zone_1_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		wave_manager_zone1.start()
		# On supprime le trigger pour ne pas relancer la zone
		if has_node("Trigger_Zone1"):
			$Trigger_Zone1.queue_free()

func _on_trigger_zone_2_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		wave_manager_zone2.start()
		if has_node("Trigger_Zone2"):
			$Trigger_Zone2.queue_free()


# --- CALLBACKS DE FIN ---

# Appelé quand les 3 vagues de la zone 2 sont terminées
func _on_zone_2_finished() -> void:
	print("Zone 2 nettoyée, lancement de la phase Boss.")
	wave_manager_boss.start()

# Appelé quand la vague du boss est terminée (ennemis à 0)
func _on_boss_defeated() -> void:
	print("Boss vaincu ! Activation du portail de sortie.")
	if level_exit:
		level_exit.activate()
