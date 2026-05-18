extends Area3D

@export var slow_multiplier : float = 0.4 
var _original_speed : float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_original_speed = body.move_speed
		body.move_speed *= slow_multiplier

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		body.move_speed = _original_speed
