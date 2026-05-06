extends Node3D

func _ready() -> void:
	CollisionManager.add_missing_collisions(self)
