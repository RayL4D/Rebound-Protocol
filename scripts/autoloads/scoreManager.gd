# =============================================================
# ScoreManager.gd (Autoload)
# =============================================================
extends Node

var is_tracking: bool = false

# --- Statistiques ---
var enemies_killed: int = 0
var waves_cleared: int = 0
var time_elapsed: float = 0.0

# --- Barème (Poids du score) ---
const PTS_PER_KILL: int = 50
const PTS_PER_WAVE: int = 500
const PTS_PER_SECOND: int = 10

func _process(delta: float) -> void:
	# Le temps tourne uniquement si on est dans un niveau
	if is_tracking:
		time_elapsed += delta

# --- CONTRÔLE DU NIVEAU ---
func start_level() -> void:
	enemies_killed = 0
	waves_cleared = 0
	time_elapsed = 0.0
	is_tracking = true

func end_level() -> void:
	is_tracking = false
	# Ici, tu peux charger ta scène de score
	get_tree().change_scene_to_file("res://scenes/ui/score_summary.tscn")

# --- ÉVÉNEMENTS ---
func add_kill() -> void:
	if is_tracking: enemies_killed += 1

func add_wave() -> void:
	if is_tracking: waves_cleared += 1

# --- CALCULS POUR L'UI ---
func get_score_breakdown() -> Array:
	# Retourne un tableau structuré pour générer l'UI dynamiquement
	return [
		{
			"name": tr("UI_STAT_ENEMIES"), 
			"value": enemies_killed, 
			"score": enemies_killed * PTS_PER_KILL
		},
		{
			"name": tr("UI_STAT_WAVES"), 
			"value": waves_cleared, 
			"score": waves_cleared * PTS_PER_WAVE
		},
		{
			"name": tr("UI_STAT_TIME"), 
			"value": int(time_elapsed), 
			"score": int(time_elapsed) * PTS_PER_SECOND
		}
	]

func get_total_score() -> int:
	var total := 0
	for item in get_score_breakdown():
		total += item["score"]
	return total
