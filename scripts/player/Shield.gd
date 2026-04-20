# =============================================================
# Shield.gd — Rotation du bouclier + logique de parade + visuel
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Shield
extends Node3D

# --- Exports -----------------------------------------------------
@export var orbit_radius: float = 0.8

# --- Références nœuds --------------------------------------------
@onready var parry_timer: ParryTimer = $ParryTimer
@onready var hit_area: Area3D        = $HitArea

# --- Scène de la balle renvoyée ----------------------------------
var _bullet_reflected_scene: PackedScene = preload("res://scenes/enemies/bullet_reflected.tscn")

# --- Variables d'état --------------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var _shield_direction: Vector3 = Vector3.FORWARD
var _pending_bullet: Bullet    = null

# --- Visuels -----------------------------------------------------
var _base_color: Color          = Color(0.0, 0.7, 1.0, 0.85)
var _shield_mat: ShaderMaterial
var _mesh_instance: MeshInstance3D


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	player = get_parent()
	camera = get_viewport().get_camera_3d()

	hit_area.area_entered.connect(_on_bullet_entered)
	parry_timer.parry_resolved.connect(_on_parry_resolved)

	_setup_shield_visual()


func _setup_shield_visual() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()

	_mesh_instance      = MeshInstance3D.new()
	var quad            := QuadMesh.new()
	quad.size            = Vector2(1.0, 1.5)
	_mesh_instance.mesh  = quad
	add_child(_mesh_instance)

	var shader         := Shader.new()
	shader.code         = _shader_code()
	_shield_mat         = ShaderMaterial.new()
	_shield_mat.shader  = shader
	_shield_mat.set_shader_parameter("shield_color", _base_color)
	_shield_mat.set_shader_parameter("intensity",    1.5)
	_shield_mat.set_shader_parameter("hex_scale",    6.0)
	_shield_mat.set_shader_parameter("pulse_speed",  1.5)
	_shield_mat.set_shader_parameter("wave_speed",   3.0)
	_mesh_instance.material_override = _shield_mat


func _shader_code() -> String:
	return (
	  "shader_type spatial;\n"
	+ "render_mode blend_add, depth_draw_never, cull_disabled, unshaded;\n"
	+ "uniform vec4  shield_color : source_color = vec4(0.0,0.7,1.0,0.85);\n"
	+ "uniform float intensity    : hint_range(0.0,5.0)  = 1.5;\n"
	+ "uniform float hex_scale    : hint_range(1.0,20.0) = 6.0;\n"
	+ "uniform float pulse_speed  : hint_range(0.1,5.0)  = 1.5;\n"
	+ "uniform float wave_speed   : hint_range(0.1,10.0) = 3.0;\n"
	+ "vec2 hex_center(vec2 p){\n"
	+ "  vec2 r=vec2(1.0,1.732); vec2 h=r*0.5;\n"
	+ "  vec2 a=mod(p,r)-h; vec2 b=mod(p-h,r)-h;\n"
	+ "  return dot(a,a)<dot(b,b)?a:b;}\n"
	+ "void fragment(){\n"
	+ "  vec2 uv=UV*2.0-1.0;\n"
	+ "  float sd=length(uv*vec2(0.85,1.0));\n"
	+ "  float shape=1.0-smoothstep(0.75,1.0,sd);\n"
	+ "  if(shape<0.001){discard;}\n"
	+ "  float pulse=sin(TIME*pulse_speed)*0.5+0.5;\n"
	+ "  vec2 hex=hex_center(UV*hex_scale);\n"
	+ "  float hd=length(hex);\n"
	+ "  float hline=1.0-smoothstep(0.04,0.14,hd);\n"
	+ "  float hglow=exp(-hd*10.0)*0.25;\n"
	+ "  float edge=smoothstep(0.45,0.85,sd);\n"
	+ "  float wave=pow(sin(UV.y*10.0-TIME*wave_speed)*0.5+0.5,5.0)*0.35;\n"
	+ "  float b=(hline*0.65+hglow+edge*0.9+wave+pulse*0.12)*shape;\n"
	+ "  vec3 holo=shield_color.rgb+vec3(-0.05,0.05,0.15)*(UV.y-0.5);\n"
	+ "  ALBEDO=holo;\n"
	+ "  ALPHA=clamp(b*intensity*shield_color.a,0.0,1.0);\n"
	+ "  EMISSION=holo*(hline+edge*0.6+pulse*0.08)*intensity;}\n"
	)


func _process(_delta: float) -> void:
	_orbit_toward_mouse()


# =============================================================
# ROTATION ORBITALE
# =============================================================

func _orbit_toward_mouse() -> void:
	if camera == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_orig  := camera.project_ray_origin(mouse_pos)
	var ray_dir   := camera.project_ray_normal(mouse_pos)
	var plane_y   := player.global_position.y

	if abs(ray_dir.y) < 0.001:
		return

	var t         := (plane_y - ray_orig.y) / ray_dir.y
	var world_pos := ray_orig + ray_dir * t
	var dir       := (world_pos - player.global_position)
	dir.y          = 0.0

	if dir.length() < 0.01:
		return

	dir                = dir.normalized()
	_shield_direction   = dir
	global_position     = player.global_position + dir * orbit_radius
	global_position.y   = player.global_position.y
	global_rotation.y   = atan2(dir.x, dir.z)


# =============================================================
# DÉTECTION BALLE
# =============================================================

func _on_bullet_entered(area: Area3D) -> void:
	if not area is Bullet:
		return
	_pending_bullet = area
	parry_timer.on_bullet_impact()


# =============================================================
# RÉSOLUTION DE LA PARADE
# =============================================================

func _on_parry_resolved(state: ParryTimer.ParryState) -> void:
	if _pending_bullet == null:
		return

	match state:
		ParryTimer.ParryState.ABSORB:
			_pending_bullet.queue_free()
			_flash_shield(Color(0.5, 0.6, 0.8, 0.6), 0.25)

		ParryTimer.ParryState.STANDARD:
			_spawn_reflected_bullet(10, false)
			_pending_bullet.queue_free()
			_flash_shield(Color(1.0, 1.0, 1.0, 1.0), 0.3)

		ParryTimer.ParryState.CRITICAL:
			_spawn_reflected_bullet(25, true)
			_pending_bullet.queue_free()
			_flash_shield(Color(1.0, 0.75, 0.0, 1.0), 0.45)

	_pending_bullet = null


# =============================================================
# FLASH DE PARADE
# =============================================================

func _flash_shield(flash_color: Color, duration: float) -> void:
	if _shield_mat == null:
		return

	_shield_mat.set_shader_parameter("shield_color", flash_color)
	_shield_mat.set_shader_parameter("intensity",    2.5)

	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		func(c: Color): _shield_mat.set_shader_parameter("shield_color", c),
		flash_color, _base_color, duration
	)
	tween.tween_method(
		func(v: float): _shield_mat.set_shader_parameter("intensity", v),
		2.5, 1.5, duration
	)


# =============================================================
# RENVOI DE BALLE
# =============================================================

func _spawn_reflected_bullet(bullet_damage: int, is_critical: bool = false) -> void:
	var bullet: BulletReflected = _bullet_reflected_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.init(global_position, _shield_direction, bullet_damage, is_critical)
