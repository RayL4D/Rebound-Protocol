# =============================================================
# EnemyPlaceholder.gd — Ennemi de test pour valider les balles
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
#
# Cet ennemi fait deux choses :
#   1. Se déplacer lentement vers le joueur
#   2. Tirer une balle vers le joueur toutes les X secondes
# =============================================================
class_name EnemyPlaceholder
extends CharacterBody3D

# --- Exports -----------------------------------------------------
@export var max_hp: int          = 30
@export var move_speed: float    = 2.0
@export var shoot_interval: float = 2.0  # secondes entre chaque tir
@export var stop_distance: float  = 3.0   # distance à laquelle il s'arrête
@export var shoot_range: float    = 8.0   # portée max de tir

# --- preload : charge la scène UNE SEULE FOIS au démarrage -------
# preload() est résolu à la compilation — Godot vérifie que le
# fichier existe. Utilise load() si le chemin est dynamique.
@export var bullet_scene: PackedScene = preload("res://scenes/enemies/bullet_enemy.tscn")

# --- Références nœuds --------------------------------------------
@onready var shoot_timer: Timer = $ShootTimer

# --- Variables d'état --------------------------------------------
var current_hp: int
var player: Player = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Signaux -----------------------------------------------------
signal enemy_died


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	current_hp = max_hp

	# Ajouter cet ennemi au groupe "enemies".
	# Tous les types d'ennemis (Grunt, Sniper, etc.) feront pareil.
	# La balle renvoyée utilise ce groupe pour savoir qui attaquer.
	add_to_group("enemies")

	# get_first_node_in_group cherche dans tout l'arbre de scène
	# le premier nœud qui appartient au groupe "player"
	player = get_tree().get_first_node_in_group("player")

	# Configurer et démarrer le timer de tir
	shoot_timer.wait_time = shoot_interval
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	shoot_timer.start()


func _physics_process(delta: float) -> void:
	if player == null:
		return

	_apply_gravity(delta)
	_move_toward_player()
	move_and_slide()


# =============================================================
# MOUVEMENT
# =============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func _move_toward_player() -> void:
	# Calculer la direction horizontale vers le joueur
	var dir: Vector3 = player.global_position - global_position
	dir.y = 0.0  # ignorer la différence de hauteur

	# Si on est suffisamment proche, s'arrêter
	if dir.length() <= stop_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed


# =============================================================
# TIR
# =============================================================

func _shoot() -> void:
	if player == null:
		return

	# Ne tirer que si le joueur est à portée
	# distance_to() retourne la distance euclidienne entre deux Vector3
	var dist: float = global_position.distance_to(player.global_position)
	if dist > shoot_range:
		return

	# instantiate() crée une copie de la scène en mémoire.
	# À ce stade la balle existe mais n'est PAS encore dans l'arbre
	# de scène — elle n'a donc pas de position ni de _ready() lancé.
	var bullet: Bullet = bullet_scene.instantiate()

	# On ajoute la balle à la scène courante (même niveau que l'ennemi)
	# AVANT d'appeler init(), car init() utilise global_position
	# qui n'est disponible qu'une fois le nœud dans l'arbre.
	get_tree().current_scene.add_child(bullet)

	# Calculer la direction vers le joueur au moment du tir
	var shoot_dir: Vector3 = player.global_position - global_position
	shoot_dir.y = 0.0

	# Initialiser la balle : position de spawn + direction
	bullet.init(global_position, shoot_dir)


func _on_shoot_timer_timeout() -> void:
	_shoot()


# =============================================================
# SANTÉ
# =============================================================

func take_damage(amount: int, silent_hurt: bool = false) -> void:
	current_hp = max(0, current_hp - amount)
	if current_hp == 0:
		_die()


func _die() -> void:
	enemy_died.emit()
	queue_free()
