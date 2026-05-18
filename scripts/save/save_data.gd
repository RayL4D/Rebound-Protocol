# =============================================================
# save_data.gd — Autoload singleton de sauvegarde
# Rebound Protocol
# =============================================================
# Deux couches de persistance — TOUTES deux par slot :
#
#   shop_upgrades  (Dict)  — upgrades achetées en boutique, propres à chaque slot.
#   coins, hp, level, checkpoint, position — données de partie.
#
# Catalogue des upgrades (CATALOG) : définit les stats de chaque
# amélioration. Utilisé par la boutique ET par Player/Shield.
# =============================================================

extends Node
signal slot_loaded
# ---------------------------------------------------------------
# user:// → stockage interne de l'app (Android, iOS, PC, etc.)
# PC     : %APPDATA%/Rebound Protocol/saves/  (Windows)
# Android: /data/data/com.votreapp/files/saves/
const SAVE_DIR  := "user://saves/"
const SAVE_FILE := "save_data.sav"   # Extension .sav — fichier chiffré
const MAX_SLOTS := 5

# Clé de chiffrement AES-256 (hardcodée dans le binaire).
# Changer avant release. Ne jamais committer en clair dans un dépôt public.
const _ENC_PASS := "rbp_AES_k3y_!R3b0und#2025_xK9mPqZ"

# Sel HMAC pour la vérification d'intégrité (anti-falsification).
const _HMAC_SALT := "rbp_hmac_s4lt_!integrity#check_v2"

var _save_path: String = ""

# ---------------------------------------------------------------
# Catalogue des améliorations permanentes
# ---------------------------------------------------------------
const CATALOG: Dictionary = {
	# ── JOUEUR ──────────────────────────────────────────────────
	"hp_max": {
		"cat": "joueur", "name_key": "SHOP_HP_MAX", "desc_key": "SHOP_HP_MAX_DESC",
		"max_tier": 6,
		"prices": [60, 95, 140, 200, 280, 390],
		"effect": 5.0,   # +5 HP par palier
	},
	"move_speed": {
		"cat": "joueur", "name_key": "SHOP_MOVE_SPEED", "desc_key": "SHOP_MOVE_SPEED_DESC",
		"max_tier": 5,
		"prices": [60, 100, 155, 230, 340],
		"effect": 0.05,  # +5 % par palier
	},
	"damage_reduction": {
		"cat": "joueur", "name_key": "SHOP_DMG_REDUCTION", "desc_key": "SHOP_DMG_REDUCTION_DESC",
		"max_tier": 5,
		"prices": [80, 130, 200, 305, 455],
		"effect": 0.05,  # -5 % dégâts reçus par palier
	},
	"pickup_radius": {
		"cat": "joueur", "name_key": "SHOP_PICKUP_RADIUS", "desc_key": "SHOP_PICKUP_RADIUS_DESC",
		"max_tier": 3,
		"prices": [45, 80, 130],
		"effect": 0.15,  # +15 % portée par palier
	},
	"dash_cooldown": {
		"cat": "joueur", "name_key": "SHOP_DASH_COOLDOWN", "desc_key": "SHOP_DASH_COOLDOWN_DESC",
		"max_tier": 5,
		"prices": [70, 115, 175, 255, 370],
		"effect": 0.10,  # -10 % cooldown dash par palier
	},
	"stomp_damage": {
		"cat": "joueur", "name_key": "SHOP_STOMP_DAMAGE", "desc_key": "SHOP_STOMP_DAMAGE_DESC",
		"max_tier": 4,
		"prices": [55, 90, 140, 205],
		"effect": 0.15,  # +15 % dégâts stomp par palier
	},
	# ── BOUCLIER ─────────────────────────────────────────────────
	"shield_size": {
		"cat": "bouclier", "name_key": "SHOP_SHIELD_SIZE", "desc_key": "SHOP_SHIELD_SIZE_DESC",
		"max_tier": 4,
		"prices": [75, 125, 200, 310],
		"effect": 0.08,  # +8 % rayon par palier
	},
	"shield_duration": {
		"cat": "bouclier", "name_key": "SHOP_SHIELD_DURATION", "desc_key": "SHOP_SHIELD_DURATION_DESC",
		"max_tier": 4,
		"prices": [65, 110, 175, 270],
		"effect": 0.10,  # +10 % durée parade par palier
	},
	"parry_damage": {
		"cat": "bouclier", "name_key": "SHOP_PARRY_DAMAGE", "desc_key": "SHOP_PARRY_DAMAGE_DESC",
		"max_tier": 6,
		"prices": [55, 90, 140, 210, 315, 475],
		"effect": 0.10,  # +10 % dégâts renvoi par palier
	},
	"parry_window": {
		"cat": "bouclier", "name_key": "SHOP_PARRY_WINDOW", "desc_key": "SHOP_PARRY_WINDOW_DESC",
		"max_tier": 3,
		"prices": [120, 210, 360],
		"effect": 1.0,   # +1 frame fenêtre critique par palier
	},
	"parry_heal": {
		"cat": "bouclier", "name_key": "SHOP_PARRY_HEAL", "desc_key": "SHOP_PARRY_HEAL_DESC",
		"max_tier": 3,
		"prices": [175, 310, 500],
		"effect": 1.0,   # +1 HP soigné par parade critique par palier
	},
	"reflect_speed": {
		"cat": "bouclier", "name_key": "SHOP_REFLECT_SPEED", "desc_key": "SHOP_REFLECT_SPEED_DESC",
		"max_tier": 4,
		"prices": [65, 110, 170, 260],
		"effect": 0.20,  # +20 % vitesse balle renvoyée par palier
	},
	# ── PASSIFS ──────────────────────────────────────────────────
	"hp_regen": {
		"cat": "passifs", "name_key": "SHOP_HP_REGEN", "desc_key": "SHOP_HP_REGEN_DESC",
		"max_tier": 3,
		"prices": [150, 260, 420],
		"effect": 1.0,   # palier 1→30s, 2→20s, 3→12s
	},
	"xp_bonus": {
		"cat": "passifs", "name_key": "SHOP_XP_BONUS", "desc_key": "SHOP_XP_BONUS_DESC",
		"max_tier": 5,
		"prices": [80, 130, 195, 280, 400],
		"effect": 0.10,  # +10 % XP par palier
	},
	"coin_bonus": {
		"cat": "passifs", "name_key": "SHOP_COIN_BONUS", "desc_key": "SHOP_COIN_BONUS_DESC",
		"max_tier": 4,
		"prices": [50, 90, 145, 215],
		"effect": 1.0,   # +1 pièce par ennemi vaincu par palier
	},
	"dash_armor": {
		"cat": "passifs", "name_key": "SHOP_DASH_ARMOR", "desc_key": "SHOP_DASH_ARMOR_DESC",
		"max_tier": 3,
		"prices": [200, 380, 620],
		"effect": 1.0,   # palier 1 = invincible pendant dash, 2 = +0.2s après, 3 = +0.4s après
	},
}

