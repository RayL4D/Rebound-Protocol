extends Area3D

@export_file("*.tscn") var next_scene: String = "res://scenes/levels/arena_base.tscn"

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready():
	# caché au début
	monitorable = false
	monitoring = false
	hide()
	body_entered.connect(_on_body_entered)


func activate():
	monitoring = true
	show()
	
	if animation_player and animation_player.has_animation("direction_animation"):
		animation_player.play("direction_animation")


func _on_body_entered(body: Node3D):
	if body is Player: 
		SceneManager.load_level("res://scenes/levels/arena_base.tscn")
