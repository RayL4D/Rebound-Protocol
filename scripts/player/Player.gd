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
@export var rotation_speed: float = 15.0  # Vitesse d'interpolation de la rotation

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
	_model_base_scale = robot_model.scale  # Mémoriser la scale réelle du modèle

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
	_handle_jump()       # Après gravity : overrride velocity.y si saut demandé
	_handle_movement()
	_rotate_toward_mouse(delta)

	# Déclenche l'animation de parade dès l'appui sur SPACE
	if Input.is_action_just_pressed("parry"):
		_parry_requested = true
		var pb := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		pb.travel("parry")

	move_and_slide()

	spring_arm.global_position = global_position + Vector3(0, 0.9, 0)
	robot_model.position = Vector3.ZERO
	_update_lean(delta)
	_update_animation()


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
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
		floor_snap_length = 0.0   # Laisser le sol pour de vrai
		_squash_stretch_jump()
	elif on_floor and not _was_on_floor:
		floor_snap_length = 0.3   # Rétablir le snap à l'atterrissage
		_squash_stretch_land()
	elif on_floor:
		floor_snap_length = 0.3

	_was_on_floor = on_floor


# Tilt du modèle selon la vélocité verticale — donne l'impression d'un arc
func _update_lean(delta: float) -> void:
	# velocity.y positif = montée → penche en arrière
	# velocity.y négatif = chute → penche en avant
	var target_tilt: float = clamp(-velocity.y * 0.03, -0.3, 0.3)
	robot_model.rotation.x = lerp(robot_model.rotation.x, target_tilt, 12.0 * delta)


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

	velocity.x = input_dir.x * move_speed
	velocity.z = input_dir.y * move_speed


# =============================================================
# ROTATION VERS LA SOURIS
# =============================================================

func _rotate_toward_mouse(delta: float) -> void:
	var mouse_pos     := get_viewport().get_mouse_position()
	var ray_origin    := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)

	if abs(ray_direction.y) < 0.001:
		return

	var t            := (global_position.y - ray_origin.y) / ray_direction.y
	var target_point := ray_origin + ray_direction * t

	var look_dir := (target_point - global_position)
	look_dir.y = 0.0

	if look_dir.length_squared() < 0.01:
		return

	var target_angle := atan2(look_dir.x, look_dir.z)
	robot_model.rotation.y = rotate_toward(
		robot_model.rotation.y,
		target_angle,
		rotation_speed * delta
	)


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
# SANTÉ
# =============================================================

func take_damage(amount: int) -> void:
	if is_dead:
		return

	current_hp = max(0, current_hp - amount)
	hp_changed.emit(current_hp)

	if current_hp == 0:
		_die()


func heal(amount: int) -> void:
	if is_dead:
		return

	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp)


func _die() -> void:
	is_dead = true
	# Déclenché ici directement car _physics_process retourne immédiatement
	# quand is_dead est true — _update_animation() ne serait jamais appelée.
	var playback := anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	playback.travel("die")
	player_died.emit()