# ---------------------------------------------------------------
# Données runtime
# ---------------------------------------------------------------

## Slots de partie (MAX_SLOTS entrées). Chaque slot contient ses propres
## shop_upgrades — plus de données partagées entre parties.
var saves: Array = []

## Index du slot actif (−1 = aucun).
var active_slot: int = -1

## Mode d'accès à l'écran de sélection de slot.
## true = "Nouvelle partie" ; false = "Continuer"
var new_game_mode: bool = false


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# user:// est géré nativement par Godot sur toutes les plateformes
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_save_path = SAVE_DIR + SAVE_FILE
	_load_from_disk()


## Recharge toutes les données depuis le disque (sans toucher à active_slot).
## À appeler avant d'afficher un écran qui lit les infos des slots.
func reload_from_disk() -> void:
	_load_from_disk()


# =============================================================
# GESTION DES SLOTS
# =============================================================

func new_game(slot: int) -> void:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	saves[slot] = _empty_slot()
	active_slot = slot
	save_current()
	slot_loaded.emit()

func load_slot(slot: int) -> bool:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	# Recharger depuis le disque pour ignorer toute donnée en mémoire
	# accumulée depuis le dernier checkpoint (pièces, upgrades non sauvegardées).
	_load_from_disk()
	if not saves[slot].get("used", false):
		return false
	active_slot = slot
	slot_loaded.emit()
	return true


func delete_slot(slot: int) -> void:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	saves[slot] = _empty_slot()
	if active_slot == slot:
		active_slot = -1
	save_current()


func get_slot_info(slot: int) -> Dictionary:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	var s: Dictionary = saves[slot]
	return {
		"used":      s.get("used", false),
		"level":     s.get("level", ""),
		"timestamp": s.get("timestamp", 0),
		"coins":     s.get("coins", 0),
		"hp":        s.get("hp", 0),
	}


# =============================================================
# ACCÈS AU SLOT ACTIF — pièces, checkpoint, niveau, HP
# =============================================================

func get_coins() -> int:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return 0
	return int(saves[active_slot].get("coins", 0))


