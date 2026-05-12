extends Enemy # Hérite de votre classe de base Rebound Protocol

@export var path_follow : PathFollow3D
@export var detection_range : float = 12.0

enum State { PATROLLING, CHASING }
var _current_state = State.PATROLLING
var _direction = 1 # 1 = aller, -1 = retour

func _on_ready() -> void:
	super._on_ready() 
	# Attendre un frame pour être sûr que le rail existe dans le monde
	await get_tree().process_frame 
	if path_follow:
		global_position = path_follow.global_position

func _physics_process(delta: float) -> void:
	# On vérifie si le joueur existe et si l'ennemi est encore en vie (HP > 0)
	if player == null or current_hp <= 0:
		return

	match _current_state:
		State.PATROLLING:
			_patrol_logic(delta)
			_check_detection()
		State.CHASING:
			# Utilise la logique de mouvement vers le joueur de Enemy.gd
			super._physics_process(delta)

func _patrol_logic(delta: float) -> void:
	if not path_follow: return
	
	# 1. Mémorisation de la position avant le mouvement
	var pos_avant = global_position
	
	# 2. Avancement sur le rail (move_speed défini dans Enemy.gd)
	path_follow.progress += move_speed * delta * _direction
	
	# 3. Mise à jour de la position physique
	global_position = path_follow.global_position
	
	# 4. Calcul de la direction du mouvement
	var direction_reelle = (global_position - pos_avant).normalized()
	
	# 5. Orientation avec correction à 180 degrés
	if direction_reelle.length() > 0.001:
		var cible_regard = global_position + direction_reelle
		look_at(cible_regard, Vector3.UP)
		
		# PIVOT À 180 DEGRÉS : 
		# On fait pivoter l'animal sur son axe Y local pour compenser l'orientation du modèle
		rotate_y(PI) # PI radians = 180 degrés
	
	# 6. Gestion de l'inversion de marche (sans Loop dans l'inspecteur)
	if path_follow.progress_ratio >= 0.99 and _direction == 1:
		_direction = -1
		path_follow.progress_ratio = 1.0
	elif path_follow.progress_ratio <= 0.01 and _direction == -1:
		_direction = 1
		path_follow.progress_ratio = 0.0
func _check_detection() -> void:
	var dist = global_position.distance_to(player.global_position)
	if dist < detection_range:
		_current_state = State.CHASING
		# On active l'arme via le composant Rebound Protocol[cite: 2]
		var weapon = get_node_or_null("WeaponMount/WeaponBullet")
		if weapon: weapon.activate(player)

func _face_direction(dir: Vector3) -> void:
	# On tourne le modèle vers sa direction de patrouille
	var target_angle = atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 0.1)
