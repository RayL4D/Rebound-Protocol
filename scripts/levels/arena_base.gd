extends Node


# arena_base.gd
func _ready():
	_add_collision_recursive(self)

func _add_collision_recursive(node: Node):
	if node is MeshInstance3D:
		node.create_trimesh_collision()
	for child in node.get_children():
		_add_collision_recursive(child)
