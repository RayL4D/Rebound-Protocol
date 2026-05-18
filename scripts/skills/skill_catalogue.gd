# =============================================================
# SkillCatalogue — Catalogue de toutes les compétences du jeu
# Rebound Protocol
# =============================================================
# Utilisation (depuis n'importe où) :
#   var drawn := SkillCatalogue.draw_two(XpManager.acquired_skills)
#   # Retourne un Array de 2 dictionnaires { id, name, description, rarity }
# =============================================================
class_name SkillCatalogue

# --- Raretés ---------------------------------------------------
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES: Dictionary = {
	Rarity.COMMON:    "Commun",
	Rarity.UNCOMMON:  "Peu Commun",
	Rarity.RARE:      "Rare",
	Rarity.EPIC:      "Épique",
	Rarity.LEGENDARY: "Légendaire",
}

const RARITY_COLORS: Dictionary = {
	Rarity.COMMON:    Color(0.72, 0.72, 0.72),   # gris
	Rarity.UNCOMMON:  Color(0.20, 0.85, 0.30),   # vert
	Rarity.RARE:      Color(0.20, 0.55, 1.00),   # bleu
	Rarity.EPIC:      Color(0.70, 0.12, 0.95),   # violet
	Rarity.LEGENDARY: Color(1.00, 0.76, 0.00),   # or
}

# Poids de tirage par rareté (somme = 100)
const RARITY_WEIGHTS: Dictionary = {
	Rarity.COMMON:    60,
	Rarity.UNCOMMON:  25,
	Rarity.RARE:      10,
	Rarity.EPIC:       4,
	Rarity.LEGENDARY:  1,
}

# =============================================================
# CATALOGUE — 23 compétences du GDD
# Clé : identifiant string stable (utilisé comme ID dans XpManager)
# Valeur : { name, description, rarity }
# =============================================================
const SKILLS: Dictionary = {

	# ── COMMUNES (60 %) ──────────────────────────────────────
	"return_speed_boost": {
		"name":        "Réflexes boostés",
		"description": "Tes balles renvoyées gagnent +15 % de vitesse.",
		"rarity":      Rarity.COMMON,
	},
	"shield_size_boost": {
		"name":        "Bouclier élargi",
		"description": "Le rayon de ton bouclier augmente de +10 %.",
		"rarity":      Rarity.COMMON,
	},
	"parry_hp_regen": {
		"name":        "Parade curative",
		"description": "Chaque parade te régénère 1 HP (max 1 fois toutes les 5 s).",
		"rarity":      Rarity.COMMON,
	},
	"return_damage_boost": {
		"name":        "Frappe renforcée",
		"description": "Tes balles renvoyées infligent +10 % de dégâts.",
		"rarity":      Rarity.COMMON,
	},
	"shield_duration_boost": {
		"name":        "Endurance du bouclier",
		"description": "La durée d'activation du bouclier augmente de +20 %.",
		"rarity":      Rarity.COMMON,
	},

	# ── PEU COMMUNES (25 %) ──────────────────────────────────
	"piercing_bullet": {
		"name":        "Balle perçante",
		"description": "Ta balle renvoyée traverse un ennemi supplémentaire avant de disparaître.",
		"rarity":      Rarity.UNCOMMON,
	},
	"parry_window_boost": {
		"name":        "Timing de maître",
		"description": "La fenêtre de parade critique s'agrandit de +20 %.",
		"rarity":      Rarity.UNCOMMON,
	},
	"stomp_damage_boost": {
		"name":        "Écrasement brutal",
		"description": "Le saut écrasant inflige 2× plus de dégâts.",
		"rarity":      Rarity.UNCOMMON,
	},
	"dash_unlock": {
		"name":        "Dash bouclier",
		"description": "Débloque le dash bouclier : maintiens le bouclier + direction + saut.",
		"rarity":      Rarity.UNCOMMON,
	},
	"enemy_slowdown": {
		"name":        "Onde de ralentissement",
		"description": "Les balles ennemies se déplacent 15 % moins vite.",
		"rarity":      Rarity.UNCOMMON,
	},

	# ── RARES (10 %) ─────────────────────────────────────────
	"poison_bullet": {
		"name":        "Balle empoisonnée",
		"description": "Ta balle renvoyée empoisonne l'ennemi — dégâts sur 3 secondes.",
		"rarity":      Rarity.RARE,
	},
	"double_bullet": {
		"name":        "Double renvoi",
		"description": "Chaque parade envoie 2 balles légèrement divergentes.",
		"rarity":      Rarity.RARE,
	},
	"critical_parry_heal": {
		"name":        "Parade critique + soin",
		"description": "Une parade critique te soigne instantanément de 3 HP.",
		"rarity":      Rarity.RARE,
	},
	"stomp_shockwave": {
		"name":        "Stomp sismique",
		"description": "Le saut écrasant libère une onde de choc qui repousse les ennemis proches.",
		"rarity":      Rarity.RARE,
	},
	"wall_bounce": {
		"name":        "Rebond mural",
		"description": "Ta balle renvoyée rebondit une fois sur les murs avant de disparaître.",
		"rarity":      Rarity.RARE,
	},

	# ── ÉPIQUES (4 %) ────────────────────────────────────────
	"chain_lightning": {
		"name":        "Chaîne éclair",
		"description": "Quand ta balle tue un ennemi, elle rebondit vers le plus proche (max 2 fois).",
		"rarity":      Rarity.EPIC,
	},
	"mirror_shield": {
		"name":        "Bouclier miroir",
		"description": "3 s après une parade critique, toutes les balles proches sont auto-renvoyées.",
		"rarity":      Rarity.EPIC,
	},
	"fire_stomp": {
		"name":        "Frappe enflammée",
		"description": "Le saut écrasant laisse une zone de feu au sol pendant 4 secondes.",
		"rarity":      Rarity.EPIC,
	},
	"phantom_bullet": {
		"name":        "Balle fantôme",
		"description": "Une balle renvoyée sur deux est fantôme — les ennemis ne peuvent pas l'éviter.",
		"rarity":      Rarity.EPIC,
	},

	# ── LÉGENDAIRES (1 %) ────────────────────────────────────
	"shield_nova": {
		"name":        "Nova du bouclier",
		"description": "Chaque parade critique libère une onde qui blesse tous les ennemis visibles.",
		"rarity":      Rarity.LEGENDARY,
	},
	"omni_bullet": {
		"name":        "Balle omnidirectionnelle",
		"description": "À chaque parade, une seconde balle part automatiquement dans la direction opposée.",
		"rarity":      Rarity.LEGENDARY,
	},
	"invuln_flash": {
		"name":        "Invulnérabilité éclair",
		"description": "0,5 seconde d'invulnérabilité accordée après chaque parade réussie.",
		"rarity":      Rarity.LEGENDARY,
	},
	"clone_bullet": {
		"name":        "Clone de balle",
		"description": "Ta balle renvoyée crée une copie à mi-chemin qui repart dans une direction aléatoire.",
		"rarity":      Rarity.LEGENDARY,
	},
}


