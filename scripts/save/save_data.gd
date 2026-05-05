# =============================================================
# save_data.gd — Autoload singleton de sauvegarde
# Rebound Protocol
# =============================================================
# Deux couches de persistance :
#
#   shop_upgrades  (Dict)  — permanent, commun à toutes les parties.
#                            Clé : upgrade_id   Valeur : palier acheté (int)
#
#   saves          (Array) — 5 slots de partie.
#                            Chaque slot : coins, competences, level,
#                            checkpoint_id, hp, timestamp
#
# Catalogue des upgrades (CATALOG) : définit les stats de chaque
# amélioration permanente. Utilisé par la boutique ET par Player/Shield
# pour appliquer les effets en jeu.
# =============================================================

extends Node

# ---------------------------------------------------------------
const SAVE_PATH := "user://save_data.json"
const MAX_SLOTS := 5

# ---------------------------------------------------------------
# Catalogue des améliorations permanentes
# Clé          : id unique (String)
# cat          : "joueur" | "bouclier" | "passifs"
# name_key     : clé de traduction pour le nom
# desc_key     : clé de traduction pour la description
# max_tier     : palier maximum achetable
# prices       : coût de chaque palier (array, index = palier 0-based)
# effect       : valeur par palier (float, interprétée selon l'upgrade)
# ---------------------------------------------------------------
const CATALOG: Dictionary = {
	# ── JOUEUR ──────────────────────────────────────────────────
	"hp_max": {
		"cat": "joueur", "name_key": "SHOP_HP_MAX", "desc_key": "SHOP_HP_MAX_DESC",
		"max_tier": 10,
		"prices": [50, 75, 105, 145, 195, 255, 325, 410, 510, 635],
		"effect": 1.0,   # +1 HP max par palier
	},
	"move_speed": {
		"cat": "joueur", "name_key": "SHOP_MOVE_SPEED", "desc_key": "SHOP_MOVE_SPEED_DESC",
		"max_tier": 5,
		"prices": [60, 100, 155, 230, 345],
		"effect": 0.05,  # +5 % vitesse par palier
	},
	"damage_reduction": {
		"cat": "joueur", "name_key": "SHOP_DMG_REDUCTION", "desc_key": "SHOP_DMG_REDUCTION_DESC",
		"max_tier": 5,
		"prices": [80, 130, 200, 305, 460],
		"effect": 0.05,  # −5 % dégâts reçus par palier
	},
	"pickup_radius": {
		"cat": "joueur", "name_key": "SHOP_PICKUP_RADIUS", "desc_key": "SHOP_PICKUP_RADIUS_DESC",
		"max_tier": 5,
		"prices": [40, 70, 110, 170, 260],
		"effect": 0.20,  # +20 % rayon de collecte par palier
	},
	# ── BOUCLIER ─────────────────────────────────────────────────
	"shield_size": {
		"cat": "bouclier", "name_key": "SHOP_SHIELD_SIZE", "desc_key": "SHOP_SHIELD_SIZE_DESC",
		"max_tier": 5,
		"prices": [70, 110, 165, 250, 375],
		"effect": 0.08,  # +8 % rayon bouclier par palier
	},
	"shield_duration": {
		"cat": "bouclier", "name_key": "SHOP_SHIELD_DURATION", "desc_key": "SHOP_SHIELD_DURATION_DESC",
		"max_tier": 5,
		"prices": [60, 100, 150, 225, 340],
		"effect": 0.10,  # +10 % durée activation par palier
	},
	"parry_damage": {
		"cat": "bouclier", "name_key": "SHOP_PARRY_DAMAGE", "desc_key": "SHOP_PARRY_DAMAGE_DESC",
		"max_tier": 8,
		"prices": [50, 80, 120, 175, 250, 355, 500, 700],
		"effect": 0.10,  # +10 % dégâts balles renvoyées par palier
	},
	"parry_window": {
		"cat": "bouclier", "name_key": "SHOP_PARRY_WINDOW", "desc_key": "SHOP_PARRY_WINDOW_DESC",
		"max_tier": 3,
		"prices": [120, 200, 350],
		"effect": 1.0,   # +1 frame de fenêtre critique par palier
	},
	# ── PASSIFS ──────────────────────────────────────────────────
	"hp_regen": {
		"cat": "passifs", "name_key": "SHOP_HP_REGEN", "desc_key": "SHOP_HP_REGEN_DESC",
		"max_tier": 3,
		"prices": [150, 250, 400],
		"effect": 1.0,   # palier → intervalle regen (1=30s, 2=20s, 3=12s)
	},
	"xp_bonus": {
		"cat": "passifs", "name_key": "SHOP_XP_BONUS", "desc_key": "SHOP_XP_BONUS_DESC",
		"max_tier": 5,
		"prices": [90, 140, 200, 285, 405],
		"effect": 0.10,  # +10 % XP par ennemi tué par palier
	},
}

# ---------------------------------------------------------------
# Données runtime
# ---------------------------------------------------------------

## Améliorations permanentes achetées (toutes parties confondues).
## Clé : upgrade_id   Valeur : palier acheté (0 = non acheté)
var shop_upgrades: Dictionary = {}

## Slots de partie (MAX_SLOTS entrées).
var saves: Array = []

## Index du slot actif (−1 = aucun).
var active_slot: int = -1

