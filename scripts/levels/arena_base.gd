# =============================================================
# arena_base.gd — Arène tutoriel / arène de base
# Auteur : Kevin SIDER
# =============================================================
extends Node

@onready var wave_manager: Node = $WaveManager
@onready var tutorial_manager: TutorialManager = $TutorialManager
@onready var hud: Node = $HUD


func _ready() -> void:
	
	# Définition de la langue utilisée dans le niveau
	TranslationServer.set_locale(SceneManager.current_lang)
	
	_add_collision_recursive(self)

	# --- Labels HUD ---
	var wave_label:    Label   = hud.get_node_or_null("%WaveLabel")
	var message_label: Label   = hud.get_node_or_null("%MessageLabel")
	var enemies_label: Label   = hud.get_node_or_null("%EnemiesLabel")
	var step_label:    Label   = hud.get_node_or_null("%StepLabel")
	var panel:         Control = hud.get_node_or_null("%PanelContainer")

	wave_manager.setup_ui(wave_label, message_label, enemies_label, panel)

	# --- Vagues ---
	var waves: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(1, 1, ""),   # Ennemi post-tuto
		WaveManager.WaveData.new(1, 1, tr("WAVE_MSG_1")),
		WaveManager.WaveData.new(2, 1, tr("WAVE_MSG_2")),
		WaveManager.WaveData.new(3, 2, tr("WAVE_MSG_FINAL")),
	]
	wave_manager.setup_waves(waves)

	# --- Tutoriel ---
	var player: Player = get_tree().get_first_node_in_group("player")
	tutorial_manager.setup(player, panel, message_label, step_label)
	tutorial_manager.tutorial_completed.connect(_on_tutorial_completed)
	tutorial_manager.start()
	
	wave_manager.all_waves_finished.connect(_on_waves_finished)


func _on_tutorial_completed() -> void:
	wave_manager.start()


func _add_collision_recursive(node: Node) -> void:
	if node is CharacterBody3D:
		return

	if node is MeshInstance3D:
		var parent := node.get_parent()
		var parent_has_collision := false
		for child in parent.get_children():
			if child is CollisionShape3D:
				parent_has_collision = true
				break
		if not parent_has_collision:
			node.create_trimesh_collision()

	for child in node.get_children():
		_add_collision_recursive(child)
		

func _on_waves_finished() -> void:
	var exit_zone = $LevelExit 
	exit_zone.activate()
	
	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	if message_label:
		message_label.text = tr("MISSION_ACCOMPLISHED")
