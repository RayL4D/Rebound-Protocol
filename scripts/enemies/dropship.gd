# =============================================================
# Dropship.gd — Vaisseau de transport de troupes
# Auteur : Kevin SIDER
# =============================================================
class_name Dropship
extends Node3D

@export var mob_scene: PackedScene # import de la scène de l'ennemie dans l'inspecteur
@export var pause_duration: float = 1.5
@export var spawn_count: int = 1

var dropship_mesh: PackedScene = null # .glb d'un autre vaisseau (utilisé pour les boss par exemple)
var enemy_died_callback: Callable = Callable()

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var spawn_point: Marker3D = %Spawn_point
@onready var dust_container: Node3D = %Cargo_dust_container
@onready var container: Node3D = $Dropship_container
@onready var cargo_spawner: Node3D = $Dropship_container/cargo_spawner


func _ready() -> void:
	if not anim_player:
		push_error("Dropship : AnimationPlayer introuvable !")
		return

	# Changement d'apparance du vaisseau (si sélectionée)
	if dropship_mesh:
		_swap_mesh(dropship_mesh)

	anim_player.stop()
	_start_delivery_sequence()


func _swap_mesh(new_mesh_scene: PackedScene) -> void:
	if not cargo_spawner:
		push_warning("Dropship : cargo_spawner introuvable, swap ignoré.")
		return

	# garder la position du vaisseau
	var saved_transform := cargo_spawner.transform

	cargo_spawner.queue_free()

	var new_mesh: Node3D = new_mesh_scene.instantiate()
	container.add_child(new_mesh)
	new_mesh.transform = saved_transform


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

		if enemy_died_callback.is_valid() and mob.has_signal("enemy_died"):
			mob.enemy_died.connect(enemy_died_callback)

		get_parent().add_child(mob)

		# Apparition semi-aléatoire
		var offset := Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		mob.global_position = spawn_point.global_position + offset
		mob.global_rotation.y = spawn_point.global_rotation.y

	print("Dropship : %d unité(s) déployée(s)." % spawn_count)


func _start_takeoff() -> void:
	anim_player.play("takeoff")
	await anim_player.animation_finished
	queue_free()
