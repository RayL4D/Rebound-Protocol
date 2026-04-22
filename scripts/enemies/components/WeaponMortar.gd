# =============================================================
# WeaponMortar.gd — Arme à impact différé (mortier)
# Rebound Protocol
# =============================================================
# Au moment du tir, capture la position actuelle du joueur et
# crée un MortarWarning à cet endroit. Le joueur voit un disque
# rouge s'élargir au sol — s'il ne bouge pas, il prend des dégâts.
#
# Mécanique : force le joueur à rester en mouvement constant.
#
# Hérite de WeaponComponent.
# =============================================================
class_name WeaponMortar
extends WeaponComponent

# --- Exports ----------------------------------------------------
@export var impact_delay: float  = 1.5  # secondes entre le tir et l'impact
@export var impact_radius: float = 1.8  # rayon de la zone d'explosion


# =============================================================
# TIR
# =============================================================

func _fire() -> void:
	if _target == null:
		return

	# Capturer la position XZ du joueur AU MOMENT du tir
	# → s'il s'est déplacé avant l'impact, il esquive
	#
	# La capsule du joueur (hauteur 1.8) est centrée sur son origine CharacterBody3D,
	# donc ses pieds sont à global_position.y - 0.9.
	# On ajoute 0.05 d'offset pour éviter le z-fighting avec le sol.
	var target_pos := _target.global_position
	target_pos.y = target_pos.y - 0.9 + 0.05  # pieds du joueur + léger offset sol

	# Shell visuel : sphère lumineuse en arc parabolique depuis l'arme jusqu'au sol
	var shell := MortarShell.new()
	get_tree().current_scene.add_child(shell)
	shell.init(global_position, target_pos, impact_delay)

	# Zone d'avertissement au sol (gère les dégâts)
	var warning := MortarWarning.new()
	get_tree().current_scene.add_child(warning)
	warning.init(target_pos, impact_delay, impact_radius, damage)
