extends Node

@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene
@export var spawn_points: Array[NodePath] # Points de spawn dans l'arène

var current_wave: int = 0
var enemies_to_spawn: int = 5
var enemies_alive: int = 0

func _ready():
	# Seul le serveur gère la logique de vague
	if not multiplayer.is_server():
		set_process(false)
		return

func start_next_wave():
	current_wave += 1
	
	# Calcul de la difficulté
	if current_wave % 5 == 0:
		enemies_to_spawn = 1 # Boss unique
		spawn_entity(boss_scene)
	else:
		# Augmentation exponentielle ou linéaire de la difficulté
		enemies_to_spawn = 5 + (current_wave * 2)
		for i in range(enemies_to_spawn):
			spawn_entity(enemy_scene)
			
	enemies_alive = enemies_to_spawn
	# On informe les clients du changement de vague (facultatif, pour UI)
	rpc("update_wave_ui", current_wave)

func spawn_entity(scene: PackedScene):
	var entity = scene.instantiate()
	var spawn_node = get_node(spawn_points.pick_random())
	entity.global_position = spawn_node.global_position
	
	# On ajoute au conteneur synchronisé par le MultiplayerSpawner
	get_node("/scenes/levels/multiplayer/arena_multiplayer/Players").add_child(entity, true)
	
	# Connexion à la mort pour décompte (côté serveur uniquement)
	entity.tree_exiting.connect(_on_enemy_death)

func _on_enemy_death():
	if not multiplayer.is_server(): return
	
	enemies_alive -= 1
	if enemies_alive <= 0:
		await get_tree().create_timer(2.0).timeout # Pause entre vagues
		start_next_wave()

@rpc("authority", "reliable")
func update_wave_ui(_wave_num):
	# Appelée sur les clients pour mettre à jour leur HUD
	pass
