# =============================================================
# WeaponSniper.gd — Arme sniper à charge longue (Koala)
# Rebound Protocol
# =============================================================
# Cycle :
#   1. IDLE      : attend d'être à portée
#   2. CHARGING  : immobile, laser rouge + réticule au sol (charge_time s)
#   3. FIRE      : une balle très rapide et très puissante
#   4. COOLDOWN  : recharge avant le prochain cycle
#
# Visuel laser :
#   • Faisceau central fin, vif (blanc-rouge)
#   • Halo extérieur large et transparent (rouge)
#   • Réticule CylinderMesh au sol sur le joueur (pulsant)
#   • Intensité et épaisseur croissantes pendant la charge
#
# NOTE : _create_laser() est appelé en deferred depuis _ready()
#   pour éviter que _apply_texture_recursive() d'Enemy._setup_model()
#   n'écrase notre matériau personnalisé.
# =============================================================
class_name WeaponSniper
extends WeaponBullet

# --- Exports propres à ce type ----------------------------------
@export var charge_time: float = 2.0

# --- Machine à états -------------------------------------------
enum State { IDLE, CHARGING, COOLDOWN }
var _state:          State = State.IDLE
var _charge_elapsed: float = 0.0

# --- Laser — nœuds visuels -------------------------------------
var _laser_root: Node3D             = null   # pivot orienté vers le joueur
var _core_mesh:  MeshInstance3D     = null   # faisceau central fin
var _core_mat:   StandardMaterial3D = null
var _glow_mesh:  MeshInstance3D     = null   # halo extérieur
var _glow_mat:   StandardMaterial3D = null

# --- Réticule — viseur à 4 bras qui se referment ---------------
# Forme distincte du disque MortarWarning : croix ouverte → croix fermée
var _reticle_root: Node3D = null
var _arm_mats:     Array  = []   # Array[StandardMaterial3D] — un par bras
# [0]=droite [1]=gauche [2]=avant [3]=arrière
var _arm_nodes:    Array  = []   # Array[MeshInstance3D]

const ARM_START_OFFSET: float = 0.55   # écart initial du centre
const ARM_END_OFFSET:   float = 0.06   # écart quand pleinement chargé
const ARM_LENGTH:       float = 0.38
const ARM_THICKNESS:    float = 0.07
const ARM_HEIGHT:       float = 0.035

# Accumulateur de phase pour le pulse
var _pulse_phase: float = 0.0


# =============================================================
# INITIALISATION
# =============================================================

# --- Audio ------------------------------------------------------
const _SFX_CHARGE: AudioStream = preload("res://audio/sfx/enemies/sniper_charge.wav")
var _sfx_charge: AudioStreamPlayer = null


func _ready() -> void:
	# Remplace le son de tir standard hérité de WeaponBullet par le son sniper
	_shoot_sfx = preload("res://audio/sfx/enemies/sniper_fire.wav")

	_sfx_charge     = AudioStreamPlayer.new()
	_sfx_charge.bus = "SFX"
	add_child(_sfx_charge)

	# Différé : s'exécute après que Enemy._setup_model() a appliqué
	# ses textures → notre matériau n'est plus écrasé
	call_deferred("_create_laser")


func _create_laser() -> void:
	# ---- Pivot orientable ----------------------------------------
	_laser_root = Node3D.new()
	add_child(_laser_root)

	# ---- Faisceau central (fin, blanc-rouge très lumineux) --------
	_core_mesh = MeshInstance3D.new()
	var core_box      := BoxMesh.new()
	core_box.size      = Vector3(0.035, 0.035, 1.0)
	_core_mesh.mesh    = core_box
	_core_mesh.position.z = -0.5

	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color               = Color(1.0, 0.55, 0.55, 0.95)
	_core_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.emission_enabled           = true
	_core_mat.emission                   = Color(1.0, 0.15, 0.05)
	_core_mat.emission_energy_multiplier = 3.0
	_core_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_core_mesh.set_surface_override_material(0, _core_mat)
	_laser_root.add_child(_core_mesh)

	# ---- Halo extérieur (large, transparent, rouge) ---------------
	_glow_mesh = MeshInstance3D.new()
	var glow_box      := BoxMesh.new()
	glow_box.size      = Vector3(0.18, 0.18, 1.0)
	_glow_mesh.mesh    = glow_box
	_glow_mesh.position.z = -0.5

	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color               = Color(1.0, 0.1, 0.05, 0.12)
	_glow_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.emission_enabled           = true
	_glow_mat.emission                   = Color(1.0, 0.05, 0.0)
	_glow_mat.emission_energy_multiplier = 1.2
	_glow_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_glow_mesh.set_surface_override_material(0, _glow_mat)
	_laser_root.add_child(_glow_mesh)

	# ---- Réticule à 4 bras au sol (viseur qui se referme) ---------
	# Forme distincte du mortier (disque plein) : croix ouverte → fermée
	_reticle_root = Node3D.new()
	get_tree().current_scene.add_child(_reticle_root)

	# Directions des 4 bras : droite, gauche, avant, arrière
	var _offsets := [
		Vector3( 1, 0,  0),
		Vector3(-1, 0,  0),
		Vector3( 0, 0,  1),
		Vector3( 0, 0, -1),
	]
	for i in 4:
		var arm      := MeshInstance3D.new()
		var box      := BoxMesh.new()
		# Bras horizontaux (X) ou verticaux (Z) selon la direction
		var is_horiz := (i < 2)
		box.size      = Vector3(
			ARM_LENGTH if is_horiz else ARM_THICKNESS,
			ARM_HEIGHT,
			ARM_THICKNESS if is_horiz else ARM_LENGTH
		)
		arm.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color               = Color(1.0, 0.85, 0.1, 0.95)   # jaune-blanc chaud
		mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled           = true
		mat.emission                   = Color(1.0, 0.4, 0.0)
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
		arm.set_surface_override_material(0, mat)

		_reticle_root.add_child(arm)
		_arm_nodes.append(arm)
		_arm_mats.append(mat)

	_laser_root.visible    = false
	_reticle_root.visible  = false