func add_coins(amount: int) -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	# Mise à jour en mémoire uniquement — persisté au prochain checkpoint.
	saves[active_slot]["coins"] = int(saves[active_slot].get("coins", 0)) + amount


func spend_coins(amount: int) -> bool:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return false
	var current := int(saves[active_slot].get("coins", 0))
	if current < amount:
		return false
	# Mise à jour en mémoire uniquement — persisté au prochain checkpoint.
	saves[active_slot]["coins"] = current - amount
	return true


func set_checkpoint(checkpoint_id: String) -> void:
	_active()["checkpoint_id"] = checkpoint_id


func get_checkpoint() -> String:
	return _active().get("checkpoint_id", "")


func set_current_level(level_name: String) -> void:
	_active()["level"] = level_name


func get_current_level() -> String:
	return _active().get("level", "")


func set_player_hp(hp: int) -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	saves[active_slot]["hp"] = hp


func get_player_hp() -> int:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return 0
	return int(saves[active_slot].get("hp", 0))


func set_player_position(pos: Vector3) -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	saves[active_slot]["pos_x"] = pos.x
	saves[active_slot]["pos_y"] = pos.y
	saves[active_slot]["pos_z"] = pos.z


func get_player_position() -> Vector3:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return Vector3.ZERO
	var x := float(saves[active_slot].get("pos_x", 0.0))
	var y := float(saves[active_slot].get("pos_y", 0.0))
	var z := float(saves[active_slot].get("pos_z", 0.0))
	if x == 0.0 and y == 0.0 and z == 0.0:
		return Vector3.ZERO
	return Vector3(x, y, z)

func get_xp() -> int:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return 0
	return int(saves[active_slot].get("xp", 0))

func get_xp_level() -> int:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return 0
	return int(saves[active_slot].get("xp_level", 0))

## Met à jour l'XP en mémoire (sans écrire sur disque).
## La persistance sur disque se fait au save_point via save_current().
func set_xp(xp: int, lvl: int) -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	saves[active_slot]["xp"]       = xp
	saves[active_slot]["xp_level"] = lvl


func get_acquired_skills() -> Array:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return []
	return saves[active_slot].get("acquired_skills", []).duplicate()


## Met à jour les skills acquis en mémoire (sans écrire sur disque).
## La persistance sur disque se fait au save_point via save_current().
func set_acquired_skills(skills: Array) -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	saves[active_slot]["acquired_skills"] = skills.duplicate()


func get_competences() -> Dictionary:
	return _active().get("competences", {})


func set_competence(key: String, value: Variant) -> void:
	_active()["competences"][key] = value
	save_current()


# =============================================================
# BOUTIQUE — upgrades par slot
# =============================================================

func get_upgrade_tier(upgrade_id: String) -> int:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return 0
	var upgrades: Dictionary = saves[active_slot].get("shop_upgrades", {})
	return int(upgrades.get(upgrade_id, 0))


func get_upgrade_value(upgrade_id: String) -> float:
	var tier := get_upgrade_tier(upgrade_id)
	var entry: Dictionary = CATALOG.get(upgrade_id, {})
	return float(tier) * entry.get("effect", 0.0)


func get_next_tier_price(upgrade_id: String) -> int:
	var entry: Dictionary = CATALOG.get(upgrade_id, {})
	var tier  := get_upgrade_tier(upgrade_id)
	if tier >= entry.get("max_tier", 0):
		return -1
	var prices: Array = entry.get("prices", [])
	if tier >= prices.size():
		return -1
	return prices[tier]


func buy_upgrade(upgrade_id: String) -> bool:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return false
	var price := get_next_tier_price(upgrade_id)
	if price < 0:
		return false
	if not spend_coins(price):
		return false
	if not saves[active_slot].has("shop_upgrades"):
		saves[active_slot]["shop_upgrades"] = {}
	# Mise à jour en mémoire uniquement — persisté au prochain checkpoint.
	saves[active_slot]["shop_upgrades"][upgrade_id] = get_upgrade_tier(upgrade_id) + 1
	return true


func reset_shop() -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	saves[active_slot]["shop_upgrades"] = {}
	save_current()


# =============================================================
# PERSISTANCE — chiffrement AES-256 + vérification HMAC
# =============================================================

