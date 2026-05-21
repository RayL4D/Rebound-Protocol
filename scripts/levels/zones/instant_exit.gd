# Portail pour sortir d'une scène (dans le cas d'un niveau avec plusieurs scènes)
extends Area3D

@export_category("Level Transition")
@export_file("*.tscn") var next_scene_path: String

func _ready() -> void:
	CollisionManager.add_missing_collisions(self)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if next_scene_path != "":
			SceneManager.load_level(next_scene_path)
		else:
			push_warning("LevelExit : Aucun 'next_scene_path' n'a été défini dans l'inspecteur !")
