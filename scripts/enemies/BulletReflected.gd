# =============================================================
# BulletReflected.gd — Balle renvoyée par le bouclier du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
#
# Même fonctionnement que Bullet.gd, mais dans l'autre sens :
#   - elle est tirée par le joueur (via le bouclier)
#   - elle blesse les ennemis, pas le joueur
#   - ses dégâts sont définis au moment du spawn (standard ou critique)
# =============================================================
class_name BulletReflected
extends Area3D

# --- Exports -----------------------------------------------------
# La balle renvoyée est plus rapide que la balle ennemie
@export var speed: float = 16.0

# --- Variables internes ------------------------------------------
var direction: Vector3 = Vector3.ZERO
var damage: int        = 10  # sera écrasé par init()


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	$VisibleOnScreenNotifier3D.screen_exited.connect(_on_screen_exited)
	# body_entered détecte les CharacterBody3D — les ennemis en sont
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# Même raison que Bullet.gd : synchronisation avec le moteur physique
	global_position += direction * speed * delta


# =============================================================
# INITIALISATION — appelée par Shield.gd après add_child()
# =============================================================

# Le paramètre bullet_damage permet à Shield.gd de passer
# 10 (standard) ou 25 (critique) selon l'état de la parade.
# is_critical change la couleur de la balle en rouge.
func init(spawn_position: Vector3, target_direction: Vector3, bullet_damage: int, is_critical: bool = false) -> void:
	global_position = spawn_position
	direction       = target_direction.normalized()
	damage          = bullet_damage

	# set_surface_override_material applique un matériau uniquement
	# sur CETTE instance, sans modifier la scène ni les autres balles.
	# On crée un nouveau StandardMaterial3D à la volée avec la bonne couleur.
	if is_critical:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0, 1)  # Rouge
		$MeshInstance3D.set_surface_override_material(0, mat)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 0, 1)  # Jaune
		$MeshInstance3D.set_surface_override_material(0, mat)

# =============================================================
# COLLISIONS
# =============================================================

func _on_body_entered(body: Node3D) -> void:
	# is_in_group("enemies") vérifie si le nœud est dans ce groupe.
	# Ça fonctionne pour TOUS les types d'ennemis (Placeholder, Grunt,
	# Sniper, etc.) tant qu'ils font add_to_group("enemies") dans _ready().
	if body.is_in_group("enemies"):
		body.take_damage(damage)
		queue_free()


func _on_screen_exited() -> void:
	queue_free()
