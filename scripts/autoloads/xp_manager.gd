# =============================================================
# XpManager — Autoload singleton
# Rebound Protocol
# =============================================================
# Gère l'XP du joueur, les paliers de niveau, le déclenchement
# de l'UI de choix de compétence et les multiplicateurs de stats
# issus des compétences acquises.
#
# UTILISATION :
#   XpManager.add_xp(10)            # appelé à la mort d'un ennemi
#   XpManager.has_skill("xxx")      # interrogé par Shield, BulletReflected…
#   XpManager.return_speed_mult     # multiplicateur global (lu par BulletReflected)
#   XpManager.reset_for_new_run()   # appelé en début de run (nouvelle partie)
# =============================================================
extends Node

# --- XP & niveau -----------------------------------------------
var current_xp:  int  = 0
var xp_to_next:  int  = 0
var level:       int  = 0
var _ui_pending: bool = false   # anti-double déclenchement si 2 kills simultanés

# --- Compétences acquises (IDs) --------------------------------
var acquired_skills: Array[String] = []

# --- Multiplicateurs globaux (mis à jour par apply_skill) ------
# Accessibles depuis n'importe quel script sans chercher le joueur.
var return_speed_mult:       float = 1.0   # return_speed_boost   (+15% / stack)
var return_damage_mult:      float = 1.0   # return_damage_boost  (+10% / stack)
var shield_radius_mult:      float = 1.0   # shield_size_boost    (+10% / stack)
var shield_duration_mult:    float = 1.0   # shield_duration_boost(+20% / stack)
var parry_window_mult:       float = 1.0   # parry_window_boost   (+20% / stack)
var stomp_mult:              float = 1.0   # stomp_damage_boost   (×2 / stack)
var enemy_bullet_speed_mult:   float = 1.0   # enemy_slowdown
var _phantom_bullet_toggle:    bool  = false # alterné par BulletReflected pour phantom_bullet       (×0.85 / stack)

# --- Signaux ---------------------------------------------------
signal xp_changed(current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int)

# --- Script de l'UI (lazy-loaded) ------------------------------
const _UI_SCRIPT_PATH := "res://scripts/ui/skill_pick_ui.gd"


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	xp_to_next   = _threshold(0)
	
	# On connecte le signal pour être prévenu à chaque chargement de partie
	SaveData.slot_loaded.connect(sync_with_save)

	# (Optionnel) Restaurer l'XP si une scène est lancée directement (débogage)
	if SaveData.active_slot >= 0:
		sync_with_save()

# =============================================================
# SYNCHRONISATION
# =============================================================

## Met à jour XpManager avec les données en mémoire de SaveData.
## Réinitialise d'abord tout, puis restaure ce qui avait été sauvegardé
## (skills vides si le joueur n'est pas passé par un save_point).
func sync_with_save() -> void:
	current_xp = SaveData.get_xp()
	level      = SaveData.get_xp_level()
	xp_to_next = _threshold(level)

	# Réinitialiser multiplicateurs + skills avant de restaurer
	acquired_skills.clear()
	return_speed_mult       = 1.0
	return_damage_mult      = 1.0
	shield_radius_mult      = 1.0
	shield_duration_mult    = 1.0
	parry_window_mult       = 1.0
	stomp_mult              = 1.0
	enemy_bullet_speed_mult = 1.0
	_phantom_bullet_toggle  = false

	# Restaurer les skills sauvegardés (vide si pas de save_point depuis ce run)
	for id: String in SaveData.get_acquired_skills():
		if SkillCatalogue.SKILLS.has(id):
			acquired_skills.append(id)
			_update_multipliers(id)

	xp_changed.emit(current_xp, xp_to_next)
	
	
# =============================================================
# API PUBLIQUE
# =============================================================

