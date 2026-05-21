# Portail pour sortir ET TERMINER un niveau (au niveau du score)
extends Area3D

func _ready():
	CollisionManager.add_missing_collisions(self)
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
		ScoreManager.call_deferred("end_level")
