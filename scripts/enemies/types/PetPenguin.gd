# =============================================================
# PetPenguin.gd — Pet glisseur (pingouin)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Alterne entre deux phases : GLISSADE rapide et ARRÊT complet
#   • Pendant la glissade → tire en rafale dans sa direction de course
#   • Pendant l'arrêt → immobile, ne tire plus (fenêtre de vulnérabilité)
#   • Visuellement : le modèle se couche à plat (rotation.x) pendant la glissade
#
# Hiérarchie de scène attendue :
#   PetPenguin (CharacterBody3D) ← ce script
#   ├── animal-penguin2 (modèle GLB)
#   ├── CollisionShape3D
#   ├── WeaponBullet (Node3D) ← logique de tir, enfant direct de la racine
#   └── WeaponMount (Node3D) ← visuel blaster, enfant direct de la racine
#       └── blaster-d2 (modèle GLB)
#
# Pourquoi WeaponMount à la racine et global_transform recalculé chaque frame ?
#
#   animal-penguin2 (GLB Kenney) embarque une rotation baked à l'import.
#   Exprimer le transform de l'arme dans son espace local produit donc
#   des orientations imprévisibles selon le modèle.
#
#   Solution : WeaponMount reste enfant de la racine (texture auto via
#   _setup_model, pas de problème de path @onready). Son global_transform
#   est recalculé à chaque frame :
#     - position  → _model.to_global(BACK_LOCAL) : suit le dos même en glissade
#     - rotation  → _model.global_transform.basis.orthonormalized()
#                   × BASE_BASIS (rotation souhaitée EN ESPACE MONDE)
#   Cela émule parfaitement un enfant de animal-penguin2, sans dépendre
#   de l'espace local du GLB.
# =============================================================
class_name PetPenguin
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var slide_speed:    float = 7.0
@export var slide_duration: float = 1.4
@export var stop_duration:  float = 0.9

# --- Composant de tir (enfant direct de la racine) --------------
@onready var weapon:        WeaponBullet = $WeaponBullet

# --- Visuel de l'arme (enfant direct de la racine) --------------
@onready var _weapon_mount: Node3D       = $WeaponMount

# --- Constantes de placement de l'arme --------------------------
# Position du point "dos" dans l'espace LOCAL NON SCALÉ du modèle GLB
const BACK_LOCAL  := Vector3(0.0, 0.9, -0.55)
# Rotation souhaitée de l'arme en ESPACE MONDE quand le modèle est debout.
# X = 90°, Z = 180° → même réglage que le joueur trouve dans l'Inspector
# quand WeaponMount est à la racine (espace monde ≈ espace local à la racine).
const BASE_BASIS  := Basis(
	Vector3(-1.0,  0.0,  0.0),   # local X
	Vector3( 0.0,  0.0, -1.0),   # local Y
	Vector3( 0.0, -1.0,  0.0)    # local Z  →  local -Z = monde +Y = vers le haut
)

# --- État interne -----------------------------------------------
var _sliding:     bool    = false
var _phase_timer: float   = 0.0
var _slide_dir:   Vector3 = Vector3.ZERO


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	xp_reward = 12   # Pingouin — glisseur
	if weapon == null:
		push_error("PetPenguin: nœud WeaponBullet introuvable à $WeaponBullet")
		return

	_sliding     = false
	_phase_timer = stop_duration * randf_range(0.3, 1.0)

	# Position initiale avant le premier _physics_process
	_update_weapon_mount()


# =============================================================
# ANIMATION — surcharge pour incliner le modèle + suivre l'arme
# =============================================================

func _update_animation() -> void:
	# Inclinaison du modèle (toujours exécutée, même sans AnimationPlayer)
	if _model != null:
		var target_x := deg_to_rad(78.0) if _sliding else 0.0
		_model.rotation.x = lerpf(_model.rotation.x, target_x, 0.18)

	# Animation squelettique
	if _anim_player != null:
		if _sliding:
			if _anim_player.current_animation != "idle":
				_anim_player.play("idle")
		elif not _gesture_active:
			var speed := Vector2(velocity.x, velocity.z).length()
			var anim  := "idle" if speed < 0.25 else "walk"
			if _anim_player.current_animation != anim:
				_anim_player.play(anim)

	# Mise à jour du visuel de l'arme
	_update_weapon_mount()


func _update_weapon_mount() -> void:
	if _weapon_mount == null or _model == null:
		return

	# Position : le point "dos" dans l'espace monde, tenant compte
	# de la scale et de l'inclinaison courante du modèle.
	var world_pos := _model.to_global(BACK_LOCAL)

	# Rotation : rotation monde du modèle (sans scale) × rotation de base.
	# orthonormalized() retire la scale 0.55 de la basis du modèle,
	# ne conservant que la rotation pure (Y depuis _face_player + X tilt).
	var model_rot  := _model.global_transform.basis.orthonormalized()
	var world_basis := model_rot * BASE_BASIS

	_weapon_mount.global_transform = Transform3D(world_basis, world_pos)


# =============================================================
# MOUVEMENT — alternance glissade / pause
# =============================================================

func _update_movement(delta: float) -> void:
	_phase_timer -= delta

	if _sliding:
		velocity.x = _slide_dir.x * slide_speed
		velocity.z = _slide_dir.z * slide_speed

		if _phase_timer <= 0.0:
			_sliding     = false
			_phase_timer = stop_duration
			velocity.x   = 0.0
			velocity.z   = 0.0
			if weapon != null:
				weapon.deactivate()
	else:
		velocity.x = 0.0
		velocity.z = 0.0

		if _phase_timer <= 0.0:
			_start_slide()


func _start_slide() -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	if to_player.length_squared() < 0.01:
		_phase_timer = stop_duration
		return

	var dir      := to_player.normalized()
	var perp     := Vector3(-dir.z, 0.0, dir.x)
	_slide_dir    = (dir + perp * randf_range(-0.35, 0.35)).normalized()
	_sliding      = true
	_phase_timer  = slide_duration

	if weapon != null and player != null:
		weapon.activate(player)
