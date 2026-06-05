# =============================================================
# kill_zone.gd — Tue le joueur au contact (lave, vide, etc.)
# =============================================================
# La mort passe par le flow normal (GameOver → checkpoint),
# contrairement à un reload brut qui ignore la sauvegarde.
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# Tuer via take_damage pour déclencher player_died → GameOver → respawn checkpoint.
	if body.has_method("take_damage"):
		body.take_damage(99999)