## Ajoute de l'XP au joueur (appelé depuis Enemy._die()).
## Applique le bonus XP de la boutique si disponible.
func add_xp(amount: int) -> void:
	# Bonus XP upgrade boutique (+10 % par palier)
	if SaveData.active_slot >= 0:
		var mult := 1.0 + SaveData.get_upgrade_value("xp_bonus")
		amount = int(round(float(amount) * mult))

	current_xp += amount
	SaveData.set_xp(current_xp, level)   # mise à jour en mémoire (persisté au save_point)
	xp_changed.emit(current_xp, xp_to_next)
	_check_level_up()


## Retourne true si la compétence `id` a déjà été acquise.
func has_skill(id: String) -> bool:
	return acquired_skills.has(id)


## Applique une compétence (appelé par SkillPickUI après le choix du joueur).
func apply_skill(id: String) -> void:
	if not SkillCatalogue.SKILLS.has(id):
		push_warning("XpManager: compétence inconnue '%s'." % id)
		return

	acquired_skills.append(id)
	_update_multipliers(id)
	SaveData.set_acquired_skills(acquired_skills)   # persisté au prochain save_point

	# Notifier le joueur pour qu'il rafraîchisse bouclier / stomp / dash
	var player := _get_player()
	if player != null and player.has_method("on_skill_acquired"):
		player.on_skill_acquired(id)


## Remet l'XP, le niveau et les compétences à zéro (début de run).
func reset_for_new_run() -> void:
	current_xp            = 0
	level                 = 0
	xp_to_next            = _threshold(0)
	_ui_pending           = false
	acquired_skills.clear()
	return_speed_mult       = 1.0
	return_damage_mult      = 1.0
	shield_radius_mult      = 1.0
	shield_duration_mult    = 1.0
	parry_window_mult       = 1.0
	stomp_mult              = 1.0
	enemy_bullet_speed_mult = 1.0
	_phantom_bullet_toggle  = false
	SaveData.set_xp(0, 0)
	SaveData.set_acquired_skills([])
	xp_changed.emit(0, xp_to_next)


# =============================================================
# INTERNE — level-up
# =============================================================

func _check_level_up() -> void:
	if _ui_pending:
		return
	if current_xp < xp_to_next:
		return

	current_xp -= xp_to_next
	level      += 1
	xp_to_next  = _threshold(level)
	SaveData.set_xp(current_xp, level)   # persisté au prochain save_point

	# On prévient le HUD qu'on vient de consommer de l'XP et de passer un niveau !
	xp_changed.emit(current_xp, xp_to_next)

	leveled_up.emit(level)
	_show_skill_pick()


## Seuil d'XP pour passer au niveau `lvl`.
## Courbe progressive : 50 XP pour le niveau 1, +30 XP par niveau.
func _threshold(lvl: int) -> int:
	return 50 + lvl * 30


func _show_skill_pick() -> void:
	_ui_pending = true
	var skills  := SkillCatalogue.draw_two(acquired_skills)
	var ui_gd: GDScript = load(_UI_SCRIPT_PATH)
	if ui_gd == null:
		push_error("XpManager: impossible de charger '%s'." % _UI_SCRIPT_PATH)
		_ui_pending = false
		return
	var ui: Node = ui_gd.new()
	get_tree().root.add_child(ui)
	ui.setup(level, skills)
	ui.skill_chosen.connect(_on_skill_chosen.bind(ui))


func _on_skill_chosen(id: String, ui: Node) -> void:
	apply_skill(id)
	_ui_pending = false
	# Un level-up peut s'être accumulé pendant le choix → chaîner
	_check_level_up()


# =============================================================
# INTERNE — multiplicateurs
# =============================================================

func _update_multipliers(id: String) -> void:
	match id:
		"return_speed_boost":    return_speed_mult       *= 1.15
		"return_damage_boost":   return_damage_mult      *= 1.10
		"shield_size_boost":     shield_radius_mult      *= 1.10
		"shield_duration_boost": shield_duration_mult    *= 1.20
		"parry_window_boost":    parry_window_mult       *= 1.20
		"stomp_damage_boost":    stomp_mult              *= 2.0
		"enemy_slowdown":        enemy_bullet_speed_mult *= 0.85


func _get_player() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("player")
