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
@onready var shield: Node3D         = $Shield

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
	# La SpringArm3D est fixée dans l'éditeur (rotation X = -55°)
	# Elle ne tourne pas avec le joueur — caméra top-down statique
	spring_arm.set_as_top_level(true)
	# Ajouter le joueur au groupe "player" pour que les ennemis
	# puissent le retrouver via get_tree().get_first_node_in_group("player")
	add_to_group("player")


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_apply_gravity(delta)
	_handle_movement()
	move_and_slide()

	# La caméra suit le joueur même si top_level = true
	spring_arm.global_position = global_position


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
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
