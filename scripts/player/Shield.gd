# =============================================================
# Shield.gd — Rotation du bouclier + logique de parade + visuel
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
# Le visuel (MeshInstance3D + ShaderMaterial) est configuré dans
# l'éditeur sur le nœud enfant "ShieldMesh". Le script récupère
# le matériau au démarrage pour gérer les flashes de parade.
# =============================================================
class_name Shield
extends Node3D

# --- Exports -----------------------------------------------------
@export var orbit_radius: float = 0.8

# --- Références nœuds --------------------------------------------
@onready var parry_timer:    ParryTimer      = $ParryTimer
@onready var hit_area:       Area3D          = $HitArea
@onready var _mesh_instance: MeshInstance3D  = $ShieldMesh

# --- Scène de la balle renvoyée ----------------------------------
var _bullet_reflected_scene: PackedScene = preload("res://scenes/enemies/bullet_reflected.tscn")

# --- Variables d'état --------------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var _shield_direction: Vector3 = Vector3.FORWARD
var _pending_bullet: Bullet    = null

# --- Matériau (lu depuis ShieldMesh dans l'éditeur) --------------
var _shield_mat: ShaderMaterial
var _base_color: Color


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	player = get_parent()
	camera = get_viewport().get_camera_3d()

	hit_area.area_entered.connect(_on_bullet_entered)
	parry_timer.parry_resolved.connect(_on_parry_resolved)

	# Chercher le ShaderMaterial : d'abord en Material Override, sinon en surface 0
	_shield_mat = _mesh_instance.material_override as ShaderMaterial
	if _shield_mat == null:
		_shield_mat = _mesh_instance.get_surface_override_material(0) as ShaderMaterial
	if _shield_mat == null:
		push_error("Shield: aucun ShaderMaterial trouvé sur ShieldMesh — vérifie l'éditeur.")
		return

	# Lire la couleur de base depuis le matériau (définie dans l'inspector)
	_base_color = _shield_mat.get_shader_parameter("shield_color")


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
