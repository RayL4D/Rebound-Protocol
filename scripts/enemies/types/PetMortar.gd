# =============================================================
# PetMortar.gd — Pet orbital + tir de mortier
# Rebound Protocol
# =============================================================
# Comportement :
#   • Maintient une distance idéale avec le joueur
#   • Tourne autour de lui en strafant latéralement
#   • Tire des mortiers sur la POSITION ACTUELLE du joueur →
#     le joueur doit bouger en permanence pour esquiver
#
# Hiérarchie de scène attendue :
#   PetMortar (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle Cube Pets importé]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle Blaster Kit (plus gros / différent)]
#   │   └── WeaponMortar (Node3D) ← script WeaponMortar.gd
#   └── (pas de ShootTimer — géré par WeaponComponent)
# =============================================================
class_name PetMortar
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 8.0  # distance idéale avec le joueur
@export var orbit_speed_mult: float   = 0.8  # vitesse de rotation orbitale (1 = move_speed)

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponMortar = $WeaponMount/WeaponMortar

# Sens de rotation orbital (1 ou -1) — aléatoire au spawn
var _orbit_sign: float = 1.0


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	# Sens de rotation aléatoire pour que les PetMortar ne tournent pas tous pareil
	_orbit_sign = 1.0 if randf() > 0.5 else -1.0

	if weapon == null:
		push_error("PetMortar: nœud WeaponMortar introuvable — vérifie le chemin $WeaponMount/WeaponMortar")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — surcharge de Enemy._update_movement
# =============================================================

func _update_movement(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist < 0.1:
		return

	var to_player_n := to_player.normalized()

	# Composante radiale : s'approcher ou s'éloigner selon la distance
	var radial := Vector3.ZERO
	var margin := 1.5  # tolérance avant de corriger la distance
	if dist < preferred_distance - margin:
		radial = -to_player_n  # trop proche → reculer
	elif dist > preferred_distance + margin:
		radial = to_player_n   # trop loin → avancer

	# Composante orbitale : toujours strafer latéralement autour du joueur
	# Perpendiculaire à to_player dans le plan horizontal
	var strafe_dir := Vector3(-to_player_n.z, 0.0, to_player_n.x) * _orbit_sign

	# Combiner et normaliser pour éviter que les diagonales aillent trop vite
	var move_dir := (radial + strafe_dir)
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
