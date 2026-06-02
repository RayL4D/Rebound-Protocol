extends Enemy # Hérite de votre classe de base Rebound Protocol

@export var path_follow : PathFollow3D
# detection_range est hérité de Enemy.gd — ne pas redéclarer

enum State { PATROLLING, CHASING }
var _current_state = State.PATROLLING
var _direction = 1 # 1 = aller, -1 = retour

func _on_ready() -> void:
	super._on_ready() # Initialise les textures et le modèle
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
	
	# Avancement sur le rail (vitesse move_speed définie dans Enemy.gd[cite: 2])
	path_follow.progress += move_speed * delta * _direction
	global_position = path_follow.global_position
	
	# Inversion de marche aux extrémités
	if path_follow.progress_ratio >= 1.0:
		_direction = -1
	elif path_follow.progress_ratio <= 0.0:
		_direction = 1
		
	# Orientation visuelle
	_face_direction(Vector3.FORWARD * _direction)

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
