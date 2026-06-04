extends Node3D

var joueur_est_a_bord = false

func _ready():
	# Ce message DOIT s'afficher au lancement du jeu, sinon le bateau n'est pas dans le niveau
	print("BATEAU PRÊT - Script chargé !")

func _process(_delta):
	# _process tourne en boucle à chaque image. Impossible que la touche soit ignorée ici.
	if Input.is_action_just_pressed("interagir"):
		print("--- TOUCHE F DÉTECTÉE ---")
		
		# On cherche le joueur via son groupe
		var joueur = get_tree().get_first_node_in_group("joueur")
		
		if joueur:
			# On calcule la distance entre le bateau et le joueur
			var distance = global_position.distance_to(joueur.global_position)
			print("Distance avec le joueur : ", distance)
			
			# Si le joueur est à moins de 6 mètres, il monte
			if distance < 6.0 and not joueur_est_a_bord:
				monter_dans_le_bateau(joueur)
			elif joueur_est_a_bord:
				descendre_du_bateau(joueur)
			elif distance >= 6.0:
				print("Joueur trop loin pour monter (Distance > 6)")
		else:
			print("ERREUR : Nœud 'joueur' introuvable ! Vérifie tes groupes.")

func monter_dans_le_bateau(joueur):
	joueur_est_a_bord = true
	# On désactive la physique et on cache le joueur
	joueur.process_mode = Node.PROCESS_MODE_DISABLED
	joueur.visible = false
	print("--> ACTION : JOUEUR MONTÉ À BORD !")

func descendre_du_bateau(joueur):
	joueur_est_a_bord = false
	# On réactive le joueur et on le décale un peu pour qu'il ne soit pas coincé
	joueur.process_mode = Node.PROCESS_MODE_INHERIT
	joueur.visible = true
	joueur.global_position = self.global_position + Vector3(3, 1, 0)
	print("--> ACTION : JOUEUR DESCENDU !")
