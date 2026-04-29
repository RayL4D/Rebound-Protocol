# =============================================================
# Player.gd — Contrôleur principal du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Player
extends CharacterBody3D

# --- Exports (modifiables dans l'inspector Godot) ----------------
@export var move_speed: float     = 5.0
@export var jump_force: float     = 8.0
@export var fall_multiplier: float = 2.5  # Gravité multipliée pendant la chute
@export var max_hp: int           = 100
@export var rotation_speed: float    = 15.0  # Vitesse d'interpolation de la rotation
@export var cam_orbit_speed: float   = 90.0  # Degrés/seconde pour l'orbite Q/E
@export var iframe_duration: float   = 0.8   # Secondes d'invincibilité après un dégât

# --- Caméra ------------------------------------------------------
@export var zoom_min: float        = 3.0    # Distance minimale (zoom max)
@export var zoom_max: float        = 15.0   # Distance maximale (zoom min)
@export var zoom_speed: float      = 1.2    # Pas par cran de molette
@export var cam_pitch_min: float   = -85.0  # Angle le plus plongeant (presque top-down)
@export var cam_pitch_max: float   = -20.0  # Angle le plus rasant (quasi TPS)
@export var cam_sensitivity: float = 0.25   # Sensibilité du clic droit

# --- Références nœuds --------------------------------------------
@onready var spring_arm: SpringArm3D  = $SpringArm3D
@onready var shield: Node3D           = $Shield
@onready var robot_model: Node3D      = $RobotModel
@onready var camera: Camera3D         = $SpringArm3D/Camera3D
@onready var anim_tree: AnimationTree = $AnimationTree

# Texture du modèle — chargée une seule fois au démarrage
var _player_texture: Texture2D = preload("res://assets/textures/player/texture-g.png")

# --- Variables d'état --------------------------------------------
var current_hp: int
var is_dead: bool          = false
var _parry_requested: bool = false
var _was_on_floor: bool    = true   # Pour détecter l'atterrissage
var _model_base_scale: Vector3     # Scale originale du RobotModel (lue dans _ready)
var _model_base_y: float = 0.0     # Offset Y du modèle dans l'éditeur (pour éviter le flottement)
var _invincible: bool    = false    # True pendant les iframes
var _iframe_tween: Tween = null     # Tween du clignotement

# --- Caméra runtime ----------------------------------------------
var _rmb_held:         bool  = false
var _cam_pitch:        float = -60.0  # Initialisé depuis le SpringArm dans _ready
var _cam_yaw:          float = 0.0    # Yaw courant (interpolé)
var _target_snap_yaw:  float = 0.0    # Yaw cible (multiple de 90°, accumule sans modulo)
var _target_zoom:      float = 8.0    # Initialisé depuis le SpringArm dans _ready

# --- Mobile : direction du joystick droit (espace caméra) --------
var _joystick_aim_dir: Vector2 = Vector2.ZERO

# --- Cache pré-slide pour le stomp --------------------------------
# move_and_slide() modifie velocity.y quand on atterrit → on sauvegarde
# la valeur AVANT pour pouvoir vérifier la vitesse de chute réelle.
var _pre_slide_velocity_y: float = 0.0

# --- Stomp -------------------------------------------------------
const STOMP_DAMAGE:         int   = 25
const STOMP_FALL_THRESHOLD: float = -4.0   # vitesse Y min pour déclencher
const STOMP_BOUNCE:         float = 7.0    # rebond vertical après stomp
var   _stomp_hit_this_jump: bool  = false  # 1 stomp max par mise en l'air — reset à l'atterrissage sol

# --- Dash-bouclier -----------------------------------------------
const DASH_SPEED:     float = 20.0
const DASH_DURATION:  float = 0.20   # secondes
const DASH_COOLDOWN:  float = 1.20   # secondes
const DASH_DAMAGE:    int   = 12
const DASH_KNOCKBACK: float = 9.0

var _is_dashing:           bool  = false
var _dash_timer:           float = 0.0
var _dash_cooldown_timer:  float = 0.0
var _dash_dir:             Vector3 = Vector3.ZERO
var _dash_hit_enemies:     Array  = []   # ennemis déjà touchés dans ce dash

