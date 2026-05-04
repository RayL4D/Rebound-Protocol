extends Node3D

func _ready() -> void:
	await get_tree().process_frame
	CollisionManager.add_missing_collisions(self)
