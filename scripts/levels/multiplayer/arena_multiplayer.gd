extends Node3D

@onready var players_container = $Players

func _ready():
	# On définit que seul le serveur autorise le spawn
	if is_multiplayer_authority():
		# Spawn de l'hôte
		spawn_player(1)
		
		# Pour les clients qui sont déjà là
		for peer in multiplayer.get_peers():
			spawn_player(peer)
	else:
		# Le client demande au serveur de le faire spawner
		request_spawn.rpc_id(1)

func spawn_player(id: int):
	# Charger la scène seulement si nécessaire
	var p = preload("res://scenes/player/player.tscn").instantiate()
	p.name = str(id)
	p.position = Vector3(randf_range(-2, 2), 1, randf_range(-2, 2))
	players_container.add_child(p, true) # 'true' active la synchro automatique

@rpc("any_peer", "call_local")
func request_spawn():
	# Seul le serveur exécute ce code
	if is_multiplayer_authority():
		spawn_player(multiplayer.get_remote_sender_id())
