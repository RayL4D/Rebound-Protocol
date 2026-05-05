extends Node3D

func _ready() -> void:
	_add_collision_recursive(self)

func _add_collision_recursive(node: Node) -> void:
	if node is CharacterBody3D or node is RigidBody3D:
		return
	# Groupe "no_collision" : skip ce nœud ET tous ses descendants
	if node.is_in_group("no_collision"):
		return

	if node is MeshInstance3D and node.mesh != null:
		var has_collision := false
		# 1. Si le parent direct est déjà un objet physique (ex: StaticBody3D défini manuellement pour un mur).
		if node.get_parent() is CollisionObject3D:
			has_collision = true
		# 2. Si le mesh possède déjà un corps physique en enfant (ex: un StaticBody3D généré via l'import de tes .glb).
		if not has_collision:
			for child in node.get_children():
				if child is CollisionObject3D:
					has_collision = true
					break
		# Si aucune collision n'est gérée pour ce mesh, on génère la collision exacte.
		if not has_collision:
			node.create_trimesh_collision()
	# Poursuivre l'exploration de l'arbre
	for child in node.get_children():
		_add_collision_recursive(child)
