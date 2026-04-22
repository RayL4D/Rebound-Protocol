# =============================================================
# MortarWarning.gd — Indicateur de zone d'impact différé
# Rebound Protocol
# =============================================================
class_name MortarWarning
extends Node3D

# --- État interne -----------------------------------------------
var _delay: float  = 1.0  # valeur par défaut non-nulle (évite division par zéro)
var _radius: float = 1.5
var _damage: int   = 10
var _elapsed: float = 0.0
var _player: Player = null
var _ready_to_process: bool = false  # vrai seulement après init()

# Référence au mesh pour l'animer
var _mesh_inst: MeshInstance3D
var _mat: StandardMaterial3D


# =============================================================
# INITIALISATION — appeler juste après add_child()
# =============================================================

func init(pos: Vector3, delay: float, radius: float, dmg: int) -> void:
	_delay  = delay
	_radius = radius
	_damage = dmg
	_player = get_tree().get_first_node_in_group("player")

	# Utiliser global_position pour ignorer le transform du nœud parent.
	# pos.y est calculé par WeaponMortar comme pieds du joueur + 0.05 (offset sol).
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

	# La couleur vire de orange à rouge vif à l'approche de l'impact
	var g: float = lerpf(0.5, 0.0, t)
	var a: float = lerpf(0.4, 0.85, t)
	_mat.albedo_color = Color(1.0, g, 0.0, a)

	if _elapsed >= _delay:
		_impact()


# =============================================================
# IMPACT
# =============================================================

func _impact() -> void:
	if _player != null:
		# Comparer uniquement X et Z — la hauteur n'a pas d'importance
		var self_xz   := Vector2(global_position.x, global_position.z)
		var player_xz := Vector2(_player.global_position.x, _player.global_position.z)
		if self_xz.distance_to(player_xz) <= _radius:
			_player.take_damage(_damage)

	queue_free()


# =============================================================
# CRÉATION DU MESH
# =============================================================

func _create_warning_mesh() -> void:
	_mesh_inst = MeshInstance3D.new()

	var cyl             := CylinderMesh.new()
	cyl.top_radius       = _radius
	cyl.bottom_radius    = _radius
	cyl.height           = 0.04
	cyl.radial_segments  = 32
	_mesh_inst.mesh      = cyl

	_mat = StandardMaterial3D.new()
	_mat.albedo_color  = Color(1.0, 0.5, 0.0, 0.4)
	_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.no_depth_test = false
	_mesh_inst.set_surface_override_material(0, _mat)

	add_child(_mesh_inst)
	# Pas d'offset Y sur le mesh — la position du nœud parent gère tout
	scale = Vector3(0.05, 1.0, 0.05)
