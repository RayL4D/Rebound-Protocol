# =============================================================
# Enemy.gd — Classe de base pour tous les ennemis
# Rebound Protocol
# =============================================================
# Ne pas attacher directement à une scène — utilise PetShooter,
# PetMortar, ou tout autre type qui hérite de cette classe.
#
# Héritage :  Enemy (ici) → PetShooter / PetMortar / ...
# Composition : chaque ennemi a un nœud WeaponComponent enfant
#               qui gère la logique de tir indépendamment.
# =============================================================
class_name Enemy
extends CharacterBody3D

# --- Exports communs à tous les ennemis -------------------------
@export var max_hp: int        = 30
@export var move_speed: float  = 2.0

# Échelle du modèle visuel (pas de la hitbox).
# Référence joueur : capsule radius 0.25 / height 1.8
#   Pet standard → 0.55  (légèrement plus petit que le joueur)
#   Mini-boss    → 1.1   (deux fois plus gros)
#   Boss final   → 1.8+  (imposant)
@export var model_scale: float = 0.55

# Offset Y du modèle pour corriger les modèles dont le pivot
# n'est pas centré sur les pieds. Ajuste dans l'inspector
# jusqu'à ce que le pet repose bien sur le sol.
@export var model_y_offset: float = 0.0

# --- Textures (même principe que Player.gd) ----------------------
var _enemy_texture:  Texture2D = preload("res://assets/textures/enemies/colormap.png")
var _weapon_texture: Texture2D = preload("res://assets/textures/weapons/colormap.png")

# --- État -------------------------------------------------------
var current_hp: int
var player: Player  = null
var _model: Node3D  = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Signal (compatible avec EnemyPlaceholder) ------------------
signal enemy_died


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")

	# Couche 5 (valeur 16) = même couche qu'EnemyPlaceholder
	# → bullet_reflected a collision_mask = 16, donc elle détectera tous les ennemis
	# Mask = couche 1 (player=1) + couche 3 (world=4) = 5
	collision_layer = 16
	collision_mask  = 5

	player = get_tree().get_first_node_in_group("player")
	_setup_model()
	_on_ready()  # Hook pour les sous-classes


# =============================================================
# SETUP DU MODÈLE (scale + offset Y + textures)
# =============================================================

func _setup_model() -> void:
	# Trouver le nœud modèle ennemi (premier Node3D enfant hors CollisionShape et WeaponMount)
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			if child.name != "WeaponMount":
				_model = child
				break

	if _model == null:
		push_warning("Enemy: aucun nœud modèle trouvé — scale/texture non appliqués.")
		return

	# Appliquer l'échelle et l'offset Y (pour sortir le modèle du sol)
	_model.scale      = Vector3.ONE * model_scale
	_model.position.y = model_y_offset

	# Appliquer la texture colormap sur le modèle ennemi
	_apply_texture_recursive(_model, _enemy_texture)

	# Appliquer la texture colormap sur l'arme (WeaponMount)
	var weapon_mount := get_node_or_null("WeaponMount")
	if weapon_mount:
		_apply_texture_recursive(weapon_mount, _weapon_texture)


# Même logique que Player.gd : parcourt tous les MeshInstance3D
# de façon récursive et applique la texture sur chacun.
func _apply_texture_recursive(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		node.set_surface_override_material(0, mat)
	for child in node.get_children():
		_apply_texture_recursive(child, texture)


# Hook surchargeable dans chaque type d'ennemi.
# Sert à initialiser les composants (arme, timer…) qui nécessitent
# que le nœud soit dans l'arbre de scène (@onready déjà résolu).
func _on_ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	if player == null:
		return

	_apply_gravity(delta)
	_update_movement(delta)
	move_and_slide()
	_face_player()


# =============================================================
# MOUVEMENT — à surcharger dans chaque sous-classe
# =============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


# Surcharge ce méthode pour définir le pattern de déplacement propre
# à chaque type d'ennemi (foncer, orbiter, reculer…).
func _update_movement(_delta: float) -> void:
	pass


# Rotation vers le joueur (horizontal uniquement)
func _face_player() -> void:
	var dir := player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.z)


# =============================================================
# SANTÉ
# =============================================================

func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	if current_hp <= 0:
		_die()


func _die() -> void:
	enemy_died.emit()
	queue_free()