# =============================================================
# TIRAGE ALÉATOIRE
# =============================================================

## Tire une rareté aléatoire selon les poids.
static func _draw_rarity() -> Rarity:
	var roll := randi_range(1, 100)
	var cumul := 0
	for r: int in [Rarity.COMMON, Rarity.UNCOMMON, Rarity.RARE, Rarity.EPIC, Rarity.LEGENDARY]:
		cumul += RARITY_WEIGHTS[r]
		if roll <= cumul:
			return r as Rarity
	return Rarity.COMMON


## Construit le pool de skills d'une rareté donnée, en excluant les acquis si possible.
static func _pool_for_rarity(rarity: Rarity, acquired: Array) -> Array:
	var pool_all:  Array = []
	var pool_new:  Array = []
	for id: String in SKILLS.keys():
		if SKILLS[id]["rarity"] == rarity:
			pool_all.append(id)
			if not acquired.has(id):
				pool_new.append(id)
	# Si tous les skills de cette rareté sont déjà acquis, autoriser les doublons
	return pool_new if not pool_new.is_empty() else pool_all


## Tire 2 compétences uniques de LA MÊME rareté aléatoire.
## `acquired` : liste de IDs déjà possédés — exclus du tirage si possible.
static func draw_two(acquired: Array) -> Array:
	var result: Array = []
	
	# 1. On tire UNE SEULE rareté pour ce level up
	var rarity := _draw_rarity()
	var pool   := _pool_for_rarity(rarity, acquired)
	
	# 2. Sécurité : Si par un hasard total cette rareté n'a plus 2 compétences dispo 
	# (ce qui n'arrive normalement pas grâce à ton système de pool), on en cherche une autre.
	var attempts := 0
	while pool.size() < 2 and attempts < 50:
		rarity = _draw_rarity()
		pool = _pool_for_rarity(rarity, acquired)
		attempts += 1

	# 3. On mélange le pool aléatoirement
	pool.shuffle()
	
	# 4. On prend les deux premières compétences du pool mélangé
	for i in range(min(2, pool.size())):
		var id: String = pool[i]
		var entry: Dictionary = SKILLS[id].duplicate()
		entry["id"] = id
		result.append(entry)

	# 5. Fallback ultime si le tirage échoue (très improbable)
	if result.size() < 2:
		for id: String in SKILLS.keys():
			# On vérifie qu'on n'ajoute pas un doublon
			var already_in_result = false
			for res in result:
				if res["id"] == id:
					already_in_result = true
			
			if not already_in_result:
				var entry: Dictionary = SKILLS[id].duplicate()
				entry["id"] = id
				result.append(entry)
				if result.size() >= 2:
					break

	return result
