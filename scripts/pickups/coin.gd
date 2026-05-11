# =============================================================
# coin.gd — Pièce droppée à la mort d'un ennemi
# Rebound Protocol
# =============================================================
# Utilisation : Coin.spawn(parent, position, value)
#   → crée une pièce flottante dans la scène.
#
# La pièce est attirée vers le joueur dès qu'il entre dans le
# rayon de collecte (base 3 m, modifié par upgrade "pickup_radius").
# Elle se collecte automatiquement au contact.
# =============================================================

class_name Coin
extends Area3D

# Valeur en pièces de ce pickup (1–5 selon l'ennemi)
var _value: int = 1

# Rayon de détection d'attraction (override par SaveData)
const BASE_ATTRACT_RADIUS := 3.0
const COLLECT_RADIUS      := 0.6   # collecte effective (toucher le joueur)
const ATTRACT_SPEED       := 8.0   # m/s vers le joueur quand attiré
const LIFETIME            := 20.0  # disparaît après 20 s si non collectée

# --- Audio ------------------------------------------------------
const _SFX_LAND:    AudioStream = preload("res://audio/sfx/enemies/coin_land.wav")
const _SFX_COLLECT: AudioStream = preload("res://audio/sfx/enemies/coin_collect.wav")
var _sfx: AudioStreamPlayer = null
var _land_played: bool = false   # évite de rejouer si plusieurs rebonds

var _player:     Player = null
var _attracted:  bool   = false
var _lifetime:   float  = LIFETIME
var _bob_time:   float  = 0.0      # pour l'animation de flottaison

# --- NOUVELLES VARIABLES POUR LE SAUT ---
var _is_popping: bool    = false
var _velocity:   Vector3 = Vector3.ZERO
var _ground_y:   float   = 0.0
var _gravity:    float   = 18.0    # Force de la gravité personnalisée

# =============================================================
# FACTORY
# =============================================================

## Instancie et ajoute une pièce dans la scène.
## value : nombre de pièces (1–5)
static func spawn(parent: Node, world_pos: Vector3, value: int = 1) -> void:
	var coin := _build()
	coin._value = value
	parent.add_child(coin)
	
	# On démarre exactement au centre de l'ennemi
	coin.global_position = world_pos
	
	# La cible Y où la pièce finira par flotter
	coin._ground_y = world_pos.y + 0.4
	
	# Impulsion aléatoire pour l'explosion
	coin._velocity = Vector3(
		randf_range(-3.0, 3.0),
		randf_range(5.0, 8.0), # Force vers le haut
		randf_range(-3.0, 3.0)
	)
	coin._is_popping = true

