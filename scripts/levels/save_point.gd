# =============================================================
# save_point.gd — Point de sauvegarde visuel
# Rebound Protocol
# =============================================================
# Glisse scenes/levels/save_point.tscn dans ton niveau.
#
# Exports (Inspector) :
#   checkpoint_id — identifiant unique (ex. "level1_a")
#   level_name    — vide = détection auto depuis le chemin de scène
#   zone_radius   — rayon de la zone de détection (défaut 2.0 m)
#
# Tous les visuels sont des nœuds éditables dans l'Inspector Godot :
#   Visuals/Beam            — faisceau vertical lumineux
#   Visuals/ZoneRing        — anneau de sol (shader pulsant)
#   Visuals/ZoneBoundary    — cylindre semi-transparent de zone
#   Visuals/HoverRing       — anneau flottant en rotation lente
#   Visuals/ZonePillars/    — 4 piliers cardinaux + gemmes au sommet
#   Visuals/Orbiters/       — 3 gemmes en orbite autour du flag
#   Visuals/Light           — OmniLight pulsante
# =============================================================

extends Node3D

@export var checkpoint_id: String = "checkpoint_default"
@export var level_name:    String = ""
@export var zone_radius:   float  = 2.0

signal save_triggered

const TEXTURE_PATH := "res://assets/textures/platformerkit/colormap.png"

# Couleurs
const COLOR_IDLE   := Color(0.0, 0.85, 1.0, 1.0)   # Cyan inactif
const COLOR_ACTIVE := Color(1.0, 0.85, 0.1, 1.0)   # Or actif

var _activated:   bool  = false
var _orbit_angle: float = 0.0
var _pulse_time:  float = 0.0

# ── Références de scène ───────────────────────────────────────────────────────
@onready var _flag_model: Node3D         = $Flag
@onready var _beam_mi:    MeshInstance3D = $Visuals/Beam
@onready var _ring_mi:    MeshInstance3D = $Visuals/ZoneRing
@onready var _hover_ring: MeshInstance3D = $Visuals/HoverRing
@onready var _light:      OmniLight3D   = $Visuals/Light

@onready var _cap_n: MeshInstance3D = $Visuals/ZonePillars/Pillar_N/Cap_N
@onready var _cap_e: MeshInstance3D = $Visuals/ZonePillars/Pillar_E/Cap_E
@onready var _cap_s: MeshInstance3D = $Visuals/ZonePillars/Pillar_S/Cap_S
@onready var _cap_w: MeshInstance3D = $Visuals/ZonePillars/Pillar_W/Cap_W

@onready var _orbiter1: MeshInstance3D = $Visuals/Orbiters/Orbiter1
@onready var _orbiter2: MeshInstance3D = $Visuals/Orbiters/Orbiter2
@onready var _orbiter3: MeshInstance3D = $Visuals/Orbiters/Orbiter3

# ── Matériaux (récupérés au _ready, partagés entre nœuds du même type) ───────
var _ring_mat:       ShaderMaterial     = null
var _beam_mat:       StandardMaterial3D = null
var _hover_ring_mat: StandardMaterial3D = null
var _cap_mat:        StandardMaterial3D = null   # partagé : Cap_N/E/S/W
var _orbiter_mat:    StandardMaterial3D = null   # partagé : Orbiter1/2/3

var _orbiters: Array = []
var _caps:     Array = []


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Empêche _add_collision_recursive (arena_base) de solidifier les visuels
	add_to_group("no_collision")

	_ring_mat       = _ring_mi.material_override as ShaderMaterial
	_beam_mat       = _beam_mi.material_override as StandardMaterial3D
	_hover_ring_mat = _hover_ring.material_override as StandardMaterial3D
	_cap_mat        = _cap_n.material_override as StandardMaterial3D
	_orbiter_mat    = _orbiter1.material_override as StandardMaterial3D

	_orbiters = [_orbiter1, _orbiter2, _orbiter3]
	_caps     = [_cap_n, _cap_e, _cap_s, _cap_w]

	_apply_flag_texture()


func _process(delta: float) -> void:
	_pulse_time  += delta
	_orbit_angle += delta * 0.9

	# Pulse de l'anneau de sol
	if _ring_mat:
		var p := sin(_pulse_time * 2.2) * 0.5 + 0.5
		_ring_mat.set_shader_parameter("pulse", p * 0.35)

	# Pulse de la lumière
	if _light:
		var lp := sin(_pulse_time * 1.8) * 0.5 + 0.5
		_light.light_energy = 0.6 + lp * 0.5

	# Pulse du faisceau
	if _beam_mat:
		var bp := sin(_pulse_time * 2.5) * 0.5 + 0.5
		_beam_mat.emission_energy_multiplier = 1.2 + bp * 0.8

	# HoverRing : rotation lente continue
	if _hover_ring:
		_hover_ring.rotation.y = _pulse_time * 0.4

	# Orbiteurs : rotation autour du flag + lévitation
	for i in _orbiters.size():
		var orb: MeshInstance3D = _orbiters[i]
		var phase  := _orbit_angle + (TAU / _orbiters.size()) * i
		var radius := 0.32
		var height := 1.2 + sin(_pulse_time * 1.4 + i * 1.3) * 0.18
		orb.position = Vector3(cos(phase) * radius, height, sin(phase) * radius)

	# Caps des piliers : lévitation légère et décalée
	for i in _caps.size():
		var cap: MeshInstance3D = _caps[i]
		cap.position.y = 0.85 + sin(_pulse_time * 1.6 + i * (TAU / _caps.size())) * 0.04


