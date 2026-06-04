extends Node3D

func _ready() -> void:
	# On parcourt tous les nœuds enfants directs de la scène
	for child in get_children():
		
		# On vérifie si le nom du nœud commence par "grass" (en minuscules)
		# Cela couvrira "grass_container", "grass_bush", "grass_1", etc.
		if child.name.to_lower().begins_with("grass"):
			continue # On passe au prochain sans ajouter de collision
			
		# Pour tout ce qui ne commence PAS par "grass", on applique la collision
		CollisionManager.add_missing_collisions(child)
