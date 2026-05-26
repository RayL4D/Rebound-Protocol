extends Control

@onready var background: TextureRect = $Background
@onready var title_label: Label = $BottomBanner/HBoxContainer/TitleContainer/TitleLabel
@onready var desc_label: Label = $BottomBanner/HBoxContainer/DescContainer/DescLabel
@onready var loading_logo: TextureRect = $BottomBanner/HBoxContainer/LogoContainer/LoadingLogo

var target_scene_path: String = ""
var minimum_time: float = 5.0
var elapsed_time: float = 0.0
var load_ready: bool = false
var loaded_scene: PackedScene = null

# On stocke les clés (texte simple) au lieu d'appeler tr() ici
const LEVEL_INFOS = {
	"arena_base": {
		"title_key": "ARENA_BASE_TITLE",
		"desc_key": "ARENA_BASE_DESC",
		"image": "res://assets/ui/loading_screen_background/arena_base.JPG"
	},
	"arena_first_level_1": {
		"title_key": "ARENA_FIRST_LEVEL_1_TITLE",
		"desc_key": "ARENA_FIRST_LEVEL_1_DESC",
		"image": "res://assets/ui/loading_screen_background/arena_first_level_1.JPG"
	},
		"arena_first_level_2": {
		"title_key": "ARENA_FIRST_LEVEL_1_TITLE",
		"desc_key": "ARENA_FIRST_LEVEL_1_DESC",
		"image": "res://assets/ui/loading_screen_background/arena_first_level_1.JPG"
	},
		"arena_first_level_3": {
		"title_key": "ARENA_FIRST_LEVEL_1_TITLE",
		"desc_key": "ARENA_FIRST_LEVEL_1_DESC",
		"image": "res://assets/ui/loading_screen_background/arena_first_level_1.JPG"
	}
}

func _ready() -> void:
	TranslationServer.set_locale(SceneManager.current_lang)
	target_scene_path = SceneManager.next_scene_path
	_setup_ui_for_level(target_scene_path)
	if target_scene_path != "":
		ResourceLoader.load_threaded_request(target_scene_path)
	else:
		printerr("ERREUR: Aucun niveau cible défini pour l'écran de chargement.")

func _setup_ui_for_level(path: String) -> void:
	# CORRECTION : Convertir l'UID en chemin réel si nécessaire
	var real_path = path
	
	# Si le chemin commence par "uid://", on le convertit en chemin de fichier
	if path.begins_with("uid://"):
		real_path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
		print("DEBUG Loading Screen - UID détecté, conversion : ", path, " -> ", real_path)
	
	# On extrait le nom du fichier sans extension du chemin réel
	var level_filename = real_path.get_file().get_basename()
	
	# Debug pour vérifier la clé
	print("DEBUG Loading Screen - Chemin original : ", path)
	print("DEBUG Loading Screen - Chemin réel : ", real_path)
	print("DEBUG Loading Screen - Nom de fichier extrait : ", level_filename)
	
	if LEVEL_INFOS.has(level_filename):
		var info = LEVEL_INFOS[level_filename]
		# On appelle tr() ici, au moment d'affecter le texte au Label
		title_label.text = tr(info["title_key"])
		desc_label.text = tr(info["desc_key"])
		
		if ResourceLoader.exists(info["image"]):
			background.texture = load(info["image"])
		
		print("DEBUG Loading Screen - Infos trouvées pour : ", level_filename)
	else:
		# Appel direct de tr() pour les valeurs par défaut
		title_label.text = tr("LOADING_DEFAULT_TITLE")
		desc_label.text = tr("LOADING_DEFAULT_DESC")
		
		print("DEBUG Loading Screen - Aucune info trouvée, affichage des valeurs par défaut")
		print("DEBUG Loading Screen - Clés disponibles dans LEVEL_INFOS : ", LEVEL_INFOS.keys())

func _process(delta: float) -> void:
	elapsed_time += delta

	if loading_logo:
		loading_logo.pivot_offset = loading_logo.size / 2.0
		loading_logo.rotation += 3.0 * delta

	if target_scene_path != "" and not load_ready:
		var progress_array = []
		var status = ResourceLoader.load_threaded_get_status(target_scene_path, progress_array)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			load_ready = true
			loaded_scene = ResourceLoader.load_threaded_get(target_scene_path)

	if load_ready and elapsed_time >= minimum_time:
		get_tree().change_scene_to_packed(loaded_scene)
