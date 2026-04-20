# =============================================================
# Dropship.gd — Vaisseau de transport de troupes
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Dropship
extends Node3D

@export var mob_scene: PackedScene
@export var pause_duration: float = 1.5

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var spawn_point: Marker3D = %Spawn_point
@onready var dust_container: Node3D = %Cargo_dust_container

func _ready() -> void:
	if not anim_player:
		push_error("Dropship : AnimationPlayer introuvable dans Dropship_container.")
		return
	
	anim_player.stop()	
	_start_delivery_sequence()


# =============================================================
# LOGIQUE DE SÉQUENCE
# =============================================================

func _start_delivery_sequence() -> void:
	anim_player.play("landing")
	await anim_player.animation_finished
	
	_spawn_mob()
	
	await get_tree().create_timer(pause_duration).timeout
	
	_start_takeoff()


func _spawn_mob() -> void:
	if not mob_scene:
		push_warning("Dropship : Aucune scène de mob assignée dans l'inspecteur !")
		return
		
	var mob = mob_scene.instantiate()
	
	get_parent().add_child(mob)
	
	mob.global_position = spawn_point.global_position
	mob.global_rotation.y = spawn_point.global_rotation.y
	
	print("Rebound Protocol : Unité ennemie déployée.")


func _start_takeoff() -> void:
	anim_player.play("takeoff")
	await anim_player.animation_finished
	
	# On libère le vaisseau une fois qu'il a quitté la zone
	queue_free()
