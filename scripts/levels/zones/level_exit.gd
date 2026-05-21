# Portail pour sortir ET TERMINER un niveau (au niveau du score)
extends Area3D

@onready var mesh_detect : Node = $Mesh_detector
@onready var meshs_portal_effect : Node = $Portal/Mesh_container

func _ready():
	monitorable = false
	monitoring = false
	mesh_detect.hide()
	meshs_portal_effect.hide()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func activate():
	monitoring = true
	mesh_detect.show()
	meshs_portal_effect.show()

func _on_body_entered(body: Node3D):
	if body is Player:
		ScoreManager.call_deferred("end_level")
