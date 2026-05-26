# Portail pour sortir d'une scène (dans le cas d'un niveau avec plusieurs scènes)
extends Area3D

@export_category("Level Transition")
@export_file("*.tscn") var next_scene_path: String
@onready var mesh_detect : Node = $Mesh_detector
@onready var meshs_portal_effect : Node = $Portal/Mesh_container

func _ready() -> void:
	monitorable = false
	monitoring = false
	mesh_detect.hide()
	meshs_portal_effect.hide()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if next_scene_path != "":
			SceneManager.load_level(next_scene_path)
		else:
			push_warning("LevelExit : Aucun 'next_scene_path' n'a été défini dans l'inspecteur !")


func activate():
	monitoring = true
	mesh_detect.show()
	meshs_portal_effect.show()
