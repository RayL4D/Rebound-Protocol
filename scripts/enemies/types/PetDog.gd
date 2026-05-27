# =============================================================
# PetDog.gd — Pet fonçeur + tir droit (chien)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Fonce vers le joueur en ligne droite
#   • S'arrête à stop_distance et tire des balles standards
#   • Pattern simple, prévisible → ennemi de base
#
# Hiérarchie de scène attendue :
#   PetDog (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-dog.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-a.glb]
#   │   └── WeaponBullet (Node3D) ← script WeaponBullet.gd
# =============================================================
@tool
class_name PetDog
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var stop_distance: float = 4.0  # distance à laquelle il s'arrête et tire

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet


# =============================================================
# HOOK D'INITIALISATION (appelé depuis Enemy._ready)
# =============================================================

func _on_ready() -> void:
	#xp_reward = 8   # Chien — ennemi de base
	if weapon == null:
		push_error("PetDog: nœud WeaponBullet introuvable — vérifie $WeaponMount/WeaponBullet")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — fonce vers le joueur, s'arrête à portée
# =============================================================

func _update_movement(_delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir := _get_move_direction()
	if dir == Vector3.ZERO:
		return
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