## Mode d'accès à l'écran de sélection de slot.
## true = "Nouvelle partie" (montrer bouton nouvelle partie)
## false = "Continuer" (montrer bouton continuer, griser les slots vides)
var new_game_mode: bool = false


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_load_from_disk()


# =============================================================
# GESTION DES SLOTS
# =============================================================

## Crée (ou réinitialise) le slot et le sélectionne comme actif.
func new_game(slot: int) -> void:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	saves[slot] = _empty_slot()
	active_slot = slot
	save_current()


## Charge un slot existant. Retourne false si le slot est vide.
func load_slot(slot: int) -> bool:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	if not saves[slot].get("used", false):
		return false
	active_slot = slot
	return true


## Supprime un slot (ex. "Nouvelle partie" sur slot occupé).
func delete_slot(slot: int) -> void:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot invalide")
	saves[slot] = _empty_slot()
	if active_slot == slot:
		active_slot = -1
	save_current()


## Infos résumées pour l'écran de sélection de slot.
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
	saves[active_slot]["coins"] = int(saves[active_slot].get("coins", 0)) + amount
	save_current()


## Tente de dépenser `amount` pièces. Retourne true si OK.
func spend_coins(amount: int) -> bool:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return false
	var current := int(saves[active_slot].get("coins", 0))
	if current < amount:
		return false
	saves[active_slot]["coins"] = current - amount
	save_current()
	return true


func set_checkpoint(checkpoint_id: String) -> void:
	_active()["checkpoint_id"] = checkpoint_id
	save_current()


func get_checkpoint() -> String:
	return _active().get("checkpoint_id", "")


func set_current_level(level_name: String) -> void:
	_active()["level"] = level_name
	save_current()


func get_current_level() -> String:
	return _active().get("level", "")


func set_player_hp(hp: int) -> void:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return
	saves[active_slot]["hp"] = hp
	save_current()


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
	save_current()


func get_player_position() -> Vector3:
	if active_slot < 0 or active_slot >= MAX_SLOTS:
		return Vector3.ZERO
	var x := float(saves[active_slot].get("pos_x", 0.0))
	var y := float(saves[active_slot].get("pos_y", 0.0))
	var z := float(saves[active_slot].get("pos_z", 0.0))
	# Retourne ZERO si aucune position n'a été sauvegardée
	if x == 0.0 and y == 0.0 and z == 0.0:
		return Vector3.ZERO
	return Vector3(x, y, z)


func get_competences() -> Dictionary:
	return _active().get("competences", {})


func set_competence(key: String, value: Variant) -> void:
	_active()["competences"][key] = value
	save_current()


# =============================================================
# BOUTIQUE PERMANENTE
# =============================================================

## Palier actuellement acheté pour un upgrade (0 = pas acheté).
func get_upgrade_tier(upgrade_id: String) -> int:
	return shop_upgrades.get(upgrade_id, 0)


## Valeur effective de l'upgrade au palier actuel.
## ex. "hp_max" tier 3 → 3 * 1.0 = 3 HP bonus
func get_upgrade_value(upgrade_id: String) -> float:
	var tier := get_upgrade_tier(upgrade_id)
	var entry: Dictionary = CATALOG.get(upgrade_id, {})
	return float(tier) * entry.get("effect", 0.0)


## Coût du prochain palier (−1 = déjà au max).
func get_next_tier_price(upgrade_id: String) -> int:
	var entry: Dictionary = CATALOG.get(upgrade_id, {})
	var tier  := get_upgrade_tier(upgrade_id)
	if tier >= entry.get("max_tier", 0):
		return -1
	var prices: Array = entry.get("prices", [])
	if tier >= prices.size():
		return -1
	return prices[tier]


## Achète le prochain palier si le joueur a assez de pièces.
## Retourne true si l'achat a réussi.
func buy_upgrade(upgrade_id: String) -> bool:
	var price := get_next_tier_price(upgrade_id)
	if price < 0:
		return false          # déjà au max
	if not spend_coins(price):
		return false          # pas assez de pièces
	shop_upgrades[upgrade_id] = get_upgrade_tier(upgrade_id) + 1
	save_current()
	return true


func reset_shop() -> void:
	shop_upgrades.clear()
	save_current()


# =============================================================
# PERSISTANCE JSON
# =============================================================

func save_current() -> void:
	if active_slot >= 0:
		_active()["timestamp"] = int(Time.get_unix_time_from_system())
		_active()["used"] = true

	var data := {
		"version":       1,
		"shop_upgrades": shop_upgrades,
		"saves":         saves,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveData : impossible d'écrire " + SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _load_from_disk() -> void:
	saves.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		saves[i] = _empty_slot()

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveData : impossible de lire " + SAVE_PATH)
		return

	var raw     := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(raw)
	if parsed == null or not parsed is Dictionary:
		push_error("SaveData : fichier corrompu — réinitialisation.")
		return

	shop_upgrades = parsed.get("shop_upgrades", {})

	var raw_saves = parsed.get("saves", [])
	for i in MAX_SLOTS:
		if i < raw_saves.size() and raw_saves[i] is Dictionary:
			saves[i] = _merge_slot(raw_saves[i])
		else:
			saves[i] = _empty_slot()


func _empty_slot() -> Dictionary:
	return {
		"used":          false,
		"coins":         0,
		"competences":   {},
		"level":         "",
		"checkpoint_id": "",
		"hp":            0,
		"timestamp":     0,
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
