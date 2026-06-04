# =============================================================
# PetFox.gd — Pet flanqueur (renard)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Se déplace en permanence en zigzag rapide autour du joueur
#   • Ne s'arrête JAMAIS — tire en plein mouvement
#   • Les balles arrivent d'angles différents à chaque tir
#   • Oblige le joueur à adapter continuellement son bouclier
#
# Design parry : les balles viennent de directions changeantes →
#   le joueur doit lire la position du renard pour orienter le parry,
#   pas juste tenir le bouclier face à lui.
#
# Hiérarchie de scène attendue :
#   PetFox (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-fox.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-f.glb]
#   │   └── WeaponBullet (Node3D) ← script WeaponBullet.gd
# =============================================================
@tool
class_name PetFox
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 7.0   # distance orbitale idéale
@export var zigzag_freq:        float = 0.8   # fréquence d'oscillation (Hz)
@export var zigzag_amp:         float = 1.6   # amplitude du zigzag

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet

# Sens orbital de base (1 ou -1) — aléatoire au spawn
var _orbit_sign:  float = 1.0
# Compteur de temps pour l'oscillation
var _zigzag_time: float = 0.0


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	xp_reward = 10   # Renard — flanqueur
	_orbit_sign  = 1.0 if randf() > 0.5 else -1.0
	_zigzag_time = randf() * TAU  # phase aléatoire → renards pas synchronisés

	if weapon == null:
		push_error("PetFox: nœud WeaponBullet introuvable — vérifie $WeaponMount/WeaponBullet")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — zigzag orbital permanent via navmesh
# =============================================================

func _update_movement(delta: float) -> void:
	_zigzag_time += delta

	var dist := global_position.distance_to(player.global_position)

	if dist < 0.1:
		return

	var to_player_n := (player.global_position - global_position)
	to_player_n.y    = 0.0
	to_player_n      = to_player_n.normalized()

	# Composante radiale : maintien de la distance préférée via navmesh
	var radial := Vector3.ZERO
	var margin := 2.0
	if dist < preferred_distance - margin:
		# Trop proche → s'éloigner (direction opposée)
		radial = -to_player_n
	elif dist > preferred_distance + margin:
		# Trop loin → revenir via navmesh
		var nav_dir := _get_move_direction()
		if nav_dir != Vector3.ZERO:
			radial = nav_dir * 0.6

	# Composante orbitale avec zigzag sinusoïdal
	var strafe_dir    := Vector3(-to_player_n.z, 0.0, to_player_n.x) * _orbit_sign
	var zigzag_factor := sin(_zigzag_time * zigzag_freq * TAU) * zigzag_amp

	var move_dir := radial + strafe_dir * zigzag_factor
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
