# =============================================================
# Bullet.gd — Projectile ennemi
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Bullet
extends Area3D

# --- Exports -----------------------------------------------------
@export var speed: float  = 12.0
@export var damage: int   = 10

# --- Palette : rouge-orangé menaçant ----------------------------
const C_BULLET := Color(1.0, 0.18, 0.0)

# --- Variables internes ------------------------------------------
var direction: Vector3 = Vector3.ZERO
var _mat: StandardMaterial3D = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	$VisibleOnScreenNotifier3D.screen_exited.connect(_on_screen_exited)
	body_entered.connect(_on_body_entered)
	_setup_visuals()

	# Compétence enemy_slowdown : ralentit les balles ennemies de 15 % par stack
	if get_tree().root.has_node("XpManager"):
		speed *= XpManager.enemy_bullet_speed_mult


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


# =============================================================
# VISUELS
# =============================================================

func _setup_visuals() -> void:
	# Matériau émissif rouge-orangé
	_mat = StandardMaterial3D.new()
	_mat.albedo_color              = C_BULLET
	_mat.emission_enabled          = true
	_mat.emission                  = C_BULLET
	_mat.emission_energy_multiplier = 3.5
	$MeshInstance3D.set_surface_override_material(0, _mat)
	"""
	# Lumière ambiante rouge-orangée
	var light := OmniLight3D.new()
	light.light_color  = C_BULLET
	light.light_energy = 2.5
	light.omni_range   = 2.2
	add_child(light)
	"""
	# Pulsation d'émission
	_pulse(_mat, 2.5, 5.0, 0.22)


func _pulse(mat: StandardMaterial3D, lo: float, hi: float, dur: float) -> void:
	var tw := create_tween().set_loops()
	tw.tween_method(_set_emission.bind(mat), lo, hi, dur)
	tw.tween_method(_set_emission.bind(mat), hi, lo, dur)


func _set_emission(value: float, mat: StandardMaterial3D) -> void:
	mat.emission_energy_multiplier = value


# =============================================================
# INITIALISATION
# =============================================================

func init(spawn_position: Vector3, target_direction: Vector3) -> void:
	global_position = spawn_position
	direction       = target_direction.normalized()


# =============================================================
# COLLISIONS
# =============================================================

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.take_damage(damage)
		_spawn_impact(C_BULLET, 6)
		queue_free()


func _on_screen_exited() -> void:
	queue_free()


# =============================================================
# IMPACT
# =============================================================

func _spawn_impact(color: Color, count: int) -> void:
	if not is_inside_tree():
		return
	var origin := global_position
	var root   := get_tree().current_scene
	for i in count:
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.1, 0.9),
			randf_range(-1.0, 1.0)
		).normalized()
		_spawn_spark(root, origin, dir, randf_range(0.9, 2.0), color)


func _spawn_spark(parent: Node, origin: Vector3, dir: Vector3,
		spd: float, color: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius          = 0.035
	sm.height          = 0.07
	sm.radial_segments = 4
	sm.rings           = 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.emission_enabled          = true
	mat.emission                  = color
	mat.emission_energy_multiplier = 4.0
	mat.no_depth_test             = true

	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	mi.global_position = origin

	var dur    := randf_range(0.18, 0.38)
	var target := origin + dir * spd

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", target, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_method(_scale_node.bind(mi), 1.0, 0.0, dur)
	tw.tween_callback(mi.queue_free)


func _scale_node(value: float, node: Node3D) -> void:
	node.scale = Vector3.ONE * value
