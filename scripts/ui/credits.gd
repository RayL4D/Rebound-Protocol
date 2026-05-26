# =============================================================
# credits.gd — Page de crédits avec auto-scroll
# =============================================================
extends Control

# --- CONFIGURATION ---
@export var auto_scroll_speed: float = 30.0  # Pixels par seconde
@export var enable_auto_scroll: bool = true

# --- RÉFÉRENCES ---
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var credits_vbox: VBoxContainer = %CreditsVBox
@onready var btn_back: Button = %BtnBack

# --- VARIABLES ---
var is_auto_scrolling: bool = true
var wait_timer: float = 0.0
var scroll_accumulator: float = 0.0

func _ready() -> void:
	if scroll_container:
		scroll_container.scroll_vertical = 0

func _process(delta: float) -> void:
	if not enable_auto_scroll or not is_auto_scrolling:
		return

	if wait_timer > 0:
		wait_timer -= delta
		return

	if scroll_container:
		# On accumule le mouvement dans une variable float
		scroll_accumulator += auto_scroll_speed * delta

		# On applique seulement la partie entière à la propriété scroll_vertical
		# et on garde le reste dans l'accumulateur
		var pixels_to_scroll = int(scroll_accumulator)
		scroll_container.scroll_vertical += pixels_to_scroll
		scroll_accumulator -= pixels_to_scroll

		# Calcul du point maximal de défilement
		var max_scroll = scroll_container.get_v_scroll_bar().max_value - scroll_container.size.y

		# Réinitialisation si on arrive au bout
		if max_scroll > 0 and scroll_container.scroll_vertical >= max_scroll:
			wait_timer = 2.0
			scroll_container.scroll_vertical = 0
			scroll_accumulator = 0.0 # On réinitialise aussi le surplus

func _input(event: InputEvent) -> void:
	# Pause auto-scroll si l'utilisateur scroll manuellement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			is_auto_scrolling = false
	
	# Reprendre auto-scroll avec Espace
	if event.is_action_pressed("ui_accept"):
		is_auto_scrolling = true
	
	# Retour avec Echap
	if event.is_action_pressed("ui_cancel"):
		_on_btn_back_pressed()

func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
