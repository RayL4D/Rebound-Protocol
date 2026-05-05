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

var _player:     Player = null
var _attracted:  bool   = false
var _lifetime:   float  = LIFETIME
var _bob_time:   float  = 0.0      # pour l'animation de flottaison


# =============================================================
# FACTORY
# =============================================================

## Instancie et ajoute une pièce dans la scène.
## value : nombre de pièces (1–5)
static func spawn(parent: Node, world_pos: Vector3, value: int = 1) -> void:
	var coin := _build()
	coin._value = value
	parent.add_child(coin)
	coin.global_position = world_pos + Vector3(
		randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))


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
