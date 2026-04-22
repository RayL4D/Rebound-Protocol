# =============================================================
# WeaponBullet.gd — Arme à tir droit
# Rebound Protocol
# =============================================================
# Tire une balle standard (bullet_enemy.tscn) en direction du joueur.
# Hérite de WeaponComponent — le cooldown et la portée sont gérés
# par la classe parente.
#
# Dans l'éditeur : attacher ce script à un nœud Node3D enfant de
# l'ennemi, puis assigner le modèle d'arme (Blaster Kit) comme
# enfant visuel du même nœud.
# =============================================================
class_name WeaponBullet
extends WeaponComponent

# --- Exports ----------------------------------------------------
@export var bullet_speed: float   = 10.0
@export var bullet_scene: PackedScene = preload("res://scenes/enemies/bullet_enemy.tscn")


# =============================================================
# TIR
# =============================================================

func _fire() -> void:
	if _target == null or bullet_scene == null:
		return

	var bullet: Bullet = bullet_scene.instantiate()

	# Ajouter à la scène AVANT init() — global_position n'est dispo
	# qu'une fois le nœud dans l'arbre (même principe que EnemyPlaceholder)
	get_tree().current_scene.add_child(bullet)

	# Surcharger les stats de la balle avec les valeurs de cette arme
	bullet.speed  = bullet_speed
	bullet.damage = damage

	# Direction horizontale vers la cible
	var dir := _target.global_position - global_position
	dir.y = 0.0

	bullet.init(global_position, dir)
