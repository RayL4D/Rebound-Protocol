extends Node3D

func _ready() -> void:
	# --- Collisions du décor ---
	# On parcourt les enfants directs et on génère les collisions manquantes,
	# en ignorant les nœuds décoratifs dont le nom commence par "grass".
	for child in get_children():
		if child.name.to_lower().begins_with("grass"):
			continue
		CollisionManager.add_missing_collisions(child)

	# --- Suivi de score (kills, temps...) comme dans les autres niveaux ---
	ScoreManager.start_level()

	# --- Setup différé (après que tous les _ready() de la scène ont tourné) ---
	call_deferred("_post_ready_setup")


func _post_ready_setup() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# --- Valeurs normales du personnage ---
	# Sacha avait laissé des valeurs de test sur le nœud Player (max_hp=10000,
	# move_speed=20). On force les valeurs standard du jeu.
	player.max_hp     = 100
	player.move_speed = 5.0
	if player.current_hp > player.max_hp:
		player.current_hp = player.max_hp

	# --- Anti-téléportation inter-niveau ---
	# Le Player restaure sa position depuis le dernier checkpoint au 1er frame
	# physique. Si ce checkpoint vient d'un AUTRE niveau (le niveau 1), ses
	# coordonnées tombent hors-map ici (au-dessus de l'eau). On ne restaure alors
	# que les PV et on garde la position placée dans la scène (sur la plage).
	# Même protection que arena_first_level_*.gd._deferred_restore_player().
	if SaveData.active_slot >= 0:
		var saved_level := SaveData.get_current_level()
		if saved_level != "" and saved_level != "arena_second_level_1":
			if player.has_method("restore_hp_only"):
				player.restore_hp_only()
		elif player.has_method("restore_from_checkpoint"):
			player.restore_from_checkpoint()

	# --- Connexion du HUD au joueur ---
	# Au niveau 2 le HUD est listé avant le Player dans la scène, donc son
	# auto-connexion dans HUD._ready() échoue ("joueur introuvable").
	# connect_to_player() est idempotent (ne refait rien s'il est déjà connecté).
	var hud := get_node_or_null("config_play/HUD")
	if hud != null and hud.has_method("connect_to_player"):
		hud.connect_to_player(player)
