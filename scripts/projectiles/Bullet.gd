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
const C_BULLET := Color(1.0, 0.50, 0.10)

# --- Variables internes ------------------------------------------
var direction: Vector3 = Vector3.ZERO
var _mat: StandardMaterial3D = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	add_to_group("bullets")   # Détectable par Player._find_nearest_threat() (auto-face mobile)
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
	# ── Corps : cube orange vif ───────────────────────────────────
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.18, 0.24)
	$MeshInstance3D.mesh = box

	_mat = StandardMaterial3D.new()
	_mat.albedo_color              = Color(1.0, 0.50, 0.10)   # orange pur
	_mat.emission_enabled          = true
	_mat.emission                  = Color(1.0, 0.38, 0.0)    # orange profond
	_mat.emission_energy_multiplier = 2.8                      # réduit pour éviter le halo
	$MeshInstance3D.set_surface_override_material(0, _mat)

	# ── Traînée conique (large côté balle, effilée à l'arrière) ──
	var cone := CylinderMesh.new()
	cone.top_radius     = 0.0      # pointu à l'arrière
	cone.bottom_radius  = 0.080    # large contre le cube
	cone.height         = 0.90
	cone.radial_segments = 8
	cone.rings           = 1

	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color              = Color(1.0, 0.42, 0.06, 0.88)
	trail_mat.emission_enabled          = true
	trail_mat.emission                  = Color(0.95, 0.28, 0.0)
	trail_mat.emission_energy_multiplier = 2.5
	trail_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.cull_mode                 = BaseMaterial3D.CULL_DISABLED

	var trail := MeshInstance3D.new()
	trail.name       = "Trail"
	trail.mesh       = cone
	trail.rotation.x = PI * 0.5        # CylinderMesh vertical → orienté sur Z
	trail.position   = Vector3(0.0, 0.0, 0.50)   # centre du cône derrière le cube
	trail.set_surface_override_material(0, trail_mat)
	add_child(trail)
	# Pas de pulsation — rendu propre et stable comme dans le splash screen


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
	# Orienter le nœud : look_at fait pointer -Z vers la cible,
	# donc +Z (= arrière) est opposé au tir → la traînée suit automatiquement.
	_orient_to_direction()


func _orient_to_direction() -> void:
	if direction.length_squared() < 0.01:
		return
	var up := Vector3.UP if abs(direction.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	look_at(global_position + direction, up)


# =============================================================
# COLLISIONS
# =============================================================

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.take_damage(damage)
		_spawn_impact(C_BULLET, 6)
	else:
		# Décor / géométrie statique : impact réduit et destruction
		_spawn_impact(C_BULLET, 3)
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
