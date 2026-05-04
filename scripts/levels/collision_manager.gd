extends Node

## Génère automatiquement les collisions manquantes.
static func add_missing_collisions(node: Node) -> void:
	# Ignorer les entités mobiles, les zones de trigger et les corps rigides :
	# ils gèrent leur propre physique ou ne doivent pas avoir de collision statique.
	if node is CharacterBody3D or node is Area3D or node is RigidBody3D:
		return

	if node is MeshInstance3D:
		var parent := node.get_parent()
		var parent_has_collision := false

		# Vérifie si un frère/sœur du Mesh est déjà une CollisionShape3D OU un
		# StaticBody3D (= trimesh déjà généré lors d'un appel précédent).
		# Cela évite la double génération quand plusieurs scripts appellent
		# add_missing_collisions sur des sous-arbres qui se chevauchent.
		if parent != null:
			for child in parent.get_children():
				if child is CollisionShape3D or child is StaticBody3D:
					parent_has_collision = true
					break

		if not parent_has_collision:
			node.create_trimesh_collision()

	# Parcours récursif de tous les enfants
	for child in node.get_children():
		add_missing_collisions(child)
