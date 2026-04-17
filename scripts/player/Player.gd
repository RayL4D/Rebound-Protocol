# =============================================================
# Player.gd — Contrôleur principal du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Player
extends CharacterBody3D

# --- Exports (modifiables dans l'inspector Godot) ----------------
@export var move_speed: float = 5.0
@export var max_hp: int   = 100

# --- Références nœuds --------------------------------------------
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var shield: Node3D          = $Shield
@onready var robot_model: Node3D     = $RobotModel

# Texture du modèle — chargée une seule fois au démarrage
var _player_texture: Texture2D = preload("res://assets/textures/player/texture-g.png")

# --- Variables d'état --------------------------------------------
var current_hp: int
var is_dead: bool = false

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

	# Évite l'éjection verticale par la collision trimesh du sol
	floor_snap_length = 0.3

	# La SpringArm3D se détache du parent → suit le joueur en position
	# mais garde sa rotation d'éditeur (tilt -60° top-down)
	spring_arm.set_as_top_level(true)

	add_to_group("player")
	_apply_texture_recursive(robot_model)

	# Stoppe l'AnimationPlayer intégré au GLB Kenney pour éviter l'autoplay
	# qui cause le root motion (personnage qui dérive tout seul).
	# find_child cherche en profondeur dans toute la hiérarchie du GLB.
	# L'AnimationTree prendra le relais à l'étape 5.
	var anim_player := robot_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		anim_player.stop()


# Applique la texture sur tous les MeshInstance3D du modèle (tête, torse,
# bras, jambes) en un seul appel. Plus fiable que de le faire manuellement
# dans l'éditeur car ça résiste aux réécritures du .tscn par Godot.
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
	move_and_slide()

	# La caméra pivote depuis le centre du personnage (pas depuis ses pieds).
	# Sans l'offset Y, le pivot est à Y=0 (pieds) et la caméra regarde les jambes.
	spring_arm.global_position = global_position + Vector3(0, 0.9, 0)

	# Annule le root motion résiduel du GLB frame par frame
	robot_model.position = Vector3.ZERO


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		# Reset Y immédiatement au sol — évite l'éjection par la trimesh
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


func _handle_movement() -> void:
	# get_axis retourne -1 / 0 / 1 selon les actions InputMap
	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_z: float = Input.get_axis("move_forward", "move_backward")

	var input_dir := Vector2(input_x, input_z)

	# Normaliser pour éviter le déplacement diagonal plus rapide
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	# Input 2D → direction 3D (top-down : Z = profondeur)
	velocity.x = input_dir.x * move_speed
	velocity.z = input_dir.y * move_speed


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