# Gravité récupérée depuis les paramètres projet Godot
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Signaux -----------------------------------------------------
signal player_died
signal hp_changed(new_hp: int)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	current_hp = max_hp
	floor_snap_length = 0.3
	spring_arm.set_as_top_level(true)
	add_to_group("player")
	_apply_texture_recursive(robot_model)

	# Ajouter le layer des ennemis (16 = layer 5) au collision mask
	# pour que move_and_slide() détecte les collisions avec eux
	# (nécessaire pour le stomp et le dash-bouclier).
	collision_mask |= 16

	_model_base_scale = robot_model.scale      # Mémoriser la scale réelle du modèle
	_model_base_y     = robot_model.position.y # Mémoriser le Y offset configuré dans l'éditeur

	# Lire les valeurs initiales depuis le SpringArm configuré dans l'éditeur
	_cam_pitch        = spring_arm.rotation_degrees.x
	_cam_yaw          = spring_arm.rotation_degrees.y
	_target_snap_yaw  = _cam_yaw   # Synchroniser la cible sur l'angle initial
	_target_zoom      = spring_arm.spring_length

	# Stoppe l'AnimationPlayer brut du GLB — c'est l'AnimationTree qui prend
	# le relais pour piloter les états (idle/sprint/parry/die).
	var anim_player := robot_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		anim_player.stop()

	# Pas besoin de connecter parry_resolved pour les animations :
	# on détecte l'appui SPACE directement dans _physics_process.


# Applique la texture sur tous les MeshInstance3D du modèle (tête, torse,
# bras, jambes) en un seul appel.
func _apply_texture_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _player_texture
		node.set_surface_override_material(0, mat)
	for child in node.get_children():
		_apply_texture_recursive(child)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_camera_orbit(delta)
	_handle_movement()
	_handle_dash(delta)

	# Sauvegarder velocity.y avant toute modification (stomp / snap)
	_pre_slide_velocity_y = velocity.y

	# Stomp : raycast AVANT move_and_slide() pour que le rebond soit appliqué
	# en amont — Jolt Physics ne retourne pas toujours les CharacterBody3D
	# dans get_slide_collision() lors d'atterrissages successifs sur le même ennemi.
	_check_stomp()

	# Désactiver le snap sol si le joueur remonte (saut, rebond stomp…)
	if velocity.y > 0.0:
		floor_snap_length = 0.0

	move_and_slide()

	_check_dash_hits()

	# Spring arm mis à jour AVANT _rotate_toward_mouse : le raycast souris
	# utilise ainsi l'orientation de caméra du frame courant (et non du précédent).
	spring_arm.global_position    = global_position + Vector3(0, 0.9, 0)
	spring_arm.rotation_degrees.x = _cam_pitch
	spring_arm.rotation_degrees.y = _cam_yaw
	spring_arm.spring_length      = lerp(spring_arm.spring_length, _target_zoom, 10.0 * delta)

	_rotate_toward_mouse()

	# Déclenche l'animation de parade dès l'appui sur SPACE
	if Input.is_action_just_pressed("parry"):
		_parry_requested = true
		var pb := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		pb.travel("parry")

	robot_model.position.x = 0.0
	robot_model.position.z = 0.0
	# robot_model.position.y est géré par _update_lean + l'offset éditeur
	_update_lean(delta)
	_update_animation()


