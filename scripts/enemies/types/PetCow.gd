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
@tool
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
	if not use_detection:
		weapon.activate(player)


func _on_player_detected() -> void:
	if weapon != null and player != null:
		weapon.activate(player)


# =============================================================
# MOUVEMENT — fonce vers le joueur, s'arrête à courte portée
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
