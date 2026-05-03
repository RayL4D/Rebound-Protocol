extends Node3D

func _ready() -> void:
	# Attendre 1 frame pour que tout soit bien initialisé
	await get_tree().process_frame
	_add_missing_collisions()
	print("✓ Vérification des collisions terminée")

func _add_missing_collisions() -> void:
	# Trouver tous les StaticBody3D dans la scène
	var static_bodies = _find_all_static_bodies(self)
	
	for static_body in static_bodies:
		# Pour chaque StaticBody3D, vérifier les meshes enfants
		_check_meshes_in_static_body(static_body)

func _find_all_static_bodies(node: Node) -> Array:
	var result := []
	
	if node is StaticBody3D:
		result.append(node)
	
	for child in node.get_children():
		result.append_array(_find_all_static_bodies(child))
	
	return result

func _check_meshes_in_static_body(static_body: StaticBody3D) -> void:
	# Récupérer tous les MeshInstance3D enfants (même indirects)
	var meshes = _find_all_meshes(static_body)
	
	# Récupérer toutes les CollisionShape3D du StaticBody3D
	var collision_shapes = _find_all_collision_shapes(static_body)
	
	print("StaticBody3D '", static_body.name, "' : ", meshes.size(), " meshes, ", collision_shapes.size(), " collision shapes")
	
	# Pour chaque mesh, vérifier s'il a une collision correspondante
	for mesh_instance in meshes:
		if not _has_corresponding_collision(mesh_instance, collision_shapes):
			print("  ⚠ Mesh sans collision détecté : ", mesh_instance.name)
			_create_collision_for_mesh(mesh_instance, static_body)

func _find_all_meshes(node: Node) -> Array:
	var result := []
	
	if node is MeshInstance3D and node.mesh != null:
		result.append(node)
	
	for child in node.get_children():
		# Ne pas descendre dans les CollisionShape3D
		if not child is CollisionShape3D:
			result.append_array(_find_all_meshes(child))
	
	return result

func _find_all_collision_shapes(node: Node) -> Array:
	var result := []
	
	if node is CollisionShape3D:
		result.append(node)
	
	for child in node.get_children():
		result.append_array(_find_all_collision_shapes(child))
	
	return result

func _has_corresponding_collision(mesh_instance: MeshInstance3D, collision_shapes: Array) -> bool:
	# Stratégie simple : vérifier si une CollisionShape3D est proche du mesh
	var mesh_pos = mesh_instance.global_position
	
	for shape in collision_shapes:
		var shape_pos = shape.global_position
		var distance = mesh_pos.distance_to(shape_pos)
		
		# Si une collision est très proche du mesh (< 1 mètre), on considère qu'elle gère ce mesh
		if distance < 1.0:
			return true
	
	return false

func _create_collision_for_mesh(mesh_instance: MeshInstance3D, static_body: StaticBody3D) -> void:
	# Créer une CollisionShape3D directement sur le StaticBody3D
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "AutoCollision_" + mesh_instance.name
	
	# Positionner la collision au même endroit que le mesh
	collision_shape.global_transform = mesh_instance.global_transform
	
	# Générer la forme de collision en fonction du type de mesh
	var shape = _create_shape_from_mesh(mesh_instance)
	if shape:
		collision_shape.shape = shape
		static_body.add_child(collision_shape)
		collision_shape.owner = get_tree().edited_scene_root
		print("  ✓ Collision générée pour : ", mesh_instance.name)

func _create_shape_from_mesh(mesh_instance: MeshInstance3D) -> Shape3D:
	var mesh = mesh_instance.mesh
	
	# Pour les cylindres
	if mesh is CylinderMesh:
		var cylinder_shape = CylinderShape3D.new()
		cylinder_shape.radius = mesh.top_radius
		cylinder_shape.height = mesh.height
		return cylinder_shape
	
	# Pour les boîtes
	elif mesh is BoxMesh:
		var box_shape = BoxShape3D.new()
		box_shape.size = mesh.size
		return box_shape
	
	# Pour les plans
	elif mesh is PlaneMesh:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(mesh.size.x, 0.1, mesh.size.y)
		return box_shape
	
	# Par défaut, utiliser une collision convexe
	else:
		return mesh.create_convex_shape()
