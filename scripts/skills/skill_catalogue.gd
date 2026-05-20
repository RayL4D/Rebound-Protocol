class_name SkillCatalogue

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES: Dictionary = {
	Rarity.COMMON:    "RARITY_COMMON",
	Rarity.UNCOMMON:  "RARITY_UNCOMMON",
	Rarity.RARE:      "RARITY_RARE",
	Rarity.EPIC:      "RARITY_EPIC",
	Rarity.LEGENDARY: "RARITY_LEGENDARY",
}

const RARITY_COLORS: Dictionary = {
	Rarity.COMMON:    Color(0.72, 0.72, 0.72),
	Rarity.UNCOMMON:  Color(0.20, 0.85, 0.30),
	Rarity.RARE:      Color(0.20, 0.55, 1.00),
	Rarity.EPIC:      Color(0.70, 0.12, 0.95),
	Rarity.LEGENDARY: Color(1.00, 0.76, 0.00),
}

const RARITY_WEIGHTS: Dictionary = {
	Rarity.COMMON:    60,
	Rarity.UNCOMMON:  25,
	Rarity.RARE:      10,
	Rarity.EPIC:       4,
	Rarity.LEGENDARY:  1,
}

const SKILLS: Dictionary = {
	"return_speed_boost": { "name": "SKILL_NAME_return_speed_boost", "description": "SKILL_DESC_return_speed_boost", "rarity": Rarity.COMMON },
	"shield_size_boost": { "name": "SKILL_NAME_shield_size_boost", "description": "SKILL_DESC_shield_size_boost", "rarity": Rarity.COMMON },
	"parry_hp_regen": { "name": "SKILL_NAME_parry_hp_regen", "description": "SKILL_DESC_parry_hp_regen", "rarity": Rarity.COMMON },
	"return_damage_boost": { "name": "SKILL_NAME_return_damage_boost", "description": "SKILL_DESC_return_damage_boost", "rarity": Rarity.COMMON },
	"shield_duration_boost": { "name": "SKILL_NAME_shield_duration_boost", "description": "SKILL_DESC_shield_duration_boost", "rarity": Rarity.COMMON },
	"piercing_bullet": { "name": "SKILL_NAME_piercing_bullet", "description": "SKILL_DESC_piercing_bullet", "rarity": Rarity.UNCOMMON },
	"parry_window_boost": { "name": "SKILL_NAME_parry_window_boost", "description": "SKILL_DESC_parry_window_boost", "rarity": Rarity.UNCOMMON },
	"stomp_damage_boost": { "name": "SKILL_NAME_stomp_damage_boost", "description": "SKILL_DESC_stomp_damage_boost", "rarity": Rarity.UNCOMMON },
	"dash_unlock": { "name": "SKILL_NAME_dash_unlock", "description": "SKILL_DESC_dash_unlock", "rarity": Rarity.UNCOMMON },
	"enemy_slowdown": { "name": "SKILL_NAME_enemy_slowdown", "description": "SKILL_DESC_enemy_slowdown", "rarity": Rarity.UNCOMMON },
	"poison_bullet": { "name": "SKILL_NAME_poison_bullet", "description": "SKILL_DESC_poison_bullet", "rarity": Rarity.RARE },
	"double_bullet": { "name": "SKILL_NAME_double_bullet", "description": "SKILL_DESC_double_bullet", "rarity": Rarity.RARE },
	"critical_parry_heal": { "name": "SKILL_NAME_critical_parry_heal", "description": "SKILL_DESC_critical_parry_heal", "rarity": Rarity.RARE },
	"stomp_shockwave": { "name": "SKILL_NAME_stomp_shockwave", "description": "SKILL_DESC_stomp_shockwave", "rarity": Rarity.RARE },
	"wall_bounce": { "name": "SKILL_NAME_wall_bounce", "description": "SKILL_DESC_wall_bounce", "rarity": Rarity.RARE },
	"chain_lightning": { "name": "SKILL_NAME_chain_lightning", "description": "SKILL_DESC_chain_lightning", "rarity": Rarity.EPIC },
	"mirror_shield": { "name": "SKILL_NAME_mirror_shield", "description": "SKILL_DESC_mirror_shield", "rarity": Rarity.EPIC },
	"fire_stomp": { "name": "SKILL_NAME_fire_stomp", "description": "SKILL_DESC_fire_stomp", "rarity": Rarity.EPIC },
	"phantom_bullet": { "name": "SKILL_NAME_phantom_bullet", "description": "SKILL_DESC_phantom_bullet", "rarity": Rarity.EPIC },
	"shield_nova": { "name": "SKILL_NAME_shield_nova", "description": "SKILL_DESC_shield_nova", "rarity": Rarity.LEGENDARY },
	"omni_bullet": { "name": "SKILL_NAME_omni_bullet", "description": "SKILL_DESC_omni_bullet", "rarity": Rarity.LEGENDARY },
	"invuln_flash": { "name": "SKILL_NAME_invuln_flash", "description": "SKILL_DESC_invuln_flash", "rarity": Rarity.LEGENDARY },
	"clone_bullet": { "name": "SKILL_NAME_clone_bullet", "description": "SKILL_DESC_clone_bullet", "rarity": Rarity.LEGENDARY },
}

static func _draw_rarity() -> Rarity:
	var roll := randi_range(1, 100)
	var cumul := 0
	for r: int in [Rarity.COMMON, Rarity.UNCOMMON, Rarity.RARE, Rarity.EPIC, Rarity.LEGENDARY]:
		cumul += RARITY_WEIGHTS[r]
		if roll <= cumul: return r as Rarity
	return Rarity.COMMON

static func _pool_for_rarity(rarity: Rarity, acquired: Array) -> Array:
	var pool_all: Array = []
	var pool_new: Array = []
	for id: String in SKILLS.keys():
		if SKILLS[id]["rarity"] == rarity:
			pool_all.append(id)
			if not acquired.has(id): pool_new.append(id)
	return pool_new if not pool_new.is_empty() else pool_all

static func draw_two(acquired: Array) -> Array:
	var result: Array = []
	var rarity := _draw_rarity()
	var pool := _pool_for_rarity(rarity, acquired)
	var attempts := 0
	while pool.size() < 2 and attempts < 50:
		rarity = _draw_rarity()
		pool = _pool_for_rarity(rarity, acquired)
		attempts += 1
	pool.shuffle()
	for i in range(min(2, pool.size())):
		var id: String = pool[i]
		var entry: Dictionary = SKILLS[id].duplicate()
		entry["id"] = id
		result.append(entry)
	if result.size() < 2:
		for id: String in SKILLS.keys():
			var already_in_result = false
			for res in result:
				if res["id"] == id: already_in_result = true
			if not already_in_result:
				var entry: Dictionary = SKILLS[id].duplicate()
				entry["id"] = id
				result.append(entry)
				if result.size() >= 2: break
	return result
