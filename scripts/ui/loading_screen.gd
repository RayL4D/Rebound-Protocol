extends CanvasLayer

@onready var spinner = %TextureRect 

func _ready():
	spinner.pivot_offset = spinner.size / 2.0

func _process(delta):
	spinner.rotation += 5.0 * delta
