# =============================================================
# Bullet.gd — Projectile ennemi
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Bullet
extends Area3D

# --- Exports (modifiables dans l'inspector Godot) ----------------
@export var speed: float  = 12.0
@export var damage: int   = 10

# --- Variables internes ------------------------------------------
# Direction normalisée transmise par l'ennemi au moment du tir
var direction: Vector3 = Vector3.ZERO


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Connecter le signal du notifier : auto-détruit la balle
	# dès qu'elle sort du champ de la caméra
	$VisibleOnScreenNotifier3D.screen_exited.connect(_on_screen_exited)

	# Connecter la détection de collision avec un corps physique
	# (CharacterBody3D du joueur par exemple)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# Déplacement en ligne droite chaque frame
	# global_position : position dans l'espace monde (pas local)
	# direction * speed * delta : on multiplie par delta pour que
	# la vitesse soit indépendante du framerate
	global_position += direction * speed * delta


# =============================================================
# INITIALISATION — appelée par l'ennemi qui instancie la balle
# =============================================================

# Cette fonction remplace le constructeur : on ne peut pas passer
# d'arguments à _ready() en Godot, donc on initialise la balle
# juste après son spawn via cette méthode.
func init(spawn_position: Vector3, target_direction: Vector3) -> void:
	global_position = spawn_position
	direction       = target_direction.normalized()


# =============================================================
# COLLISIONS
# =============================================================

func _on_body_entered(body: Node3D) -> void:
	# Si la balle touche le joueur → infliger des dégâts
	# "is Player" utilise la class_name déclarée dans Player.gd
	if body is Player:
		body.take_damage(damage)
		queue_free()  # Détruire la balle après impact


func _on_screen_exited() -> void:
	# La balle a raté sa cible et est sortie de l'écran
	queue_free()
