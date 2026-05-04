# =============================================================
# instant_exit.gd - Sortie de niveau générique
# =============================================================
extends Area3D

@export_category("Level Transition")
## Chemin de la prochaine scène à charger. 
@export_file("*.tscn") var next_scene_path: String

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	if animation_player and animation_player.has_animation("direction_animation"):
		animation_player.play("direction_animation")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if next_scene_path != "":
			SceneManager.load_level(next_scene_path)
		else:
			push_warning("LevelExit : Aucun 'next_scene_path' n'a été défini dans l'inspecteur !")
