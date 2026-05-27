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

@tool
class_name Chest
extends Node3D

@export var coin_value: int  = 1   # valeur par pièce
@export var coin_count: int  = 5   # nombre de pièces spawnées

const CHEST_TEXTURE := preload("res://assets/textures/platformerkit/colormap.png")

@onready var _model:  Node3D  = $ChestModel
@onready var _area:   Area3D  = $InteractArea
@onready var _prompt: Label3D = $Prompt

var _anim_player:  AnimationPlayer = null
var _opened:       bool           = false
var _player_near:  bool           = false


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_apply_texture(_model)
	_anim_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_prompt.text = tr("CHEST_OPEN")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _opened or not _player_near:
		return
	if Input.is_action_just_pressed("interact"):
		_open()


# =============================================================
# CONSTRUCTION
# =============================================================

func _apply_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = CHEST_TEXTURE
		var count := mi.mesh.get_surface_count() if mi.mesh else 1
		for i in count:
			mi.set_surface_override_material(i, mat)
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
