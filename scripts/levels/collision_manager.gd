class_name CollisionManager 
extends Node

## Génère automatiquement les collisions manquantes.
static func add_missing_collisions(node: Node) -> void:
	# On ignore les entités mobiles comme le joueur ou les ennemis
	if node is CharacterBody3D:
		return

	if node is MeshInstance3D:
		var parent := node.get_parent()
		var parent_has_collision := false
		
		# Vérifie si un frère/sœur du Mesh (enfant du même parent) est une CollisionShape3D
		if parent != null:
			for child in parent.get_children():
				if child is CollisionShape3D:
					parent_has_collision = true
					break
					
		# Si aucune collision n'a été trouvée à ce niveau, on génère le trimesh
		if not parent_has_collision:
			node.create_trimesh_collision()

	# Parcours récursif de tous les enfants
	for child in node.get_children():
		add_missing_collisions(child)
