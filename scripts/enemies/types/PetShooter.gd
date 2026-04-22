# =============================================================
# PetShooter.gd — Pet fonçeur + tir droit
# Rebound Protocol
# =============================================================
# Comportement :
#   • Fonce vers le joueur en ligne droite
#   • S'arrête à stop_distance et tire des balles standards
#   • Pattern simple, prévisible → ennemi de base
#
# Hiérarchie de scène attendue :
#   PetShooter (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle Cube Pets importé]
#   ├── WeaponMount (Node3D)          ← point d'attache de l'arme
#   │   ├── [Modèle Blaster Kit]      ← visuel de l'arme
#   │   └── WeaponBullet (Node3D)     ← script WeaponBullet.gd
#   └── ShootTimer n'est PLUS nécessaire (géré par WeaponComponent)
# =============================================================
class_name PetShooter
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var stop_distance: float = 4.0  # distance à laquelle il s'arrête et tire

# --- Référence au composant d'arme ------------------------------
# Chemin à ajuster selon la hiérarchie réelle de ta scène
@onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet


# =============================================================
# HOOK D'INITIALISATION (appelé depuis Enemy._ready)
# =============================================================

func _on_ready() -> void:
	if weapon == null:
		push_error("PetShooter: nœud WeaponBullet introuvable — vérifie le chemin $WeaponMount/WeaponBullet")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — surcharge de Enemy._update_movement
# =============================================================

func _update_movement(_delta: float) -> void:
	var dir := player.global_position - global_position
	dir.y = 0.0
	var dist := dir.length()

	if dist <= stop_distance:
		# À portée → s'arrêter, l'arme gère le tir automatiquement
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Foncer vers le joueur
	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