# =============================================================
# CAMÉRA
# =============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				# Zoom avant — réduire la longueur du bras
				_target_zoom = clamp(_target_zoom - zoom_speed, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				# Zoom arrière — allonger le bras
				_target_zoom = clamp(_target_zoom + zoom_speed, zoom_min, zoom_max)
			MOUSE_BUTTON_RIGHT:
				# Mémoriser l'état du clic droit pour le drag
				_rmb_held = event.pressed

	# Pitch de la caméra avec clic droit maintenu (vertical seulement)
	if event is InputEventMouseMotion and _rmb_held:
		_cam_pitch -= event.relative.y * cam_sensitivity
		_cam_pitch  = clamp(_cam_pitch, cam_pitch_min, cam_pitch_max)

	# Orbite par snap de 90° — détection ici pour éviter la répétition du held
	if event is InputEventKey and event.pressed and not event.echo:
		if Input.is_action_just_pressed("cam_orbit_left"):
			_target_snap_yaw += 90.0
		elif Input.is_action_just_pressed("cam_orbit_right"):
			_target_snap_yaw -= 90.0


# =============================================================
# ORBITE CAMÉRA (Q / E)
# =============================================================

func _handle_camera_orbit(delta: float) -> void:
	# Interpolation fluide vers l'angle cible (multiple de 90°)
	# On accumule sans modulo pour éviter les sauts 359° → 0°
	_cam_yaw = lerp(_cam_yaw, _target_snap_yaw, 10.0 * delta)


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		# Sol : annuler uniquement si le joueur ne remonte pas déjà
		# (un stomp ou un saut vient de fixer velocity.y > 0 → ne pas l'écraser)
		velocity.y = 0.0
	elif velocity.y < 0.0:
		# Chute : gravité renforcée pour éviter le flottement
		velocity.y -= gravity * fall_multiplier * delta
	else:
		# Montée : gravité normale
		velocity.y -= gravity * delta


func _handle_jump() -> void:
	var on_floor := is_on_floor()

	if Input.is_action_just_pressed("jump") and on_floor:
		velocity.y        = jump_force
		floor_snap_length = 0.0
		_squash_stretch_jump()
	elif on_floor and not _was_on_floor:
		floor_snap_length = 0.3
		# Recharger le stomp seulement si on atterrit sur le sol réel,
		# pas sur la tête d'un ennemi.
		if not _standing_on_enemy():
			_stomp_hit_this_jump = false
			_squash_stretch_land()
	elif on_floor:
		floor_snap_length = 0.3

	_was_on_floor = on_floor


# Retourne true si la surface sous le joueur (collisions du frame précédent)
# est la tête d'un ennemi plutôt que le sol de la géométrie.
func _standing_on_enemy() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y > 0.5 and col.get_collider() is Enemy:
			return true
	return false


# Tilt du modèle selon la vélocité verticale — donne l'impression d'un arc
func _update_lean(delta: float) -> void:
	# velocity.y positif = montée → penche en arrière
	# velocity.y négatif = chute → penche en avant
	var target_tilt: float = clamp(-velocity.y * 0.03, -0.3, 0.3)
	robot_model.rotation.x   = lerp(robot_model.rotation.x,   target_tilt,    12.0 * delta)
	robot_model.position.y   = lerp(robot_model.position.y,   _model_base_y,  12.0 * delta)


# Squash & stretch au décollage
func _squash_stretch_jump() -> void:
	var b := _model_base_scale
	var tween := create_tween()
	tween.tween_property(robot_model, "scale", Vector3(b.x * 1.2, b.y * 0.7,  b.z * 1.2),  0.07)
	tween.tween_property(robot_model, "scale", Vector3(b.x * 0.85, b.y * 1.3, b.z * 0.85), 0.12)
	tween.tween_property(robot_model, "scale", b,                                            0.18)


# Squash & stretch à l'atterrissage
func _squash_stretch_land() -> void:
	var b := _model_base_scale
	var tween := create_tween()
	tween.tween_property(robot_model, "scale", Vector3(b.x * 1.3,  b.y * 0.65, b.z * 1.3),  0.06)
	tween.tween_property(robot_model, "scale", Vector3(b.x * 0.92, b.y * 1.1,  b.z * 0.92), 0.09)
	tween.tween_property(robot_model, "scale", b,                                             0.1)


func _handle_movement() -> void:
	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_forward", "move_backward")

	var input_dir := Vector2(input_x, input_z)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	# Déplacement relatif à la caméra — on lit directement la base de la caméra
	# plutôt que de recalculer depuis le yaw, pour éviter tout désalignement.
	var cb        := camera.global_transform.basis
	var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()   # -Z local projeté au sol
	var cam_right :=  Vector3(cb.x.x, 0.0, cb.x.z).normalized()   # +X local projeté au sol

	# input_dir.y est négatif quand "move_forward" est pressé (convention get_axis)
	# → on l'inverse pour que cam_fwd corresponde bien à "avancer"
	var move := cam_right * input_dir.x - cam_fwd * input_dir.y
	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed


# =============================================================
# ROTATION VERS LA SOURIS
# =============================================================

func _rotate_toward_mouse() -> void:
	# --- Joystick mobile prioritaire ---
	if _joystick_aim_dir.length_squared() > 0.04:
		var cb        := camera.global_transform.basis
		var cam_right := Vector3(cb.x.x, 0.0, cb.x.z).normalized()
		var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
		var world_dir := cam_right * _joystick_aim_dir.x - cam_fwd * _joystick_aim_dir.y
		world_dir.y   = 0.0
		if world_dir.length_squared() > 0.01:
			robot_model.global_rotation.y = atan2(world_dir.x, world_dir.z)
		return

	# --- Souris (desktop) ---
	var mouse_pos     := get_viewport().get_mouse_position()
	var ray_origin    := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)

	var look_dir := Vector3.ZERO

	if abs(ray_direction.y) > 0.001:
		var t := (global_position.y - ray_origin.y) / ray_direction.y
		if t > 0.0:
			# Intersection normale avec le plan du sol → on tourne vers ce point
			var target_point := ray_origin + ray_direction * t
			look_dir = (target_point - global_position)
			look_dir.y = 0.0

	# Souris vers le ciel (t ≤ 0) → projection horizontale du rayon :
	# si la souris est en haut à droite, le rayon pointe en haut à droite en 3D,
	# on ignore juste son Y pour garder la direction latérale correcte.
	if look_dir.length_squared() < 0.01:
		look_dir = Vector3(ray_direction.x, 0.0, ray_direction.z)

	if look_dir.length_squared() < 0.01:
		return

	# Assigner directement en global_rotation.y (espace monde),
	# identique à ce que fait le bouclier — pas de lag, pas d'offset.
	robot_model.global_rotation.y = atan2(look_dir.x, look_dir.z)


