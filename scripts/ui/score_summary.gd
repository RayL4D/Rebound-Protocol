# =============================================================
# score_summary.gd — VERSION CORRIGÉE AVEC DEBUG
# =============================================================
extends CanvasLayer

@onready var rows_container: VBoxContainer = $Panel/VBoxContainer/RowsContainer
@onready var total_label: Label = $Panel/VBoxContainer/TotalLabel
@onready var btn_continue: Button = $Panel/VBoxContainer/BtnContinue

func _ready() -> void:
	print("=== SCORE SUMMARY : _ready() appelé ===")
	
	# Afficher le curseur
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Mettre le jeu en pause
	get_tree().paused = true
	
	# Vérifier que les nœuds existent
	if not rows_container:
		push_error("❌ RowsContainer introuvable!")
	if not total_label:
		push_error("❌ TotalLabel introuvable!")
	if not btn_continue:
		push_error("❌ BtnContinue introuvable!")
	
	# Vérifier que ScoreManager existe
	if not has_node("/root/ScoreManager"):
		push_error("❌ ScoreManager n'existe pas dans l'autoload!")
		return
	
	print("✅ Tous les nœuds trouvés, population du score...")
	_populate_score()
	
	# Connecter le bouton
	if btn_continue:
		btn_continue.pressed.connect(_on_continue)

func _populate_score() -> void:
	print("=== DÉBUT _populate_score() ===")
	
	# 1. On vide le conteneur par sécurité
	for child in rows_container.get_children():
		child.queue_free()
	
	# 2. On récupère les détails depuis le Singleton
	var breakdown = ScoreManager.get_score_breakdown()
	print("📊 Breakdown reçu : ", breakdown)
	
	# 3. On crée une ligne pour chaque statistique
	for item in breakdown:
		print("  • Création ligne : ", item["name"], " = ", item["value"], " (", item["score"], " pts)")
		
		var row := HBoxContainer.new()
		
		# Nom de la stat (ex: Ennemis tués)
		var name_lbl := Label.new()
		name_lbl.text = item["name"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 24)
		
		# Valeur de la stat (ex: 5)
		var val_lbl := Label.new()
		val_lbl.text = "x" + str(item["value"])
		val_lbl.custom_minimum_size = Vector2(100, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 24)
		
		# Points rapportés (ex: +250)
		var score_lbl := Label.new()
		score_lbl.text = "+ " + str(item["score"])
		score_lbl.custom_minimum_size = Vector2(120, 0)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score_lbl.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
		score_lbl.add_theme_font_size_override("font_size", 24)
		
		row.add_child(name_lbl)
		row.add_child(val_lbl)
		row.add_child(score_lbl)
		
		rows_container.add_child(row)
	
	# 4. On affiche le grand total
	var total_score = ScoreManager.get_total_score()
	total_label.text = "SCORE TOTAL : " + str(total_score)
	print("✅ Score total affiché : ", total_score)
	print("=== FIN _populate_score() ===")

func _on_continue() -> void:
	print("🔘 Bouton continuer pressé")
	get_tree().paused = false
	
	# Réinitialiser le tracking
	ScoreManager.is_tracking = false
	
	# Retour au menu principal
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
