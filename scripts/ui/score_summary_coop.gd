# =============================================================
# score_summary_coop.gd — COMPILATION DYNAMIQUE ET TRI DU PODIUM
# =============================================================
extends Control

@onready var gold_player: Label = $Background/gold_player
@onready var gold_score: Label = $Background/gold_player/score

@onready var silver_player: Label = $Background/silver_player
@onready var silver_score: Label = $Background/silver_player/score

@onready var bronze_player: Label = $Background/bronze_player
@onready var bronze_score: Label = $Background/bronze_player/score

@onready var podium_1: ColorRect = $Background/HBoxContainer/Podium_1
@onready var podium_2: ColorRect = $Background/HBoxContainer/Podium_2
@onready var podium_3: ColorRect = $Background/HBoxContainer/Podium_3

func _ready() -> void:
	var fx := AnimatedBackground.new()
	add_child(fx)
	move_child(fx, 0)
	
	_generate_podium()

func _generate_podium() -> void:
	var sm = ScoreManager
	var leaderboard = sm.players_stats.duplicate(true)
	
	# Compiler les scores finaux calculés avec la survie infinie
	for i in range(leaderboard.size()):
		leaderboard[i]["final_score"] = sm.get_player_total_score(i)
		
	# Trier par ordre décroissant (le plus gros score en premier)
	leaderboard.sort_custom(func(a, b): return a["final_score"] > b["final_score"])
	
	# Dissimuler les podiums vides (si moins de 3 joueurs connectés)
	gold_player.hide()
	podium_1.hide()
	silver_player.hide()
	podium_2.hide()
	bronze_player.hide()
	podium_3.hide()
	
	# 🥇 1ère PLACE : L'Or (#F3A912)
	if leaderboard.size() > 0:
		gold_player.text = leaderboard[0]["name"]
		gold_score.text = str(leaderboard[0]["final_score"])
		podium_1.color = Color.from_string("#F3A912", Color.GOLD)
		gold_player.show()
		podium_1.show()
		
	# 🥈 2ème PLACE : L'Argent (#E0E4E8)
	if leaderboard.size() > 1:
		silver_player.text = leaderboard[1]["name"]
		silver_score.text = str(leaderboard[1]["final_score"])
		podium_2.color = Color.from_string("#E0E4E8", Color.SILVER)
		silver_player.show()
		podium_2.show()
		
	# 🥉 3ème PLACE : Le Bronze (#C87541)
	if leaderboard.size() > 2:
		bronze_player.text = leaderboard[2]["name"]
		bronze_score.text = str(leaderboard[2]["final_score"])
		podium_3.color = Color.from_string("#C87541", Color.DARK_ORANGE)
		bronze_player.show()
		podium_3.show()
