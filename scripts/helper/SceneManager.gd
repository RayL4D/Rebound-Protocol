extends Node

var loading_screen_scene = preload("res://scenes/ui/loading_screen.tscn")
var loading_screen_instance = null
var current_lang: String = "fr"

func load_level(target_scene_path: String):
	# 1. Afficher l'écran de chargement
	loading_screen_instance = loading_screen_scene.instantiate()
	get_tree().root.add_child(loading_screen_instance)
	
	# Petit délai pour laisser le temps à l'UI de s'afficher
	await get_tree().create_timer(0.1).timeout
	
	# 2. Charger la scène en arrière-plan
	# Pour un projet de cette taille, change_scene_to_file suffit.
	# Si la map est très lourde, on utiliserait ResourceLoader.load_threaded_request
	var err = get_tree().change_scene_to_file(target_scene_path)
	
	if err != OK:
		printerr("Erreur lors du chargement de la scène : ", target_scene_path)
	
	# 3. Attendre que la nouvelle scène soit prête
	await get_tree().node_added
	
	# 4. Retirer l'écran de chargement
	if loading_screen_instance:
		loading_screen_instance.queue_free()
		loading_screen_instance = null
