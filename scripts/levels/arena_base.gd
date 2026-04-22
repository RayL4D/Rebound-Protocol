# =============================================================
# arena_base.gd — Arène tutoriel / arène de base
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
extends Node

@onready var wave_manager: Node = $WaveManager
@onready var tutorial_manager: TutorialManager = $TutorialManager
@onready var hud: Node = $HUD


func _ready() -> void:
	
	#var locale = OS.get_locale_language()
	#TranslationServer.set_locale(locale)
	
	TranslationServer.set_locale("es") # Anglais pour le test
	
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
		WaveManager.WaveData.new(1, 1, ""),   # Ennemi test post-tuto
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


func _on_tutorial_completed() -> void:
	wave_manager.start()


# =============================================================
# COLLISION DÉCOR
# =============================================================

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
