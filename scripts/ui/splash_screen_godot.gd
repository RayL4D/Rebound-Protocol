extends Control

@export var load_scene : PackedScene
@export var in_time : float = 0.5
@export var fade_in_time : float = 1.5
@export var pause_time : float = 1.5
@export var fade_out_time : float = 1.5
@export var out_time : float = 0.5

@onready var splash_content : TextureRect = $TextureRect


func fade() -> void:
	splash_content.modulate.a = 0.0
	var tween = self.create_tween()
	tween.tween_interval(in_time)
	tween.tween_property(splash_content, "modulate:a", 1.0, fade_in_time)
	tween.tween_interval(pause_time)
	tween.tween_property(splash_content, "modulate:a", 0.0, fade_out_time)
	tween.tween_interval(out_time)
	await tween.finished
	get_tree().change_scene_to_packed(load_scene)


func _ready() -> void:
	if OS.has_feature("mobile"):
		_setup_bleed_background()
	fade()


# Sur mobile, remplace le fond uni par la même image en mode "couverture".
# Les bords de l'écran sont ainsi remplis par l'image elle-même (légèrement
# assombrie) plutôt que par une bande grise — technique "bleed" standard.
func _setup_bleed_background() -> void:
	var bleed := TextureRect.new()
	bleed.texture        = splash_content.texture
	bleed.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	bleed.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bleed.set_anchors_preset(Control.PRESET_FULL_RECT)
	bleed.modulate       = Color(0.45, 0.45, 0.45, 1.0)  # assombri → image principale reste dominante
	add_child(bleed)
	# Ordre : ColorRect (fond) → bleed (image couverte) → splash_content (image nette)
	move_child(bleed, 1)
