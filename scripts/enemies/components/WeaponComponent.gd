# =============================================================
# WeaponComponent.gd — Composant d'arme de base
# Rebound Protocol
# =============================================================
# Attacher ce nœud (ou une de ses sous-classes) comme enfant
# d'un ennemi. Il gère le cooldown de tir et la portée.
#
# Sous-classes disponibles :
#   WeaponBullet  — tir droit vers le joueur
#   WeaponMortar  — tir différé sur la dernière position du joueur
#
# Usage dans la sous-classe de l'ennemi :
#   @onready var weapon: WeaponBullet = $WeaponMount/WeaponBullet
#   func _on_ready(): weapon.activate(player)
# =============================================================
class_name WeaponComponent
extends Node3D

# --- Exports ----------------------------------------------------
@export var fire_rate: float   = 1.0   # tirs par seconde
@export var shoot_range: float = 10.0  # portée en unités
@export var damage: int        = 10    # dégâts par projectile

# --- État interne -----------------------------------------------
var _target: Node3D  = null
var _cooldown: float = 0.0
var _active: bool    = false


# =============================================================
# LIFECYCLE
# =============================================================

func _process(delta: float) -> void:
	if not _active or _target == null:
		return

	if _cooldown > 0.0:
		_cooldown -= delta
		return

	# Vérifier la portée avant de tirer
	if global_position.distance_to(_target.global_position) <= shoot_range:
		_fire()
		_cooldown = 1.0 / fire_rate


# =============================================================
# API PUBLIQUE
# =============================================================

# Appeler depuis _on_ready() de l'ennemi une fois le joueur trouvé.
# Le délai aléatoire évite que tous les ennemis d'une vague tirent
# exactement en même temps au spawn.
func activate(target: Node3D) -> void:
	_target   = target
	_active   = true
	_cooldown = randf_range(0.3, 1.0 / fire_rate)  # offset initial aléatoire


func deactivate() -> void:
	_active = false


# =============================================================
# LOGIQUE DE TIR — à surcharger dans chaque sous-classe
# =============================================================

func _fire() -> void:
	pass
