# =============================================================
# SceneManager.gd — Gère les transitions entre les scènes
# Auteur : Kevin SIDER
# =============================================================
extends Node

var loading_screen_scene = preload("res://scenes/ui/loading_screen.tscn")
var loading_screen_instance = null
# Sauvegarde de la langue choisie dans le menu principal ici 
var current_lang: String = "fr"

func load_level(target_scene_path: String):
	# Afficher l'écran de chargement
	loading_screen_instance = loading_screen_scene.instantiate()
	get_tree().root.add_child(loading_screen_instance)
	
	# Petit délai pour laisser le temps à l'UI de s'afficher
	await get_tree().create_timer(0.1).timeout
	
	var err = get_tree().change_scene_to_file(target_scene_path)
	
	if err != OK:
		printerr("Erreur lors du chargement de la scène : ", target_scene_path)
	
	# Attendre que la nouvelle scène soit prête
	await get_tree().node_added
	
	# Retirer l'écran de chargement
	if loading_screen_instance:
		loading_screen_instance.queue_free()
		loading_screen_instance = null