## Construit le graphe de nœuds d'une pièce (sans l'ajouter à la scène).
static func _build() -> Coin:
	# Nœud racine : Area3D (detecte joueur)
	var self_node := Coin.new()
	self_node.collision_layer = 0   # pas de layer propre
	self_node.collision_mask  = 1   # détecte layer 1 (player)
	self_node.monitoring      = true
	self_node.monitorable     = false

	# Sphère de détection (rayon d'attraction, ajusté au runtime)
	var attract_shape        := SphereShape3D.new()
	attract_shape.radius      = BASE_ATTRACT_RADIUS
	var attract_col          := CollisionShape3D.new()
	attract_col.shape         = attract_shape
	attract_col.name          = "AttractZone"
	self_node.add_child(attract_col)

	# Mesh visuel : cylindre doré (ressemble à une pièce)
	var mesh_inst            := MeshInstance3D.new()
	var cyl                  := CylinderMesh.new()
	cyl.top_radius            = 0.15
	cyl.bottom_radius         = 0.15
	cyl.height                = 0.06
	cyl.radial_segments       = 16
	mesh_inst.mesh            = cyl
	mesh_inst.rotation_degrees = Vector3(90, 0, 0)  # face vers la caméra

	var mat                  := StandardMaterial3D.new()
	mat.albedo_color          = Color(1.0, 0.82, 0.1)
	mat.emission_enabled      = true
	mat.emission              = Color(1.0, 0.70, 0.0)
	mat.emission_energy_multiplier = 1.2
	mesh_inst.set_surface_override_material(0, mat)
	self_node.add_child(mesh_inst)

	# Halo (OmniLight3D léger pour le glow)
	var light            := OmniLight3D.new()
	light.light_color     = Color(1.0, 0.85, 0.2)
	light.light_energy    = 0.6
	light.omni_range      = 1.2
	self_node.add_child(light)

	return self_node


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_sfx     = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)

	# Ajuster le rayon d'attraction selon l'upgrade "pickup_radius"
	var radius_mult := 1.0 + SaveData.get_upgrade_value("pickup_radius")
	var col := get_node_or_null("AttractZone") as CollisionShape3D
	if col and col.shape is SphereShape3D:
		(col.shape as SphereShape3D).radius = BASE_ATTRACT_RADIUS * radius_mult

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	if _is_popping:
		# --- PHASE 1 : EXPLOSION ET REBONDS ---
		_velocity.y -= _gravity * delta
		global_position += _velocity * delta
		
		# Si la pièce tombe sous sa ligne de flottaison cible
		if global_position.y <= _ground_y and _velocity.y < 0.0:
			global_position.y = _ground_y
			
			# Rebond amorti
			_velocity.y *= -0.4  # Perd de la hauteur
			_velocity.x *= 0.6   # Ralentit sur les côtés
			_velocity.z *= 0.6
			
			# Si le rebond est trop petit, on arrête la physique
			if _velocity.y < 1.0:
				_is_popping = false
				_bob_time = 0.0  # On reset pour la flottaison
				if not _land_played and _sfx and _SFX_LAND:
					_land_played        = true
					_sfx.stream         = _SFX_LAND
					_sfx.volume_db      = -6.0 + randf_range(-1.0, 1.0)
					_sfx.pitch_scale    = randf_range(0.90, 1.10)
					_sfx.play()
	else:
		# --- PHASE 2 : COMPORTEMENT ORIGINAL ---
		_bob_time += delta
		# Flottaison sinusoïdale douce
		position.y += sin(_bob_time * 3.0) * 0.003

		# Attraction vers le joueur
		if _attracted and _player != null and is_instance_valid(_player):
			var dir := (_player.global_position + Vector3(0, 0.5, 0)) - global_position
			if dir.length() < COLLECT_RADIUS:
				_collect()
				return
			global_position += dir.normalized() * ATTRACT_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body is Player:
		_attracted = true
		_player    = body as Player


func _collect() -> void:
	SaveData.add_coins(_value)
	_spawn_collect_burst()

	# Player flottant — survit au queue_free de la pièce
	if _SFX_COLLECT != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_COLLECT
		p.bus         = "SFX"
		p.volume_db   = -2.0 + randf_range(-1.0, 1.0)
		p.pitch_scale = randf_range(0.95, 1.05)
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

	queue_free()


# =============================================================
# FX DE COLLECTE
# =============================================================

func _spawn_collect_burst() -> void:
	if not is_inside_tree():
		return
	var origin := global_position
	var parent  := get_tree().current_scene

	for i in 6:
		var angle := TAU * float(i) / 6.0
		var dir   := Vector3(cos(angle), 0.5, sin(angle)).normalized()
		_burst_particle(parent, origin, dir)


func _burst_particle(parent: Node, origin: Vector3, dir: Vector3) -> void:
	var sphere      := SphereMesh.new()
	sphere.radius    = 0.04
	sphere.height    = 0.08
	sphere.radial_segments = 4
	sphere.rings     = 2

	var mat          := StandardMaterial3D.new()
	mat.albedo_color  = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission      = Color(1.0, 0.75, 0.0)
	mat.emission_energy_multiplier = 1.5

	var mi           := MeshInstance3D.new()
	mi.mesh           = sphere
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	mi.global_position = origin

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position",
		origin + dir * randf_range(0.4, 0.8), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(
		func(a: float): mat.albedo_color = Color(1.0, 0.85, 0.1, a),
		1.0, 0.0, 0.35)
	tw.tween_callback(mi.queue_free)
