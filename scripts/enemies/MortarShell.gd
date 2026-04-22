# =============================================================
# MortarShell.gd — Projectile visuel du mortier (arc parabolique)
# Rebound Protocol
# =============================================================
# Purement visuel : ne fait aucun dégât.
# Les dégâts sont gérés par MortarWarning qui expire en même temps
# que ce projectile atterrit.
# =============================================================
class_name MortarShell
extends Node3D

var _start_pos: Vector3
var _end_pos:   Vector3
var _duration:  float = 1.0
var _elapsed:   float = 0.0
var _arc_height: float = 3.0
var _ready_to_process: bool = false

var _mat: StandardMaterial3D


# =============================================================
# INITIALISATION — appeler juste après add_child()
# =============================================================

func init(start: Vector3, end: Vector3, duration: float) -> void:
	_start_pos  = start
	_end_pos    = end
	_duration   = duration
	# Hauteur de l'arc proportionnelle à la distance (min 1.5, max 5.0)
	_arc_height = clampf(start.distance_to(end) * 0.35, 1.5, 5.0)

	global_position = start
	_create_mesh()
	_ready_to_process = true


# =============================================================
# LIFECYCLE
# =============================================================

func _process(delta: float) -> void:
	if not _ready_to_process:
		return

	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)

	# Position XZ : interpolation linéaire
	var p := _start_pos.lerp(_end_pos, t)

	# Position Y : arc parabolique par-dessus la ligne de tir
	# 4 * h * t * (1-t) = parabole qui vaut 0 en t=0 et t=1, max h en t=0.5
	p.y = lerpf(_start_pos.y, _end_pos.y, t) + _arc_height * 4.0 * t * (1.0 - t)

	global_position = p

	# Éclat lumineux dans la dernière portion de la trajectoire (descente finale)
	var glow: float = clampf((t - 0.65) / 0.35, 0.0, 1.0)
	_mat.emission_energy_multiplier = lerpf(0.6, 4.0, glow)

	if _elapsed >= _duration:
		queue_free()


# =============================================================
# CRÉATION DU MESH — petite sphère lumineuse
# =============================================================

func _create_mesh() -> void:
	var inst   := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius          = 0.14
	sphere.height          = 0.28
	sphere.radial_segments = 8
	sphere.rings           = 4
	inst.mesh = sphere

	_mat = StandardMaterial3D.new()
	_mat.albedo_color               = Color(1.0, 0.55, 0.0, 1.0)
	_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled           = true
	_mat.emission                   = Color(1.0, 0.35, 0.0)
	_mat.emission_energy_multiplier = 0.6
	inst.set_surface_override_material(0, _mat)

	add_child(inst)
