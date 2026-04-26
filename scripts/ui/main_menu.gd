extends Control

# Boutons du menu principal
@onready var btn_new_game = $CenterContainer/MainVBox/ButtonsVBox/BtnNewGame
@onready var btn_quit = $CenterContainer/MainVBox/ButtonsVBox/BtnQuit

# Éléments de la langue
@onready var btn_toggle_language = $CenterContainer/MainVBox/LanguageVBox/BtnToggleLanguage
@onready var flags_container = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer

@onready var btn_flag_fr = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagFR
@onready var btn_flag_en = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagEN
@onready var btn_flag_es = $CenterContainer/MainVBox/LanguageVBox/FlagsContainer/BtnFlagES

func _ready():
	flags_container.hide()
	
	# Connexions du menu principal
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)
	
	# Connexion du bouton pour dérouler les langues
	btn_toggle_language.pressed.connect(_on_toggle_language_pressed)
	
	# Connexions des drapeaux
	btn_flag_fr.pressed.connect(func(): _change_language("fr"))
	btn_flag_en.pressed.connect(func(): _change_language("en"))
	btn_flag_es.pressed.connect(func(): _change_language("es"))

func _on_new_game_pressed():
	# Charge le tutoriel
	SceneManager.load_level("res://scenes/levels/arena_base.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _on_toggle_language_pressed():
	flags_container.visible = !flags_container.visible

func _change_language(locale: String):
	TranslationServer.set_locale(locale)
	flags_container.hide()
	
	print("Langue changée pour : ", locale)
