# =============================================================
# PetFox.gd — Pet sniper à longue portée
# Rebound Protocol
# =============================================================
# Comportement :
#   • Reste à grande distance et tire des balles puissantes lentes
#   • Recule VITE si le joueur s'approche trop
#   • Se repositionne latéralement lentement pour dégager la ligne de vue
#   • Peu de HP mais dangereux à ignorer → forcer le joueur à aller vers lui
#
# Hiérarchie de scène attendue :
#   PetFox (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-fox.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-c.glb]   ← fusil à lunette
#   │   └── WeaponBullet (Node3D)    ← script WeaponBullet.gd
# =============================================================
class_name PetFox
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 14.0  # distance idéale de snipe
@export var danger_distance:    float = 8.0   # distance à laquelle il fuit
@export var strafe_speed_mult:  float = 0.4   # dérive latérale lente pour dégager la vue

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	if weapon == null:
		push_error("PetFox: nœud WeaponBullet introuvable — vérifie $WeaponMount/WeaponBullet")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — maintien de distance + fuite rapide
# =============================================================

func _update_movement(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist < 0.1:
		return

	var to_player_n := to_player.normalized()

	# Composante latérale (dérive lente pour maintenir la visibilité)
	var strafe_dir := Vector3(-to_player_n.z, 0.0, to_player_n.x)

	var move_dir := Vector3.ZERO

	if dist < danger_distance:
		# Trop proche → fuite rapide en arrière
		move_dir = -to_player_n + strafe_dir * strafe_speed_mult
	elif dist < preferred_distance - 2.0:
		# Sous la distance idéale → reculer doucement
		move_dir = -to_player_n * 0.6 + strafe_dir * strafe_speed_mult
	elif dist > preferred_distance + 4.0:
		# Hors portée → avancer lentement pour rester dans shoot_range
		move_dir = to_player_n * 0.5
	else:
		# Dans la zone idéale → dérive latérale seulement (tient la ligne)
		move_dir = strafe_dir * strafe_speed_mult

	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
