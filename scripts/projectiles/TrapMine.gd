# =============================================================
# TrapMine.gd — Mine posée par le Castor
# Rebound Protocol
# =============================================================
# Petite mine au sol qui explose au contact du joueur.
# Gérée par WeaponTrap.gd (qui la crée et track sa durée de vie).
#
# Usage :
#   var mine := TrapMine.new()
#   get_tree().current_scene.add_child(mine)  # d'abord dans l'arbre
#   mine.init(global_position, damage, lifetime)
# =============================================================
class_name TrapMine
extends Area3D

const TRIGGER_RADIUS: float = 0.75
const MINE_SCENE:     PackedScene = preload("res://assets/models/platformerkit/button-round.glb")
const COLORMAP:       Texture2D   = preload("res://assets/textures/platformerkit/colormap.png")

var _damage:         int   = 10
var _lifetime:       float = 25.0
var _elapsed:        float = 0.0
var _triggered:      bool  = false

# Référence au matériau pour l'animation de clignotement final
var _mat: StandardMaterial3D = null
# Phase accumulée pour un chirp propre (évite l'emballement via _elapsed * hz)
var _blink_phase: float = 0.0


# =============================================================
# INITIALISATION (appeler après add_child)
# =============================================================

func init(pos: Vector3, dmg: int, lifetime: float) -> void:
	_damage   = dmg
	_lifetime = lifetime

	# Pose la mine légèrement au-dessus du sol pour éviter le z-fighting.
	# pos.y est la position Y de l'ennemi (origine du CharacterBody3D, au ras du sol).
	global_position = Vector3(pos.x, pos.y + 0.06, pos.z)

	# Collision : détecte les corps sur le calque 1 (joueur)
	collision_layer  = 0
	collision_mask   = 1
	monitoring       = true

	# Forme de détection
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = TRIGGER_RADIUS
	col.shape  = sph
	add_child(col)

	# Visuel : button-round.glb — disque plat reconnaissable comme mine
	var mine_inst := MINE_SCENE.instantiate()
	mine_inst.scale = Vector3(0.7, 0.7, 0.7)
	add_child(mine_inst)

	# Matériau avec la texture platformerkit + émission pour le clignotement.
	# On crée un nouveau matériau (pas de modification du matériau partagé du GLB).
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture             = COLORMAP
	_mat.emission_enabled           = true
	_mat.emission                   = Color(1.0, 0.1, 0.0)   # rouge-orangé
	_mat.emission_energy_multiplier = 0.0   # éteint au repos

	_apply_material(mine_inst, _mat)

	body_entered.connect(_on_body_entered)


# =============================================================
# UTILITAIRES — parcourt le modèle pour appliquer le matériau
# =============================================================

func _apply_material(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in mesh_inst.get_surface_override_material_count():
			mesh_inst.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material(child, mat)


# =============================================================
# LOGIQUE
# =============================================================

func _process(delta: float) -> void:
	_elapsed += delta

	# Clignotement dans les 5 dernières secondes de vie
	var remaining := _lifetime - _elapsed

	if _mat != null:
		if remaining <= 5.0:
			# Fréquence qui accélère progressivement (chirp)
			var t     := clampf(1.0 - remaining / 5.0, 0.0, 1.0)
			var hz    := lerpf(1.5, 10.0, t * t)
			_blink_phase += hz * TAU * delta

			# Seulement la demi-onde positive → flash bref, silence long
			# Donne une impulsion nette sans "rester allumé" entre les flashs
			var pulse := maxf(0.0, sin(_blink_phase))
			_mat.emission_energy_multiplier = pulse * 4.0
		else:
			_mat.emission_energy_multiplier = 0.0   # silencieux pendant la vie normale

	if _elapsed >= _lifetime:
		queue_free()


const _SFX_EXPLODE: AudioStream = preload("res://audio/sfx/enemies/mine_explode.wav")

func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return

	_triggered = true
	body.take_damage(_damage)

	# Player flottant ajouté à /root (plus stable que current_scene lors d'un queue_free)
	if _SFX_EXPLODE != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_EXPLODE
		p.bus         = "SFX"
		p.volume_db   = -5.0
		p.pitch_scale = randf_range(0.95, 1.05)
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

	call_deferred("queue_free")
