# =============================================================
# PetPanda.gd — Pet corps-à-corps (panda)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Fonce vers le joueur sans s'arrêter
#   • Inflige des dégâts de mêlée au contact via une Area3D
#   • Joue gesture-positive à chaque coup porté
#   • Pas de tir à distance — oblige le joueur à fuir ou éliminer
#   • Robuste (55 HP) et rapide → dangereux si ignoré
#
# Design : oblige le joueur à le prioriser.
#   Il ne peut pas être "parié" → source de pression permanente.
#
# Hiérarchie de scène attendue :
#   PetPanda (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   └── [Modèle animal-panda.glb]
#   (Pas de WeaponMount — dégâts via Area3D créée en code)
# =============================================================
@tool
class_name PetPanda
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var melee_damage:   int   = 18    # dégâts par coup
@export var melee_interval: float = 1.2   # secondes entre deux coups
@export var melee_radius:   float = 1.1   # rayon de la zone de mêlée

# --- État interne -----------------------------------------------
var _melee_area:     Area3D = null
var _melee_cooldown: float  = 0.0


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

# --- Audio ------------------------------------------------------
const _SFX_SWIPE: AudioStream = preload("res://audio/sfx/enemies/melee_swipe.wav")


func _on_ready() -> void:
	xp_reward = 10   # Panda — corps-à-corps
	_create_melee_area()
	if _anim_player != null:
		_anim_player.animation_finished.connect(_on_animation_finished)


func _create_melee_area() -> void:
	_melee_area = Area3D.new()

	var col    := CollisionShape3D.new()
	var sph    := SphereShape3D.new()
	sph.radius  = melee_radius
	col.shape   = sph
	_melee_area.add_child(col)

	# Layer 0 (l'area n'a pas de présence physique), détecte layer 1 (joueur)
	_melee_area.collision_layer = 0
	_melee_area.collision_mask  = 1
	_melee_area.monitoring      = true
	_melee_area.position.y      = 0.6   # centré sur le corps

	add_child(_melee_area)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"gesture-positive":
		_gesture_active = false


# =============================================================
# OVERRIDE _physics_process — vérification mêlée chaque frame
# =============================================================

func _physics_process(delta: float) -> void:
	if _melee_cooldown > 0.0:
		_melee_cooldown -= delta
	_check_melee()
	super._physics_process(delta)


func _check_melee() -> void:
	if _melee_cooldown > 0.0 or _melee_area == null:
		return

	for body in _melee_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			body.take_damage(melee_damage)
			_melee_cooldown = melee_interval

			if _sfx_player and _SFX_SWIPE:
				_sfx_player.stream      = _SFX_SWIPE
				_sfx_player.volume_db   = -8.0 + randf_range(-1.0, 1.0)
				_sfx_player.pitch_scale = randf_range(0.93, 1.07)
				_sfx_player.play()

			# Animation de frappe
			if _anim_player != null:
				_gesture_active = true
				_anim_player.play("gesture-positive")
			break


# =============================================================
# MOUVEMENT — fonce vers le joueur sans jamais s'arrêter
# =============================================================

func _update_movement(_delta: float) -> void:
	var dir := _get_move_direction()
	if dir == Vector3.ZERO:
		return
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
