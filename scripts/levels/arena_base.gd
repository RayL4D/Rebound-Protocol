# =============================================================
# arena_base.gd — Arène tutoriel / arène de base
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
extends Node

@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: Node = $HUD


func _ready() -> void:
	_add_collision_recursive(self)

	# Brancher les labels du HUD sur le WaveManager
	# Les nœuds Label sont cherchés dans la scène HUD avec leur unique name
	var wave_label: Label    = hud.get_node_or_null("%WaveLabel")
	var message_label: Label = hud.get_node_or_null("%MessageLabel")
	var enemies_label: Label = hud.get_node_or_null("%EnemiesLabel")
	wave_manager.setup_ui(wave_label, message_label, enemies_label)

	# Définit les 3 vagues du tutoriel
	var waves: Array[WaveManager.WaveData] = [
		WaveManager.WaveData.new(
			1, 1,
			"Pare les balles ennemies avec [ESPACE] !\nUn ennemi arrive."
		),
		WaveManager.WaveData.new(
			2, 1,
			"Bien joué ! Deux ennemis cette fois.\nReste mobile !"
		),
		WaveManager.WaveData.new(
			3, 2,
			"Vague finale — trois ennemis, deux vaisseaux.\nConcentre-toi !"
		),
	]

	wave_manager.setup_waves(waves)



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
