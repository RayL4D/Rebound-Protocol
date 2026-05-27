# =============================================================
# PetBunny.gd — Pet fonceur en zigzag
# Rebound Protocol
# =============================================================
# Comportement :
#   • Fonce vers le joueur en zigzaguant (trajectoire sinusoïdale)
#   • Mouvement imprévisible → difficile à toucher et à esquiver
#   • S'arrête à stop_distance et tire très rapidement (fire_rate élevé)
#   • Peu de HP → s'il arrive à portée, il est très dangereux
#
# Hiérarchie de scène attendue :
#   PetBunny (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-bunny.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-d.glb]
#   │   └── WeaponBullet (Node3D) ← script WeaponBullet.gd
# =============================================================
@tool
class_name PetBunny
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var stop_distance:  float = 3.5   # s'arrête et tire à cette distance
@export var strafe_freq:    float = 2.5   # fréquence d'oscillation (Hz)
@export var strafe_amp:     float = 1.0   # amplitude du zigzag (0 = ligne droite)

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet

# Compteur de temps pour l'oscillation
var _strafe_time: float = 0.0
# Phase de départ aléatoire pour que les lapins ne zigzaguent pas en phase
var _strafe_offset: float = 0.0


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	xp_reward = 8   # Lapin — agité
	# Phase initiale aléatoire → patterns différents entre lapins
	_strafe_offset = randf() * TAU

	if weapon == null:
		push_error("PetBunny: nœud WeaponBullet introuvable — vérifie $WeaponMount/WeaponBullet")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — fonce vers le joueur en zigzaguant via navmesh
# =============================================================

func _update_movement(delta: float) -> void:
	_strafe_time += delta

	var dist := global_position.distance_to(player.global_position)

	if dist < 0.1:
		return

	# À portée → s'arrêter et laisser l'arme tirer
	if dist <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Direction navmesh vers le joueur (évite les obstacles)
	var nav_dir := _get_move_direction()
	if nav_dir == Vector3.ZERO:
		return

	# Direction latérale perpendiculaire au chemin navmesh
	var strafe_dir := Vector3(-nav_dir.z, 0.0, nav_dir.x)

	# Oscillation sinusoïdale avec phase aléatoire
	var zigzag := sin(_strafe_time * strafe_freq * TAU + _strafe_offset) * strafe_amp

	var move_dir := (nav_dir + strafe_dir * zigzag)
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
