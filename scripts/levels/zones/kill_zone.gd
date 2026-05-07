# =============================================================
# kill_zone.gd - Réinitialise le niveau au contact
# =============================================================
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		var current_scene = get_tree().current_scene.scene_file_path
		
		if SceneManager:
			SceneManager.load_level(current_scene)
		else:
			get_tree().reload_current_scene()
