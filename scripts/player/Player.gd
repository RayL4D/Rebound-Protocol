# =============================================================
# Player.gd — Contrôleur principal du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Player
extends CharacterBody3D

# --- Exports (modifiables dans l'inspector Godot) ----------------
@export var move_speed: float     = 5.0
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

	_update_animation()


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


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
	player_died.emit()
