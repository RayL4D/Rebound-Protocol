extends Node

signal language_changed(locale: String)

var loading_screen_scene = preload("res://scenes/ui/loading_screen.tscn")
var loading_screen_instance = null
var current_lang: String = "fr"
var next_scene_path: String = ""

func load_level(target_scene_path: String):
	next_scene_path = target_scene_path
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/loading_screen.tscn")


func _ready():
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		current_lang = cfg.get_value("locale", "language", "fr")
	else:
		current_lang = "fr" # Défaut
	
	TranslationServer.set_locale(current_lang)

func update_language(locale: String):
	current_lang = locale
	TranslationServer.set_locale(locale)
	# Sauvegarde persistante
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("locale", "language", locale)
	cfg.save("user://settings.cfg")
	language_changed.emit(locale)
