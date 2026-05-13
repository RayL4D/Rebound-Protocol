# =============================================================
# BulletReflected.gd — Balle renvoyée par le bouclier du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name BulletReflected
extends Area3D

# --- Exports -----------------------------------------------------
@export var speed: float = 16.0

# --- Palette clairement distincte de la balle ennemie (rouge) ---
# Normale  → CYAN   (couleur identitaire du joueur / bouclier)
# Critique → OR     (identique au flash bouclier en parade parfaite)
#            JAMAIS rouge pour ne pas confondre avec l'ennemi
const C_NORMAL   := Color(0.0,  0.85, 1.0)   # cyan
const C_CRITICAL := Color(1.0,  0.78, 0.0)   # or

# --- Variables internes ------------------------------------------
var direction: Vector3 = Vector3.ZERO
var damage: int        = 10
var _is_critical: bool = false
var _mat: StandardMaterial3D = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	$VisibleOnScreenNotifier3D.screen_exited.connect(_on_screen_exited)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


# =============================================================
# INITIALISATION — appelée par Shield.gd après add_child()
# =============================================================

func init(spawn_position: Vector3, target_direction: Vector3,
		bullet_damage: int, is_critical: bool = false) -> void:
	global_position  = spawn_position
	direction        = target_direction.normalized()
	damage           = bullet_damage
	_is_critical     = is_critical

	# Vitesse de renvoi : +20 % par palier (upgrade "reflect_speed")
	var speed_mult := 1.0 + (SaveData.get_upgrade_value("reflect_speed") if SaveData.active_slot >= 0 else 0.0)
	speed = 16.0 * speed_mult

	_setup_visuals(C_CRITICAL if is_critical else C_NORMAL, is_critical)


# =============================================================
# VISUELS
# =============================================================

func _setup_visuals(color: Color, critical: bool) -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color              = color
	_mat.emission_enabled          = true
	_mat.emission                  = color
	_mat.emission_energy_multiplier = 4.0
	$MeshInstance3D.set_surface_override_material(0, _mat)
	"""
	# Lumière dynamique — plus grande et brillante pour le critique
	var light := OmniLight3D.new()
	light.light_color  = color
	light.light_energy = 4.0 if critical else 3.0
	light.omni_range   = 3.5 if critical else 2.5
	add_child(light)
	"""
	# Pulsation — critique plus rapide et plus contrastée
	var lo  := 3.5 if not critical else 5.0
	var hi  := 7.0 if not critical else 12.0
	var dur := 0.20 if not critical else 0.10
	var tw := create_tween().set_loops()
	tw.tween_method(_set_emission.bind(_mat), lo, hi, dur)
	tw.tween_method(_set_emission.bind(_mat), hi, lo, dur)


func _set_emission(value: float, mat: StandardMaterial3D) -> void:
	mat.emission_energy_multiplier = value


# =============================================================
# COLLISIONS
# =============================================================

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies"):
		body.take_damage(damage)
		_spawn_impact()
		queue_free()


func _on_screen_exited() -> void:
	queue_free()


# =============================================================
# IMPACT — explosion de particules
# =============================================================

func _spawn_impact() -> void:
	if not is_inside_tree():
		return
	var origin := global_position
	var root   := get_tree().current_scene
	var color  := C_CRITICAL if _is_critical else C_NORMAL
	var count  := 12 if _is_critical else 8

	for i in count:
		var angle := TAU * float(i) / float(count)
		var dir: Vector3
		if i < count - 2:
			dir = Vector3(cos(angle), randf_range(0.0, 0.5), sin(angle)).normalized()
		else:
			dir = Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
		_spawn_spark(root, origin, dir,
			randf_range(1.5, 3.0 if _is_critical else 2.2), color)

	# Flash blanc central sur critique
	if _is_critical:
		_spawn_spark(root, origin, Vector3.UP * 0.3, 0.4, Color.WHITE)


func _spawn_spark(parent: Node, origin: Vector3, dir: Vector3,
		spd: float, color: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius          = 0.045 if _is_critical else 0.033
	sm.height          = sm.radius * 2.0
	sm.radial_segments = 4
	sm.rings           = 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.emission_enabled          = true
	mat.emission                  = color
	mat.emission_energy_multiplier = 4.5
	mat.no_depth_test             = true

	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	mi.global_position = origin

	var dur    := randf_range(0.22, 0.48)
	var target := origin + dir * spd

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", target, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_method(_scale_node.bind(mi), 1.0, 0.0, dur)
	tw.tween_callback(mi.queue_free)


func _scale_node(value: float, node: Node3D) -> void:
	node.scale = Vector3.ONE * value
