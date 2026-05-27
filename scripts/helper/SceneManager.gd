extends Node

var loading_screen_scene = preload("res://scenes/ui/loading_screen.tscn")
var loading_screen_instance = null
var current_lang: String = "fr"
var next_scene_path: String = ""

func load_level(target_scene_path: String):
	next_scene_path = target_scene_path
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/loading_screen.tscn")
