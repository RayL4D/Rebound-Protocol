# =============================================================
# Dropship.gd — Vaisseau de transport de troupes
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name Dropship
extends Node3D

@export var mob_scene: PackedScene
@export var pause_duration: float = 1.5

## Nombre d'ennemis à déposer (assigné par le WaveManager)
@export var spawn_count: int = 1

var enemy_died_callback: Callable = Callable()

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var spawn_point: Marker3D = %Spawn_point
@onready var dust_container: Node3D = %Cargo_dust_container

func _ready() -> void:
	if not anim_player:
		push_error("Dropship : AnimationPlayer introuvable !")
		return

	anim_player.stop()
	_start_delivery_sequence()


# =============================================================
# SÉQUENCE
# =============================================================

func _start_delivery_sequence() -> void:
	anim_player.play("landing")
	await anim_player.animation_finished

	_spawn_mobs()

	await get_tree().create_timer(pause_duration).timeout

	_start_takeoff()


func _spawn_mobs() -> void:
	if not mob_scene:
		push_warning("Dropship : Aucune scène de mob assignée !")
		return

	for i in range(spawn_count):
		var mob = mob_scene.instantiate()

		# Connecte le signal de mort de l'ennemi au callback du WaveManager
		if enemy_died_callback.is_valid() and mob.has_signal("enemy_died"):
			mob.enemy_died.connect(enemy_died_callback)

		get_parent().add_child(mob)

		# Légère variation de position pour éviter le spawn au même endroit
		var offset := Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		mob.global_position = spawn_point.global_position + offset
		mob.global_rotation.y = spawn_point.global_rotation.y

	print("Dropship : %d unité(s) déployée(s)." % spawn_count)


func _start_takeoff() -> void:
	anim_player.play("takeoff")
	await anim_player.animation_finished
	queue_free()
