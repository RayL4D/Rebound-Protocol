# =============================================================
# PetMonkey.gd — Pet orbital + tir de mortier (singe)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Maintient une distance idéale avec le joueur
#   • Tourne autour de lui en strafant latéralement
#   • Tire des mortiers sur la POSITION ACTUELLE du joueur →
#     le joueur doit bouger en permanence pour esquiver
#
# Hiérarchie de scène attendue :
#   PetMonkey (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-monkey.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-h.glb]
#   │   └── WeaponMortar (Node3D) ← script WeaponMortar.gd
# =============================================================
class_name PetMonkey
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 8.0  # distance idéale avec le joueur
@export var orbit_speed_mult:   float = 0.8  # vitesse de rotation orbitale (1 = move_speed)

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponMortar = $WeaponMount/WeaponMortar

# Sens de rotation orbital (1 ou -1) — aléatoire au spawn
var _orbit_sign: float = 1.0


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	xp_reward = 12   # Singe — mortier
	_orbit_sign = 1.0 if randf() > 0.5 else -1.0

	if weapon == null:
		push_error("PetMonkey: nœud WeaponMortar introuvable — vérifie $WeaponMount/WeaponMortar")
		return
	if player == null:
		return
	weapon.activate(player)

	# Jouer gesture-positive à chaque tir de mortier
	weapon.fired.connect(_on_mortar_fired)

	# Quand gesture-positive se termine, rendre la main à idle/walk/run
	if _anim_player != null:
		_anim_player.animation_finished.connect(_on_animation_finished)


func _on_mortar_fired() -> void:
	if _anim_player == null:
		return
	_gesture_active = true
	_anim_player.play("gesture-positive")


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"gesture-positive":
		_gesture_active = false


# =============================================================
# MOUVEMENT — orbite autour du joueur à distance idéale
# =============================================================

func _update_movement(_delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)

	if dist < 0.1:
		return

	var to_player_n := (player.global_position - global_position)
	to_player_n.y    = 0.0
	to_player_n      = to_player_n.normalized()

	# Composante radiale via navmesh
	var radial := Vector3.ZERO
	var margin := 1.5
	if dist < preferred_distance - margin:
		# Trop proche → reculer
		radial = -to_player_n
	elif dist > preferred_distance + margin:
		# Trop loin → avancer via navmesh
		var nav_dir := _get_move_direction()
		if nav_dir != Vector3.ZERO:
			radial = nav_dir

	# Composante orbitale : strafe latéral constant
	var strafe_dir := Vector3(-to_player_n.z, 0.0, to_player_n.x) * _orbit_sign

	var move_dir := (radial + strafe_dir)
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
