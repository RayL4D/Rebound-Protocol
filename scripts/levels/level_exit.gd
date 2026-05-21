extends Area3D

func _ready():
	monitorable = false
	monitoring = false
	hide()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func activate():
	monitoring = true
	show()

func _on_body_entered(body: Node3D):
	if body is Player:
		ScoreManager.end_level()
