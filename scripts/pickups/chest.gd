# =============================================================
# chest.gd — Coffre interactif donnant des pièces au joueur
# Rebound Protocol
#
# Usage : placer la scène chest.tscn dans un niveau.
#   - Le joueur s'approche → prompt d'interaction visible
#   - Le joueur appuie sur la touche d'interaction → animation open
#     puis spawn des pièces
#   - Le coffre ne peut être ouvert qu'une seule fois
#
# Paramètres exportés (modifiables dans l'éditeur) :
#   coin_value  : nombre de pièces données (défaut : 5)
#   coin_count  : nombre de pièces spawnées (défaut : 5)
# =============================================================

class_name Chest
extends Node3D

@export var coin_value: int  = 1   # valeur par pièce
@export var coin_count: int  = 5   # nombre de pièces spawnées

const CHEST_MODEL   := preload("res://assets/models/platformerkit/chest.glb")
const CHEST_TEXTURE := preload("res://assets/textures/platformerkit/colormap.png")

const INTERACT_RADIUS := 2.0   # rayon de détection du joueur

var _area:         Area3D         = null
var _model:        Node3D         = null
var _anim_player:  AnimationPlayer = null
var _prompt:       Label3D        = null
var _opened:       bool           = false
var _player_near:  bool           = false


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_build_model()
	_build_detection_area()
	_build_prompt()


func _process(_delta: float) -> void:
	if _opened or not _player_near:
		return
	if Input.is_action_just_pressed("interact"):
		_open()


# =============================================================
# CONSTRUCTION
# =============================================================

func _build_model() -> void:
	_model = CHEST_MODEL.instantiate()
	_model.scale    = Vector3(1.5, 1.5, 1.5)  # augmente la taille
	_model.position = Vector3(0, -0.4, 0)      # ajuste jusqu'au sol
	add_child(_model)
	_apply_texture(_model)

	# Chercher l'AnimationPlayer dans le GLB
	_anim_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _build_detection_area() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask  = 1   # layer player

	var shape        := CollisionShape3D.new()
	var sphere       := SphereShape3D.new()
	sphere.radius     = INTERACT_RADIUS
	shape.shape       = sphere
	_area.add_child(shape)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _build_prompt() -> void:
	_prompt              = Label3D.new()
	_prompt.text         = "[F] Ouvrir"
	_prompt.font_size    = 48
	_prompt.modulate     = Color(1.0, 0.90, 0.3)
	_prompt.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position     = Vector3(0, 1.4, 0)
	_prompt.visible      = false
	add_child(_prompt)


func _apply_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = CHEST_TEXTURE
		(node as MeshInstance3D).set_surface_override_material(0, mat)
	for child in node.get_children():
		_apply_texture(child)


# =============================================================
# INTERACTION
# =============================================================

func _open() -> void:
	_opened = true
	_prompt.visible = false

	# Jouer l'animation d'ouverture
	if _anim_player:
		if _anim_player.has_animation("open"):
			_anim_player.play("open")
			await _anim_player.animation_finished
		elif _anim_player.has_animation("open-close"):
			_anim_player.play("open-close")
			await _anim_player.animation_finished

	_spawn_coins()


func _spawn_coins() -> void:
	var spawn_pos := global_position + Vector3(0, 0.5, 0)
	for i in coin_count:
		Coin.spawn(get_tree().current_scene, spawn_pos, coin_value)


# =============================================================
# ZONE DE DÉTECTION
# =============================================================

func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_near = true
		if not _opened:
			_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body is Player:
		_player_near = false
		_prompt.visible = false