# =============================================================
# ANIMATIONS
# =============================================================

func _update_animation() -> void:
	var playback := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	if is_dead:
		playback.travel("die")
		return

	var current := playback.get_current_node()

	# _parry_requested bloque les frames de transition entre l'appel de
	# travel("parry") et le moment où le state machine entre réellement dans
	# cet état — sans ça, _update_animation écrase la demande dès le frame suivant.
	if _parry_requested:
		if current == "parry":
			_parry_requested = false  # Entrée confirmée, le flag n'est plus nécessaire
		return  # Dans tous les cas on attend, qu'on soit en transition ou dedans

	# L'animation de parade joue jusqu'à la fin (transition AtEnd → idle automatique)
	if current == "parry":
		return

	# Déplacement horizontal uniquement (on ignore Y pour ne pas switcher en l'air)
	var is_moving := Vector2(velocity.x, velocity.z).length_squared() > 0.1
	if is_moving:
		playback.travel("sprint")
	else:
		playback.travel("idle")




# =============================================================
# STOMP (saut écrasant)
# =============================================================

# Détecte un ennemi sous le joueur via raycast et applique le rebond
# AVANT move_and_slide() — évite les problèmes de Jolt Physics qui ne retourne
# pas toujours les CharacterBody3D dans get_slide_collision() lors d'atterrissages
# successifs sur le même ennemi.
func _check_stomp() -> void:
	# Pas assez de vitesse descendante → pas un stomp
	if _pre_slide_velocity_y > STOMP_FALL_THRESHOLD:
		return

	# Raycast vers le bas depuis le centre du joueur (layer 16 = ennemis uniquement)
	var space := get_world_3d().direct_space_state
	var query  := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 1.2,
		16
	)
	query.exclude = [self]
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		return

	var body = hit.get("collider")
	if not (body is Enemy):
		return

	var enemy := body as Enemy
	if enemy.stomp_immune:
		return

	# Rebond — toujours actif, permet de rebondir sur le même ennemi
	velocity.y = STOMP_BOUNCE

	# Dégâts uniquement au premier contact depuis le dernier atterrissage sol
	if not _stomp_hit_this_jump:
		_stomp_hit_this_jump = true
		enemy.stomp_squish()
		enemy.take_damage(STOMP_DAMAGE)


