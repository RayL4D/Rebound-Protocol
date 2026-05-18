# =============================================================
# MortarWarning.gd — Indicateur de zone d'impact différé
# Rebound Protocol
# =============================================================
class_name MortarWarning
extends Node3D

# --- État interne -----------------------------------------------
var _delay: float   = 1.0
var _radius: float  = 1.5
var _damage: int    = 10
var _elapsed: float = 0.0
var _player: Player = null
var _ready_to_process: bool = false

var _mesh_inst: MeshInstance3D
var _mat: StandardMaterial3D

# Phase accumulée séparément pour un clignotement propre (chirp correct)
var _blink_phase: float = 0.0


# =============================================================
# INITIALISATION — appeler juste après add_child()
# =============================================================

func init(pos: Vector3, delay: float, radius: float, dmg: int) -> void:
	_delay  = delay
	_radius = radius
	_damage = dmg
	_player = get_tree().get_first_node_in_group("player")

	# global_position ignore le transform du parent —
	# pos.y est calculé par WeaponMortar (pieds du joueur + 0.05)
	global_position = pos

	_create_warning_mesh()
	_ready_to_process = true


# =============================================================
# LIFECYCLE
# =============================================================

func _process(delta: float) -> void:
	if not _ready_to_process:
		return

	_elapsed += delta
	var t := clampf(_elapsed / _delay, 0.0, 1.0)

	# Le disque s'agrandit progressivement vers sa taille finale
	var s: float = lerpf(0.1, 1.0, t)
	scale = Vector3(s, 1.0, s)

	# Clignotement : on accumule la phase à la fréquence courante (chirp propre).
	# Multiplier _elapsed par blink_hz serait incorrect — la dérivée de la phase
	# contiendrait un terme parasite (_elapsed * d(blink_hz)/dt) qui emballe la fréquence.
	var blink_hz: float = lerpf(1.5, 10.0, t * t)
	_blink_phase += blink_hz * TAU * delta
	var blink: float = sin(_blink_phase) * 0.5 + 0.5

	# Couleur : orange → rouge vif, alpha suit le clignotement
	var g:     float = lerpf(0.5, 0.0, t)
	var a_min: float = lerpf(0.15, 0.30, t)
	var a_max: float = lerpf(0.65, 0.90, t)
	_mat.albedo_color = Color(1.0, g, 0.0, lerpf(a_min, a_max, blink))

	if _elapsed >= _delay:
		_impact()


# =============================================================
# IMPACT
# =============================================================

const _SFX_EXPLODE: AudioStream = preload("res://audio/sfx/enemies/mortar_explode.wav")

func _impact() -> void:
	if _player != null:
		var self_xz   := Vector2(global_position.x, global_position.z)
		var player_xz := Vector2(_player.global_position.x, _player.global_position.z)
		if self_xz.distance_to(player_xz) <= _radius:
			_player.take_damage(_damage)

	# Player flottant ajouté à /root (plus stable que current_scene lors d'un queue_free)
	if _SFX_EXPLODE != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_EXPLODE
		p.bus         = "SFX"
		p.volume_db   = -3.0
		p.pitch_scale = randf_range(0.93, 1.07)
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

	call_deferred("queue_free")


# =============================================================
# CRÉATION DU MESH
# =============================================================

func _create_warning_mesh() -> void:
	_mesh_inst = MeshInstance3D.new()

	var cyl            := CylinderMesh.new()
	cyl.top_radius      = _radius
	cyl.bottom_radius   = _radius
	cyl.height          = 0.04
	cyl.radial_segments = 32
	_mesh_inst.mesh     = cyl

	_mat = StandardMaterial3D.new()
	_mat.albedo_color  = Color(1.0, 0.5, 0.0, 0.4)
	_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.no_depth_test = false
	_mesh_inst.set_surface_override_material(0, _mat)

	add_child(_mesh_inst)
	scale = Vector3(0.05, 1.0, 0.05)
