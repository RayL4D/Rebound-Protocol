# =============================================================
# PetKoala.gd — Pet sniper (koala)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Se déplace très lentement, maintient une grande distance
#   • S'immobilise COMPLÈTEMENT pendant la charge (2 secondes)
#   • Pendant la charge : faisceau laser rouge visible → avertissement
#   • Tire ensuite une unique balle très rapide et très puissante
#
# Design parry : le laser est un gros signal visuel →
#   le joueur PEUT éviter ou préparer le parry, mais la balle est
#   rapide et puissante. Pendant la charge, le koala est parfaitement
#   immobile → une balle renvoyée le tue en un seul coup.
#
# Hiérarchie de scène attendue :
#   PetKoala (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-koala.glb]
#   └── WeaponMount (Node3D)
#       ├── [Modèle blaster-r.glb]
#       ├── [Modèle scope-large-a.glb]
#       └── WeaponSniper (Node3D) ← charge + laser + tir unique
# =============================================================
class_name PetKoala
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 14.0   # distance de combat idéale

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponSniper = $WeaponMount/WeaponSniper


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	if weapon == null:
		push_error("PetKoala: nœud WeaponSniper introuvable — vérifie $WeaponMount/WeaponSniper")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — dérive lente, s'immobilise pendant la charge
# =============================================================

func _update_movement(_delta: float) -> void:
	# Immobile pendant la phase de charge du sniper
	if weapon != null and weapon.is_charging():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist < 0.1:
		return

	var to_player_n := to_player.normalized()

	if dist < preferred_distance - 2.0:
		# Trop proche → recule
		velocity.x = -to_player_n.x * move_speed
		velocity.z = -to_player_n.z * move_speed
	elif dist > preferred_distance + 3.0:
		# Trop loin → s'approche doucement
		velocity.x = to_player_n.x * move_speed
		velocity.z = to_player_n.z * move_speed
	else:
		# Zone confortable → légère dérive latérale pour ne pas rester figé
		var lateral := Vector3(-to_player_n.z, 0.0, to_player_n.x)
		velocity.x   = lateral.x * move_speed * 0.25
		velocity.z   = lateral.z * move_speed * 0.25
