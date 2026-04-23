extends CanvasLayer

@onready var spinner = $TextureRect

func _process(delta):
	spinner.rotation += 5.0 * delta
