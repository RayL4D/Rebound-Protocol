# =============================================================
# PetCow.gd — Pet shotgun de proximité (vache)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Fonce vers le joueur et s'arrête à courte portée
#   • Tire un éventail de 4 balles simultanées (shotgun)
#   • Dangereux si le joueur laisse la vache s'approcher
#   • Neutralisée à distance — sa menace est nulle à >7 unités
#
# Design parry : 4 balles = 4 parries simultanés impossibles →
#   le joueur doit rester loin ou en mouvement pour n'en toucher qu'une.
#
# Hiérarchie de scène attendue :
#   PetCow (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-cow.glb]
#   ├── WeaponMount (Node3D)
#   │   ├── [Modèle blaster-e.glb]
#   │   └── WeaponShotgun (Node3D) ← script WeaponShotgun.gd
# =============================================================
class_name PetCow
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var stop_distance: float = 5.0  # distance à laquelle elle s'arrête et tire

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponShotgun = $WeaponMount/WeaponShotgun


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	xp_reward = 12   # Vache — shotgun
	if weapon == null:
		push_error("PetCow: nœud WeaponShotgun introuvable — vérifie $WeaponMount/WeaponShotgun")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — fonce vers le joueur, s'arrête à courte portée
# =============================================================

func _update_movement(_delta: float) -> void:
	var dir  := player.global_position - global_position
	dir.y     = 0.0
	var dist  := dir.length()

	if dist <= stop_distance:
		# À portée → stopper, WeaponShotgun gère le tir
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Foncer vers le joueur
	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
