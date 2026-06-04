# =============================================================
# ScoreManager.gd (Autoload) - Version Vagues Infinies & Survie
# =============================================================
extends Node

var is_tracking: bool = false

# --- Statistiques Globales ---
var waves_cleared: int = 0
var time_elapsed: float = 0.0

# --- Statistiques Individuelles ---
var players_stats: Array[Dictionary] = []
var current_viewing_player: int = 0 

# --- Barème de points de base ---
const PTS_PER_KILL: int = 50
const PTS_PER_WAVE: int = 500

# ⏱️ BARÈME DE TEMPS SURVÉCU (Plus on reste en vie, plus on accumule)
const PTS_PER_SECOND_SURVIVED: int = 15  

# 💖 BONUS DE RÉSISTANCE (Dégressif à chaque mort)
const MAX_SURVIVAL_BONUS: int = 2500     # Score max si 0 mort
const PENALTY_PER_DEATH: int = 500       # Ce que le joueur perd à chaque mort

func _process(delta: float) -> void:
	if is_tracking:
		time_elapsed += delta
		# Accumuler le temps de survie uniquement pour les joueurs encore actifs
		for p in players_stats:
			if p["is_alive"]:
				p["survival_time"] += delta

# --- CONTRÔLE DU NIVEAU ---
func start_level(num_players: int = 1) -> void:
	waves_cleared = 0
	time_elapsed = 0.0
	current_viewing_player = 0
	players_stats.clear()
	
	for i in num_players:
		players_stats.append({
			"id": i,
			"name": "JOUEUR " + str(i + 1),
			"enemies_killed": 0,
			"deaths": 0,
			"survival_time": 0.0,
			"is_alive": true
		})
	is_tracking = true

func end_level() -> void:
	is_tracking = false
	current_viewing_player = 0
	get_tree().change_scene_to_file("res://scenes/ui/score_summary.tscn")

# --- ENREGISTREMENT DES ÉVÉNEMENTS ---
func add_kill(player_index: int = 0) -> void:
	if is_tracking and player_index < players_stats.size():
		players_stats[player_index]["enemies_killed"] += 1

func add_wave() -> void:
	if is_tracking: 
		waves_cleared += 1

# À appeler dès qu'un joueur meurt
func register_player_death(player_index: int) -> void:
	if is_tracking and player_index < players_stats.size():
		var p = players_stats[player_index]
		p["deaths"] += 1
		
		# S'il s'agit d'une mort définitive pour le reste de la partie/vague :
		# p["is_alive"] = false

# À appeler si le joueur réapparaît (Utile si p["is_alive"] a été passé à false)
func register_player_respawn(player_index: int) -> void:
	if is_tracking and player_index < players_stats.size():
		players_stats[player_index]["is_alive"] = true

# --- CALCUL DU SCORE COMPLET ---
func get_player_total_score(player_index: int) -> int:
	if player_index >= players_stats.size(): 
		return 0
		
	var p = players_stats[player_index]
	
	# 1. Éliminations & Vagues
	var kill_score = p["enemies_killed"] * PTS_PER_KILL
	var wave_score = waves_cleared * PTS_PER_WAVE
	
	# 2. Points de temps survécu
	var time_score = int(p["survival_time"]) * PTS_PER_SECOND_SURVIVED
	
	# 3. Bonus de résistance (Dégressif mais ne descend jamais sous 0)
	var survival_bonus = max(0, MAX_SURVIVAL_BONUS - (p["deaths"] * PENALTY_PER_DEATH))
	
	return kill_score + wave_score + time_score + survival_bonus
