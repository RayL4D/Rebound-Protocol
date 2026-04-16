# =============================================================
# Shield.gd — Rotation du bouclier + logique de parade
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Shield
extends Node3D

# --- Exports -----------------------------------------------------
@export var orbit_radius: float = 0.8

# --- Références nœuds --------------------------------------------
# @onready : la variable est remplie au moment où _ready() s'exécute.
# Le $ est un raccourci pour get_node(). $ParryTimer = get_node("ParryTimer")
@onready var parry_timer: ParryTimer = $ParryTimer
@onready var hit_area: Area3D        = $HitArea

# --- Scène de la balle renvoyée ----------------------------------
# preload charge le fichier une seule fois au démarrage
var _bullet_reflected_scene: PackedScene = preload("res://scenes/enemies/bullet_reflected.tscn")

# --- Variables d'état --------------------------------------------
var player: CharacterBody3D
var camera: Camera3D

# Direction actuelle du bouclier (joueur → souris), mémorisée
# pour savoir dans quel sens renvoyer la balle
var _shield_direction: Vector3 = Vector3.FORWARD

# Balle actuellement en contact avec le bouclier
# On la garde en mémoire pour pouvoir la détruire après la parade
var _pending_bullet: Bullet = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	player = get_parent()
	camera = get_viewport().get_camera_3d()

	# Connecter le signal area_entered de la HitArea.
	# area_entered est émis quand une Area3D entre dans une autre Area3D.
	# C'est comme body_entered du tuto, mais pour les Area3D.
	hit_area.area_entered.connect(_on_bullet_entered)

	# Connecter le signal parry_resolved de ParryTimer.
	# Quand ParryTimer a calculé l'état, il nous appelle via ce signal.
	parry_timer.parry_resolved.connect(_on_parry_resolved)


func _process(_delta: float) -> void:
	_orbit_toward_mouse()


# =============================================================
# ROTATION ORBITALE (inchangée)
# =============================================================

func _orbit_toward_mouse() -> void:
	if camera == null:
		return

	var mouse_screen_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_screen_pos)
	var ray_dir: Vector3    = camera.project_ray_normal(mouse_screen_pos)

	var plane_y: float = player.global_position.y

	if abs(ray_dir.y) < 0.001:
		return

	var t: float             = (plane_y - ray_origin.y) / ray_dir.y
	var mouse_world_pos: Vector3 = ray_origin + ray_dir * t

	var dir_to_mouse: Vector3 = mouse_world_pos - player.global_position
	dir_to_mouse.y = 0.0

	if dir_to_mouse.length() < 0.01:
		return

	dir_to_mouse = dir_to_mouse.normalized()

	# On mémorise la direction pour l'utiliser lors du renvoi de balle
	_shield_direction = dir_to_mouse

	global_position = player.global_position + dir_to_mouse * orbit_radius
	global_position.y = player.global_position.y

	var angle: float = atan2(dir_to_mouse.x, dir_to_mouse.z)
	global_rotation.y = angle


# =============================================================
# DÉTECTION BALLE
# =============================================================

# Appelée automatiquement quand une Area3D entre dans la HitArea
func _on_bullet_entered(area: Area3D) -> void:
	# On vérifie que c'est bien une balle ennemie avec "is Bullet"
	# (utilise la class_name déclarée dans Bullet.gd)
	# Ça évite de réagir si une autre Area3D frôle le bouclier plus tard
	if not area is Bullet:
		return

	# Mémoriser la balle : on en aura besoin dans _on_parry_resolved
	_pending_bullet = area

	# Prévenir le ParryTimer qu'une balle vient d'arriver
	# C'est lui qui calcule si c'est ABSORB / STANDARD / CRITICAL
	# et qui émet ensuite le signal parry_resolved
	parry_timer.on_bullet_impact()


# =============================================================
# RÉSOLUTION DE LA PARADE
# =============================================================

# Appelée automatiquement par le signal parry_resolved de ParryTimer
func _on_parry_resolved(state: ParryTimer.ParryState) -> void:
	if _pending_bullet == null:
		return

	# match = switch/case en GDScript
	# On agit différemment selon l'état retourné par ParryTimer
	match state:

		ParryTimer.ParryState.ABSORB:
			# Le bouclier absorbe la balle complètement : aucun dégât pour le joueur
			_pending_bullet.queue_free()

		ParryTimer.ParryState.STANDARD:
			# Renvoi standard : balle orange
			_spawn_reflected_bullet(10, false)
			_pending_bullet.queue_free()

		ParryTimer.ParryState.CRITICAL:
			# Renvoi critique : balle rouge + plus de dégâts
			_spawn_reflected_bullet(25, true)
			_pending_bullet.queue_free()

	# On remet à null pour être prêts pour la prochaine balle
	_pending_bullet = null


# =============================================================
# RENVOI DE BALLE
# =============================================================

func _spawn_reflected_bullet(bullet_damage: int, is_critical: bool = false) -> void:
	# Créer une copie de la scène bullet_reflected en mémoire
	var bullet: BulletReflected = _bullet_reflected_scene.instantiate()

	# L'ajouter à la scène AVANT d'appeler init()
	# (global_position n'est accessible qu'une fois dans l'arbre de scène)
	get_tree().current_scene.add_child(bullet)

	# Initialiser : spawn au niveau du bouclier, part dans la direction du bouclier
	bullet.init(global_position, _shield_direction, bullet_damage, is_critical)