## Calcule le HMAC-SHA256 d'une chaîne avec le sel secret.
## Utilisé pour détecter toute falsification du fichier.
func _compute_hmac(payload: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((payload + _HMAC_SALT).to_utf8_buffer())
	return ctx.finish().hex_encode()


func save_current() -> void:
	if active_slot >= 0:
		_active()["timestamp"] = int(Time.get_unix_time_from_system())
		_active()["used"] = true

	# 1. Construire le payload JSON
	var payload := JSON.stringify({"version": 2, "saves": saves})

	# 2. Calculer la signature HMAC du payload
	var sig := _compute_hmac(payload)

	# 3. Écrire le tout chiffré avec AES-256
	var file := FileAccess.open_encrypted_with_pass(_save_path, FileAccess.WRITE, _ENC_PASS)
	if file == null:
		push_error("SaveData : impossible d'écrire " + _save_path)
		return
	file.store_string(JSON.stringify({"sig": sig, "payload": payload}))
	file.close()


func _load_from_disk() -> void:
	saves.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		saves[i] = _empty_slot()

	if not FileAccess.file_exists(_save_path):
		# Vérifier si un ancien fichier .json non chiffré existe (migration)
		var old_path := _save_path.replace(".sav", ".json")
		if FileAccess.file_exists(old_path):
			_migrate_plain_json(old_path)
		return

	# 1. Lire le fichier chiffré
	var file := FileAccess.open_encrypted_with_pass(_save_path, FileAccess.READ, _ENC_PASS)
	if file == null:
		push_error("SaveData : impossible de déchiffrer " + _save_path + " — fichier corrompu ou mauvaise clé.")
		return

	var raw := file.get_as_text()
	file.close()

	# 2. Parser l'enveloppe {sig, payload}
	var envelope = JSON.parse_string(raw)
	if envelope == null or not envelope is Dictionary \
			or not envelope.has("sig") or not envelope.has("payload"):
		push_error("SaveData : format invalide — réinitialisation.")
		return

	# 3. Vérifier le HMAC — si la signature ne correspond pas, le fichier a été falsifié
	var payload: String = envelope["payload"]
	var expected_sig := _compute_hmac(payload)
	if envelope["sig"] != expected_sig:
		push_error("SaveData : signature invalide — sauvegarde falsifiée ou corrompue, réinitialisation.")
		# On repart de zéro : ne pas charger des données trafiquées
		return

	# 4. Parser le payload validé
	var parsed = JSON.parse_string(payload)
	if parsed == null or not parsed is Dictionary:
		push_error("SaveData : payload corrompu — réinitialisation.")
		return

	var file_version := int(parsed.get("version", 1))
	var raw_saves    = parsed.get("saves", [])

	for i in MAX_SLOTS:
		if i < raw_saves.size() and raw_saves[i] is Dictionary:
			saves[i] = _merge_slot(raw_saves[i])
		else:
			saves[i] = _empty_slot()

	# Migration version 1 → 2
	if file_version < 2:
		for i in MAX_SLOTS:
			saves[i]["shop_upgrades"] = {}
		save_current()


## Migration : convertit un ancien fichier JSON non chiffré vers le nouveau format chiffré.
func _migrate_plain_json(old_path: String) -> void:
	var file := FileAccess.open(old_path, FileAccess.READ)
	if file == null:
		return
	var raw := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(raw)
	if parsed == null or not parsed is Dictionary:
		return

	push_warning("SaveData : migration de l'ancien fichier JSON non chiffré vers " + _save_path)

	var raw_saves = parsed.get("saves", [])
	for i in MAX_SLOTS:
		if i < raw_saves.size() and raw_saves[i] is Dictionary:
			saves[i] = _merge_slot(raw_saves[i])
			saves[i]["shop_upgrades"] = {}   # Effacer les upgrades de l'ancien format
		else:
			saves[i] = _empty_slot()

	# Réécrire dans le nouveau format chiffré
	save_current()
	# Supprimer l'ancien fichier (globalize_path pour obtenir le chemin absolu réel)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))


func _empty_slot() -> Dictionary:
	return {
		"used":          false,
		"coins":         0,
		"shop_upgrades": {},
		"competences":   {},
		"level":         "",
		"checkpoint_id": "",
		"hp":            0,
		"timestamp":     0,
		"pos_x":         0.0,
		"pos_y":         0.0,
		"pos_z":         0.0,
		"xp":            0,
		"xp_level":      0,
		"acquired_skills": [],
	}


func _merge_slot(loaded: Dictionary) -> Dictionary:
	var base := _empty_slot()
	for key in base.keys():
		if loaded.has(key):
			base[key] = loaded[key]
	return base


func _active() -> Dictionary:
	assert(active_slot >= 0 and active_slot < MAX_SLOTS,
		"SaveData : aucun slot actif — appelle new_game() ou load_slot() d'abord.")
	return saves[active_slot]