# =============================================================
# DASH-BOUCLIER
# =============================================================

# Gère le cooldown, détecte l'appui Shift et pilote le dash.
# Appelé AVANT move_and_slide() pour que le dash soit actif ce frame.
func _handle_dash(delta: float) -> void:
	# Tick du cooldown
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta

	# Dash en cours : décompte la durée et écrase velocity horizontale.
	# NOTE : appelé APRÈS _handle_movement(), donc cet override est définitif.
	if _is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_is_dashing = false
			_dash_hit_enemies.clear()
		else:
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
		return  # Pendant le dash on n'accepte pas de nouveau déclenchement

	# Déclenchement : touche dash pressée + cooldown écoulé
	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_start_dash()


# Initialise la direction et les timers du dash.
func _start_dash() -> void:
	# Direction prioritaire : mouvement clavier/joystick courant
	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_forward", "move_backward")
	var input_v := Vector2(input_x, input_z)

	var cb        := camera.global_transform.basis
	var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
	var cam_right :=  Vector3(cb.x.x, 0.0, cb.x.z).normalized()

	if input_v.length_squared() > 0.04:
		# Dash dans la direction de l'input relatif à la caméra
		_dash_dir = (cam_right * input_v.x - cam_fwd * input_v.y).normalized()
	else:
		# Aucun input → dash dans la direction du regard du modèle
		_dash_dir = -robot_model.global_transform.basis.z

	_dash_dir.y  = 0.0
	_dash_dir    = _dash_dir.normalized()

	_is_dashing           = true
	_dash_timer           = DASH_DURATION
	_dash_cooldown_timer  = DASH_COOLDOWN
	_dash_hit_enemies.clear()


# Détecte les ennemis touchés pendant le dash via les collisions de move_and_slide().
func _check_dash_hits() -> void:
	if not _is_dashing:
		return

	for i in get_slide_collision_count():
		var col  := get_slide_collision(i)
		var body := col.get_collider()
		if body is Enemy and not _dash_hit_enemies.has(body):
			var enemy := body as Enemy
			_dash_hit_enemies.append(enemy)
			enemy.take_damage(DASH_DAMAGE)
			# Knockback dans la direction du dash
			enemy.apply_knockback(_dash_dir, DASH_KNOCKBACK)


# =============================================================
# SANTÉ
# =============================================================

func take_damage(amount: int) -> void:
	if is_dead or _invincible:
		return

	current_hp = max(0, current_hp - amount)
	hp_changed.emit(current_hp)

	if current_hp == 0:
		_die()
	else:
		_start_iframes()


# Invincibilité temporaire avec clignotement visuel
func _start_iframes() -> void:
	_invincible = true

	# Clignotement : Node3D n'a pas modulate, on toggle la visibilité
	if _iframe_tween:
		_iframe_tween.kill()
	_iframe_tween = create_tween().set_loops()
	_iframe_tween.tween_callback(func(): robot_model.visible = not robot_model.visible)
	_iframe_tween.tween_interval(0.08)

	# Attendre la fin de la durée d'invincibilité
	await get_tree().create_timer(iframe_duration).timeout

	# Remettre le modèle visible
	_invincible = false
	if _iframe_tween:
		_iframe_tween.kill()
		_iframe_tween = null
	robot_model.visible = true


func heal(amount: int) -> void:
	if is_dead:
		return

	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp)


func _die() -> void:
	is_dead = true

	# Stopper le clignotement des iframes si actif au moment de la mort
	if _iframe_tween:
		_iframe_tween.kill()
		_iframe_tween = null
	robot_model.visible = true

	# Déclenché ici directement car _physics_process retourne immédiatement
	# quand is_dead est true — _update_animation() ne serait jamais appelée.
	var playback := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	playback.travel("die")
	player_died.emit()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
