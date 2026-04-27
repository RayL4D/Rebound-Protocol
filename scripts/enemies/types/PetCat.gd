# =============================================================
# PetCat.gd — Pet rafale orbitale
# Rebound Protocol
# =============================================================
# Comportement :
#   • Tourne en orbite autour du joueur (comme PetMortar)
#   • Tire des rafales de 3 balles rapides, puis recharge
#   • Distance orbitale plus serrée → pression constante
#   • Dangereux en groupe : les rafales se chevauchent
#
# Hiérarchie de scène attendue :
#   PetCat (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-cat.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-b.glb]
#   │   └── WeaponBurst (Node3D) ← script WeaponBurst.gd
#   └── (pas de ShootTimer — géré par WeaponComponent)
# =============================================================
class_name PetCat
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 6.0   # orbite plus serrée que PetMortar
@export var orbit_speed_mult:   float = 1.2   # plus agile que le singe

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponBurst = $WeaponMount/WeaponBurst

# Sens de rotation orbital (1 ou -1) — aléatoire au spawn
var _orbit_sign: float = 1.0


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	_orbit_sign = 1.0 if randf() > 0.5 else -1.0

	if weapon == null:
		push_error("PetCat: nœud WeaponBurst introuvable — vérifie $WeaponMount/WeaponBurst")
		return
	if player == null:
		return
	weapon.activate(player)

	# Animation gesture-negative (grognement) à chaque début de rafale
	weapon.fired.connect(_on_burst_fired)
	if _anim_player != null:
		_anim_player.animation_finished.connect(_on_animation_finished)


func _on_burst_fired() -> void:
	# Jouer gesture-negative uniquement au premier tir du burst
	# (WeaponBurst émet fired à chaque balle, on filtre avec _gesture_active)
	if _anim_player == null or _gesture_active:
		return
	_gesture_active = true
	_anim_player.play("gesture-negative")


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"gesture-negative":
		_gesture_active = false


# =============================================================
# MOUVEMENT — orbite serrée autour du joueur
# =============================================================

func _update_movement(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist < 0.1:
		return

	var to_player_n := to_player.normalized()

	# Composante radiale : ajustement de la distance préférée
	var radial := Vector3.ZERO
	var margin := 1.2
	if dist < preferred_distance - margin:
		radial = -to_player_n  # trop proche → reculer
	elif dist > preferred_distance + margin:
		radial = to_player_n   # trop loin → avancer

	# Composante orbitale (strafe latéral)
	var strafe_dir := Vector3(-to_player_n.z, 0.0, to_player_n.x) * _orbit_sign

	var move_dir := (radial + strafe_dir * orbit_speed_mult)
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
