extends Node

## Génère automatiquement les collisions manquantes.
func add_missing_collisions(node: Node) -> void:
	# Ignorer les entités mobiles, les zones de trigger et les corps rigides.
	if node is CharacterBody3D or node is Area3D or node is RigidBody3D:
		return

	if node is MeshInstance3D:
		# Groupe "_cm_done" : ce mesh a déjà été traité lors d'un appel précédent
		# (évite la double génération quand arena_base ET le niveau appellent tous
		# les deux add_missing_collisions sur des sous-arbres qui se chevauchent).
		if not node.is_in_group("_cm_done"):
			var parent := node.get_parent()
			var parent_has_collision := false

			# On cherche uniquement un CollisionShape3D frère direct —
			# PAS un StaticBody3D, car le StaticBody3D généré par create_trimesh_collision()
			# contient un CollisionShape3D en enfant, pas en frère. Vérifier StaticBody3D
			# ferait sauter tous les meshes suivants du même parent (portes, murs...).
			if parent != null:
				for child in parent.get_children():
					if child is CollisionShape3D:
						parent_has_collision = true
						break

			if not parent_has_collision:
				node.create_trimesh_collision()

			# Marquer ce mesh traité dans les deux cas pour éviter tout doublon.
			node.add_to_group("_cm_done")

	# Parcours récursif de tous les enfants
	for child in node.get_children():
		add_missing_collisions(child)