# =============================================================
# SURCHARGE _process — machine à états sniper
# =============================================================

func _process(delta: float) -> void:
	if not _active or _target == null:
		_abort_charge()
		return

	match _state:
		State.IDLE:
			if global_position.distance_to(_target.global_position) <= shoot_range:
				_state          = State.CHARGING
				_charge_elapsed = 0.0
				_pulse_phase    = 0.0
				if _laser_root != null:
					_laser_root.visible = true
				if _reticle_root != null:
					_reticle_root.visible = true

		State.CHARGING:
			if global_position.distance_to(_target.global_position) > shoot_range:
				_abort_charge()
				return

			# Jouer le son de charge au début (une seule fois)
			if _charge_elapsed == 0.0 and _sfx_charge != null and _SFX_CHARGE != null:
				_sfx_charge.stream      = _SFX_CHARGE
				_sfx_charge.volume_db   = -10.0
				_sfx_charge.pitch_scale = 1.0
				_sfx_charge.play()

			_charge_elapsed += delta
			_pulse_phase    += delta

			var t := clampf(_charge_elapsed / charge_time, 0.0, 1.0)
			_update_laser(t)
			_update_reticle(t)

			if _charge_elapsed >= charge_time:
				_fire()
				fired.emit()
				_abort_charge()
				_state    = State.COOLDOWN
				_cooldown = 1.0 / fire_rate

		State.COOLDOWN:
			_cooldown -= delta
			if _cooldown <= 0.0:
				_state = State.IDLE


# =============================================================
# MISE À JOUR DES VISUELS
# =============================================================

func _update_laser(t: float) -> void:
	if _laser_root == null or _target == null:
		return

	var dist := global_position.distance_to(_target.global_position)
	if dist < 0.5:
		return

	_laser_root.global_position = global_position
	_laser_root.look_at(_target.global_position, Vector3.UP)

	# Scale des deux meshes pour couvrir la distance exacte
	_core_mesh.scale    = Vector3(1.0, 1.0, dist)
	_core_mesh.position = Vector3(0.0, 0.0, -dist * 0.5)
	_glow_mesh.scale    = Vector3(1.0, 1.0, dist)
	_glow_mesh.position = Vector3(0.0, 0.0, -dist * 0.5)

	# Pulse rapide sur le faisceau — s'accélère et s'intensifie avec la charge
	# _pulse_phase est incrémenté par delta dans _process ; on applique la fréquence ici
	var pulse_hz := lerpf(2.0, 12.0, t * t)
	var pulse    := sin(_pulse_phase * pulse_hz * TAU) * 0.5 + 0.5

	# Faisceau central : s'épaissit et devient plus lumineux
	var core_width := lerpf(0.035, 0.065, t)
	_core_mesh.scale.x = core_width
	_core_mesh.scale.y = core_width
	_core_mat.emission_energy_multiplier = lerpf(3.0, 10.0, t) * lerpf(0.7, 1.0, pulse)

	# Halo : s'élargit et pulse en alpha
	var glow_width := lerpf(0.18, 0.35, t)
	_glow_mesh.scale.x = glow_width
	_glow_mesh.scale.y = glow_width
	_glow_mat.albedo_color.a             = lerpf(0.08, 0.22, pulse)
	_glow_mat.emission_energy_multiplier = lerpf(1.0, 3.5, t * pulse)


func _update_reticle(t: float) -> void:
	if _reticle_root == null or _target == null or _arm_nodes.is_empty():
		return

	# Positionne le réticule aux pieds du joueur
	var feet_pos := _target.global_position
	feet_pos.y   = feet_pos.y - 0.9 + 0.04
	_reticle_root.global_position = feet_pos

	# Les 4 bras se referment vers le centre au fil de la charge
	var offset := lerpf(ARM_START_OFFSET, ARM_END_OFFSET, t)
	var dirs   := [
		Vector3( offset + ARM_LENGTH * 0.5, 0,  0),
		Vector3(-(offset + ARM_LENGTH * 0.5), 0, 0),
		Vector3( 0, 0,  offset + ARM_LENGTH * 0.5),
		Vector3( 0, 0, -(offset + ARM_LENGTH * 0.5)),
	]
	for i in _arm_nodes.size():
		_arm_nodes[i].position = dirs[i]

	# Pulse rapide sur les bras : clignotement qui s'accélère
	var pulse_hz := lerpf(1.5, 10.0, t * t)
	var pulse    := sin(_pulse_phase * pulse_hz * TAU) * 0.5 + 0.5

	# Couleur : jaune-blanc → orange vif → rouge en fin de charge
	var r := 1.0
	var g := lerpf(0.85, 0.0, t)
	for mat in _arm_mats:
		mat.albedo_color               = Color(r, g, 0.05, lerpf(0.7, 1.0, pulse))
		mat.emission_energy_multiplier = lerpf(2.5, 8.0, t) * lerpf(0.6, 1.0, pulse)


# =============================================================
# UTILITAIRES
# =============================================================

func _abort_charge() -> void:
	_state          = State.IDLE
	_charge_elapsed = 0.0
	if _laser_root != null:
		_laser_root.visible = false
	if _reticle_root != null:
		_reticle_root.visible = false


func is_charging() -> bool:
	return _state == State.CHARGING


# Nettoyage du réticule quand le koala meurt
func _exit_tree() -> void:
	if _reticle_root != null and is_instance_valid(_reticle_root):
		_reticle_root.queue_free()