# =============================================================
# TEXTURE DU FLAG
# =============================================================

func _apply_flag_texture() -> void:
	if not ResourceLoader.exists(TEXTURE_PATH):
		push_warning("SavePoint: texture colormap introuvable — " + TEXTURE_PATH)
		return
	var tex: Texture2D = load(TEXTURE_PATH)
	_apply_texture_recursive(_flag_model, tex)


func _apply_texture_recursive(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter  = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		node.material_override = mat
	for child in node.get_children():
		_apply_texture_recursive(child, tex)


# =============================================================
# DÉTECTION ET SAUVEGARDE
# =============================================================

func _on_player_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	_do_save(body)

	if not _activated:
		_activated = true
		_play_activate_animation()
	else:
		_play_repulse_animation()


func _do_save(player_node: Node3D) -> void:
	if SaveData.active_slot < 0:
		return

	var lname: String = level_name
	if lname == "":
		lname = get_tree().current_scene.scene_file_path.get_file().get_basename()

	SaveData.set_checkpoint(checkpoint_id)
	SaveData.set_current_level(lname)
	SaveData.set_player_position(player_node.global_position)

	if player_node.get("current_hp") != null:
		SaveData.set_player_hp(int(player_node.get("current_hp")))

	SaveData.save_current()
	save_triggered.emit()


# =============================================================
# ANIMATIONS
# =============================================================

func _play_activate_animation() -> void:
	# 1. Anneau de sol : cyan → or
	if _ring_mat:
		var tw := create_tween()
		tw.tween_method(
			func(c: Color): _ring_mat.set_shader_parameter("ring_color", c),
			Color(COLOR_IDLE.r,   COLOR_IDLE.g,   COLOR_IDLE.b,   0.55),
			Color(COLOR_ACTIVE.r, COLOR_ACTIVE.g, COLOR_ACTIVE.b, 0.80),
			0.4
		)

	# 2. Lumière : flash blanc puis or
	if _light:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_light, "light_color",  Color(1.0, 1.0, 1.0), 0.08)
		tw.tween_property(_light, "light_energy", 4.0,                   0.08)
		tw.chain().tween_property(_light, "light_color",  COLOR_ACTIVE, 0.3)
		tw.chain().tween_property(_light, "light_energy", 1.2,           0.3)

	# 3. Faisceau : flash blanc puis or
	if _beam_mat:
		var tw := create_tween()
		tw.tween_method(
			func(c: Color): _beam_mat.emission = c,
			COLOR_IDLE, Color(1.0, 1.0, 0.8), 0.1
		)
		tw.tween_method(
			func(c: Color): _beam_mat.emission = c,
			Color(1.0, 1.0, 0.8), COLOR_ACTIVE, 0.3
		)

	# 4. Orbiteurs : cyan → or (matériau partagé, une tween suffit)
	if _orbiter_mat:
		var tw := create_tween().set_parallel(true)
		tw.tween_method(
			func(c: Color): _orbiter_mat.emission = c; _orbiter_mat.albedo_color = c,
			COLOR_IDLE, COLOR_ACTIVE, 0.4
		)

	# 5. Caps des piliers : cyan → or (matériau partagé, une tween suffit)
	if _cap_mat:
		var tw := create_tween().set_parallel(true)
		tw.tween_method(
			func(c: Color): _cap_mat.emission = c; _cap_mat.albedo_color = c,
			COLOR_IDLE, COLOR_ACTIVE, 0.4
		)

	# 6. HoverRing : cyan → or
	if _hover_ring_mat:
		var tw := create_tween().set_parallel(true)
		tw.tween_method(
			func(c: Color): _hover_ring_mat.emission = c,
			COLOR_IDLE, COLOR_ACTIVE, 0.4
		)

	# 7. Rebond du flag
	if _flag_model:
		var tw := create_tween()
		tw.tween_property(_flag_model, "position:y", 0.35, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_flag_model, "position:y", 0.0,  0.35) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# 8. Burst de particules
	_spawn_burst(COLOR_ACTIVE, 18)


func _play_repulse_animation() -> void:
	# Flash rapide sur l'anneau de sol
	if _ring_mat:
		var tw := create_tween()
		tw.tween_method(
			func(v: float): _ring_mat.set_shader_parameter("pulse", v),
			1.0, 0.0, 0.45
		)

	# Petit burst discret
	_spawn_burst(COLOR_ACTIVE, 6)


func _spawn_burst(color: Color, count: int) -> void:
	var origin := global_position + Vector3(0, 1.0, 0)
	var parent  := get_tree().current_scene

	for i in count:
		var angle := TAU * float(i) / float(count) + randf() * 0.3
		var dir   := Vector3(
			cos(angle),
			randf_range(0.5, 1.4),
			sin(angle)
		).normalized()

		var sphere     := SphereMesh.new()
		sphere.radius   = 0.04
		sphere.height   = 0.08
		sphere.radial_segments = 4

		var mat := StandardMaterial3D.new()
		mat.albedo_color              = color
		mat.emission_enabled          = true
		mat.emission                  = color
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED

		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.set_surface_override_material(0, mat)
		parent.add_child(mi)
		mi.global_position = origin

		var dist := randf_range(0.7, 1.6)
		var dur  := 0.5 + randf() * 0.15

		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", origin + dir * dist, dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(
			func(a: float):
				mat.albedo_color = Color(color.r, color.g, color.b, a)
				mat.emission_energy_multiplier = a * 3.0,
			1.0, 0.0, dur)
		tw.tween_callback(mi.queue_free)
