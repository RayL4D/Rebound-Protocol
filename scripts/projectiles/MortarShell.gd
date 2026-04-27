# =============================================================
# MortarShell.gd — Projectile visuel du mortier (grenade en arc)
# Rebound Protocol
# =============================================================
# Phase 1 (vol) : grenade-b.glb suit un arc parabolique en tournoyant
# Phase 2 (impact) : flash d'explosion sphérique, puis queue_free
# Les dégâts sont toujours gérés par MortarWarning.
# =============================================================
class_name MortarShell
extends Node3D

const GRENADE_SCENE: PackedScene = preload("res://assets/models/weapons/grenade-b.glb")
const COLORMAP:      Texture2D   = preload("res://assets/textures/weapons/colormap.png")

# --- Trajectoire -----------------------------------------------
var _start_pos:   Vector3
var _end_pos:     Vector3
var _duration:    float = 1.0
var _elapsed:     float = 0.0
var _arc_height:  float = 3.0

# --- Rotation (tumble) -----------------------------------------
var _spin_axis:   Vector3 = Vector3.RIGHT
var _spin_speed:  float   = 6.0   # rad/s

# --- Nœuds visuels ---------------------------------------------
var _grenade_inst:    Node3D          = null
var _explosion_mesh:  MeshInstance3D  = null
var _explosion_mat:   StandardMaterial3D = null

# --- État de la phase d'explosion ------------------------------
var _landed:              bool  = false
var _explosion_elapsed:   float = 0.0
const EXPLOSION_DURATION: float = 0.35
const EXPLOSION_RADIUS:   float = 0.9

var _ready_to_process: bool = false


# =============================================================
# INITIALISATION — appeler juste après add_child()
# =============================================================

func init(start: Vector3, end: Vector3, duration: float) -> void:
	_start_pos  = start
	_end_pos    = end
	_duration   = duration

	# Arc proportionnel à la distance (min 1.5, max 5.0)
	_arc_height = clampf(start.distance_to(end) * 0.35, 1.5, 5.0)

	# Axe de rotation : perpendiculaire au déplacement XZ → effet "grenade qui tourne"
	var dir := end - start
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		_spin_axis = Vector3.UP.cross(dir.normalized()).normalized()
	else:
		_spin_axis = Vector3.RIGHT

	global_position = start
	_create_grenade()
	_create_explosion_mesh()

	_ready_to_process = true


# =============================================================
# LIFECYCLE
# =============================================================

func _process(delta: float) -> void:
	if not _ready_to_process:
		return

	if not _landed:
		_elapsed += delta
		var t := clampf(_elapsed / _duration, 0.0, 1.0)

		# Position XZ linéaire + Y parabolique
		var p := _start_pos.lerp(_end_pos, t)
		p.y    = lerpf(_start_pos.y, _end_pos.y, t) + _arc_height * 4.0 * t * (1.0 - t)
		global_position = p

		# Rotation progressive : la grenade accélère en fin de trajectoire
		var spin := _spin_speed * (1.0 + t)
		if _grenade_inst != null:
			_grenade_inst.rotate(_spin_axis, spin * delta)

		if _elapsed >= _duration:
			_on_land()
	else:
		# Phase explosion
		_explosion_elapsed += delta
		_update_explosion(_explosion_elapsed / EXPLOSION_DURATION)

		if _explosion_elapsed >= EXPLOSION_DURATION:
			queue_free()


# =============================================================
# ATTERRISSAGE
# =============================================================

func _on_land() -> void:
	_landed = true

	# Cache la grenade, ancre le shell à la position d'impact
	if _grenade_inst != null:
		_grenade_inst.visible = false

	global_position = _end_pos

	# Lance l'explosion
	if _explosion_mesh != null:
		_explosion_mesh.visible = true


# =============================================================
# ANIMATION DE L'EXPLOSION
# =============================================================

func _update_explosion(t: float) -> void:
	if _explosion_mesh == null or _explosion_mat == null:
		return

	# t : 0 → 1 pendant EXPLOSION_DURATION
	# Sphère qui s'agrandit vite puis se dissipe
	var s := lerpf(0.1, EXPLOSION_RADIUS * 2.0, t)
	_explosion_mesh.scale = Vector3(s, s, s)

	# Couleur : blanc chaud → orange → transparent
	var r := 1.0
	var g := lerpf(1.0, 0.3, t)
	var b := lerpf(0.8, 0.0, t)
	var a := lerpf(0.9, 0.0, t)
	_explosion_mat.albedo_color = Color(r, g, b, a)
	_explosion_mat.emission_energy_multiplier = lerpf(4.0, 0.0, t)


# =============================================================
# CRÉATION DES NŒUDS VISUELS
# =============================================================

func _create_grenade() -> void:
	_grenade_inst = GRENADE_SCENE.instantiate()
	_grenade_inst.scale = Vector3(1.5, 1.5, 1.5)
	add_child(_grenade_inst)
	_apply_texture(_grenade_inst)


func _apply_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = COLORMAP
		(node as MeshInstance3D).set_surface_override_material(0, mat)
	for child in node.get_children():
		_apply_texture(child)


func _create_explosion_mesh() -> void:
	_explosion_mesh = MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius          = 1.0
	sphere.height          = 2.0
	sphere.radial_segments = 12
	sphere.rings           = 6
	_explosion_mesh.mesh   = sphere

	_explosion_mat = StandardMaterial3D.new()
	_explosion_mat.albedo_color               = Color(1.0, 0.9, 0.7, 0.9)
	_explosion_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_explosion_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_explosion_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_explosion_mat.emission_enabled           = true
	_explosion_mat.emission                   = Color(1.0, 0.5, 0.1)
	_explosion_mat.emission_energy_multiplier = 4.0
	_explosion_mesh.set_surface_override_material(0, _explosion_mat)

	_explosion_mesh.scale   = Vector3(0.1, 0.1, 0.1)
	_explosion_mesh.visible = false   # invisible jusqu'à l'impact
	add_child(_explosion_mesh)
