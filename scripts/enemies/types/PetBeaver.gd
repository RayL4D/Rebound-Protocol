# =============================================================
# PetBeaver.gd — Pet poseur de mines (castor)
# Rebound Protocol
# =============================================================
# Comportement :
#   • Recule devant le joueur en maintenant une grande distance
#   • Dépose des mines TrapMine sur son passage
#   • Le champ de mines force le joueur à faire attention où il court
#   • Pas de tir direct — tout sa dangerosité vient des mines
#   • Priorité basse → distraction qui peut être fatale si ignoré
#
# Hiérarchie de scène attendue :
#   PetBeaver (CharacterBody3D) ← ce script
#   ├── CollisionShape3D
#   ├── [Modèle animal-beaver.glb]
#   └── WeaponTrap (Node3D) ← script WeaponTrap.gd (pas de visuel d'arme)
# =============================================================
class_name PetBeaver
extends Enemy

# --- Exports propres à ce type ----------------------------------
@export var preferred_distance: float = 12.0  # distance à laquelle il se sent à l'aise
@export var flee_speed_mult:    float = 1.3   # vitesse de fuite (× move_speed)

# --- Référence au composant d'arme ------------------------------
@onready var weapon: WeaponTrap = $WeaponTrap


# =============================================================
# HOOK D'INITIALISATION
# =============================================================

func _on_ready() -> void:
	xp_reward = 12   # Castor — mines
	if weapon == null:
		push_error("PetBeaver: nœud WeaponTrap introuvable — vérifie $WeaponTrap")
		return
	if player == null:
		return
	weapon.activate(player)


# =============================================================
# MOUVEMENT — fuit devant le joueur en reculant et strafant
# =============================================================

func _update_movement(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y   = 0.0
	var dist      := to_player.length()

	if dist < 0.1:
		return

	var to_player_n := to_player.normalized()
	var move_dir    := Vector3.ZERO

	if dist < preferred_distance - 1.0:
		# Trop proche → fuite rapide en sens opposé via navmesh
		# On inverse la direction navmesh pour fuir en contournant les obstacles
		var nav_dir := _get_move_direction()
		var lateral := Vector3(-to_player_n.z, 0.0, to_player_n.x)
		move_dir     = -nav_dir + lateral * 0.4
		if move_dir.length_squared() > 0.01:
			move_dir = move_dir.normalized()

		velocity.x = move_dir.x * move_speed * flee_speed_mult
		velocity.z = move_dir.z * move_speed * flee_speed_mult
	elif dist > preferred_distance + 3.0:
		# Trop loin → se repositionne via navmesh
		var nav_dir := _get_move_direction()
		if nav_dir == Vector3.ZERO:
			return
		velocity.x = nav_dir.x * move_speed * 0.4
		velocity.z = nav_dir.z * move_speed * 0.4
	else:
		# Zone confortable → dérive latérale lente (continue de poser des mines)
		var lateral := Vector3(-to_player_n.z, 0.0, to_player_n.x)
		velocity.x   = lateral.x * move_speed * 0.5
		velocity.z   = lateral.z * move_speed * 0.5
