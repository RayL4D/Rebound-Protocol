# =============================================================
# BulletReflected.gd — Balle renvoyée par le bouclier du joueur
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
class_name BulletReflected
extends Area3D

# --- Exports -----------------------------------------------------
@export var speed: float = 16.0

# --- Palette clairement distincte de la balle ennemie (rouge) ---
# Normale  → CYAN   (couleur identitaire du joueur / bouclier)
# Critique → OR     (identique au flash bouclier en parade parfaite)
#            JAMAIS rouge pour ne pas confondre avec l'ennemi
const C_NORMAL   := Color(0.0,  0.85, 1.0)   # cyan
const C_CRITICAL := Color(1.0,  0.78, 0.0)   # or

# --- Variables internes ------------------------------------------
var direction: Vector3 = Vector3.ZERO
var damage: int        = 10
var _is_critical: bool = false
var _mat: StandardMaterial3D = null

# --- Flags de compétences (définis dans init) --------------------
var _pierce_remaining: int   = 0      # piercing_bullet : traversées restantes
var _wall_bounces:     int   = 0      # wall_bounce : rebonds muraux restants
var _chain_remaining:  int   = 0      # chain_lightning : chaînes restantes
var _is_clone:         bool  = false  # true = balle clone (pas de re-clonage)
var _is_phantom:       bool  = false  # phantom_bullet : visuel spécial
var _is_poisoned:      bool  = false  # poison_bullet : applique DoT

var _dist_traveled:    float = 0.0    # pour le clone à mi-chemin
var _clone_spawned:    bool  = false  # anti-doublon clone
const _CLONE_DIST := 3.5             # unités avant spawn du clone


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	$VisibleOnScreenNotifier3D.screen_exited.connect(_on_screen_exited)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_dist_traveled  += speed * delta

	# Clone de balle : spawn à mi-chemin (~3.5 unités)
	if not _is_clone and not _clone_spawned and _dist_traveled >= _CLONE_DIST:
		_clone_spawned = true
		if get_tree().root.has_node("XpManager") and XpManager.has_skill("clone_bullet"):
			_spawn_clone()

	# Rebond mural
	if _wall_bounces > 0:
		_check_wall_bounce()


# =============================================================
# INITIALISATION — appelée par Shield.gd après add_child()
# =============================================================

## `is_omni` : true pour la balle omnidirectionnelle (pas de skills supplémentaires)
func init(spawn_position: Vector3, target_direction: Vector3,
		bullet_damage: int, is_critical: bool = false, is_omni: bool = false) -> void:
	global_position  = spawn_position
	direction        = target_direction.normalized()
	damage           = bullet_damage
	_is_critical     = is_critical

	# Vitesse : upgrade boutique × skill return_speed_boost
	var save_speed  := 1.0 + (SaveData.get_upgrade_value("reflect_speed") if SaveData.active_slot >= 0 else 0.0)
	var skill_speed := XpManager.return_speed_mult if get_tree().root.has_node("XpManager") else 1.0
	speed = 16.0 * save_speed * skill_speed

	# Flags de compétences (uniquement sur les balles "normales", pas les clones/omni)
	if not _is_clone and not is_omni and get_tree().root.has_node("XpManager"):
		_pierce_remaining = 1 if XpManager.has_skill("piercing_bullet")  else 0
		_wall_bounces     = 1 if XpManager.has_skill("wall_bounce")       else 0
		_chain_remaining  = 2 if XpManager.has_skill("chain_lightning")   else 0
		_is_poisoned      =     XpManager.has_skill("poison_bullet")
		# Phantom : une balle sur deux (toggle dans XpManager)
		if XpManager.has_skill("phantom_bullet"):
			XpManager._phantom_bullet_toggle = not XpManager._phantom_bullet_toggle
			_is_phantom = XpManager._phantom_bullet_toggle

	var color := C_CRITICAL if is_critical else (Color(0.6, 0.0, 1.0) if _is_phantom else C_NORMAL)
	_setup_visuals(color, is_critical)


# =============================================================
# VISUELS
# =============================================================

func _setup_visuals(color: Color, critical: bool) -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color              = color
	_mat.emission_enabled          = true
	_mat.emission                  = color
	_mat.emission_energy_multiplier = 4.0
	$MeshInstance3D.set_surface_override_material(0, _mat)
	"""
	# Lumière dynamique — plus grande et brillante pour le critique
	var light := OmniLight3D.new()
	light.light_color  = color
	light.light_energy = 4.0 if critical else 3.0
	light.omni_range   = 3.5 if critical else 2.5
	add_child(light)
	"""
	# Pulsation — critique plus rapide et plus contrastée
	var lo  := 3.5 if not critical else 5.0
	var hi  := 7.0 if not critical else 12.0
	var dur := 0.20 if not critical else 0.10
	var tw := create_tween().set_loops()
	tw.tween_method(_set_emission.bind(_mat), lo, hi, dur)
	tw.tween_method(_set_emission.bind(_mat), hi, lo, dur)


func _set_emission(value: float, mat: StandardMaterial3D) -> void:
	mat.emission_energy_multiplier = value


# =============================================================
# COLLISIONS
# =============================================================

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemies"):
		return

	body.take_damage(damage)

	# Poison sur l'ennemi touché
	if _is_poisoned and is_inside_tree():
		_apply_poison(body)

	# Chain lightning : si la balle tue l'ennemi et qu'il reste des rebonds
	# (la mort est async via _die() → on vérifie current_hp)
	if _chain_remaining > 0 and body is Enemy and (body as Enemy).current_hp <= 0:
		var next := _find_nearest_enemy(body)
		if next != null and is_inside_tree():
			_chain_remaining -= 1
			_redirect_to(next)
			return   # Ne pas queue_free — la balle rebondit

	# Perçant : traverser un ennemi supplémentaire
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		_spawn_impact()
		return   # Pas de queue_free — la balle continue

	_spawn_impact()
	queue_free()


func _on_screen_exited() -> void:
	queue_free()


# =============================================================
# IMPACT — explosion de particules
# =============================================================

func _spawn_impact() -> void:
	if not is_inside_tree():
		return
	var origin := global_position
	var root   := get_tree().current_scene
	var color  := C_CRITICAL if _is_critical else C_NORMAL
	var count  := 12 if _is_critical else 8

	for i in count:
		var angle := TAU * float(i) / float(count)
		var dir: Vector3
		if i < count - 2:
			dir = Vector3(cos(angle), randf_range(0.0, 0.5), sin(angle)).normalized()
		else:
			dir = Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
		_spawn_spark(root, origin, dir,
			randf_range(1.5, 3.0 if _is_critical else 2.2), color)

	# Flash blanc central sur critique
	if _is_critical:
		_spawn_spark(root, origin, Vector3.UP * 0.3, 0.4, Color.WHITE)


func _spawn_spark(parent: Node, origin: Vector3, dir: Vector3,
		spd: float, color: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius          = 0.045 if _is_critical else 0.033
	sm.height          = sm.radius * 2.0
	sm.radial_segments = 4
	sm.rings           = 2

	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.emission_enabled          = true
	mat.emission                  = color
	mat.emission_energy_multiplier = 4.5
	mat.no_depth_test             = true

	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	mi.global_position = origin

	var dur    := randf_range(0.22, 0.48)
	var target := origin + dir * spd

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", target, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_method(_scale_node.bind(mi), 1.0, 0.0, dur)
	tw.tween_callback(mi.queue_free)


func _scale_node(value: float, node: Node3D) -> void:
	node.scale = Vector3.ONE * value


# =============================================================
# COMPÉTENCES — méthodes auxiliaires
# =============================================================

# --- Poison (3 ticks × 3 dégâts sur 3 secondes) --------------
func _apply_poison(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	var root := get_tree().current_scene

	for tick in range(3):
		var delay := float(tick + 1)
		var tw := root.create_tween()
		# IMPORTANT : ne pas référencer `self` dans ce lambda —
		# la balle est déjà queue_free() quand les ticks suivants tirent.
		tw.tween_callback(func() -> void:
			if is_instance_valid(enemy) and enemy.has_method("take_damage"):
				enemy.take_damage(3, true)
		).set_delay(delay)


# --- Chain lightning : ennemi le plus proche (sauf `exclude`) --
func _find_nearest_enemy(exclude: Node3D) -> Node3D:
	var best:     Node3D = null
	var best_d2:  float  = INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == exclude or not is_instance_valid(e):
			continue
		var d2 := global_position.distance_squared_to(e.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best    = e
	return best


# --- Redirection vers une cible (chain / wall bounce) ----------
func _redirect_to(target: Node3D) -> void:
	var to_target := target.global_position - global_position
	to_target.y   = 0.0
	direction      = to_target.normalized()
	# Petit flash blanc pour indiquer le rebond
	if is_inside_tree():
		_spawn_spark(get_tree().current_scene, global_position,
			Vector3.UP, 0.3, Color.WHITE)


# --- Clone : spawn d'une seconde balle réfléchie ---------------
func _spawn_clone() -> void:
	if not is_inside_tree():
		return
	# Chargement dynamique pour éviter les dépendances circulaires
	var bullet_scene: PackedScene = load("res://scenes/projectiles/bullet_reflected.tscn")
	if bullet_scene == null:
		return

	var clone: BulletReflected = bullet_scene.instantiate()
	clone._is_clone = true

	# Direction légèrement décalée (±20°) pour ne pas superposer les deux balles
	var angle_offset := randf_range(deg_to_rad(15.0), deg_to_rad(25.0))
	if randf() < 0.5:
		angle_offset = -angle_offset
	var clone_dir := direction.rotated(Vector3.UP, angle_offset)

	get_tree().current_scene.add_child(clone)
	clone.init(global_position, clone_dir, damage, _is_critical, false)


# --- Wall bounce : rayon pour détecter les murs ----------------
func _check_wall_bounce() -> void:
	if not is_inside_tree():
		return

	var space  := get_world_3d().direct_space_state
	var from   := global_position
	var to     := global_position + direction * 0.6   # lookahead court

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	# On exclut les ennemis et le joueur pour ne rebondir que sur la géométrie
	query.collision_mask = 1   # layer 1 = monde statique

	var result := space.intersect_ray(query)
	if result.is_empty():
		return

	# Réflexion de la direction par rapport à la normale du mur
	var normal: Vector3 = result["normal"]
	normal.y = 0.0
	if normal.length_squared() < 0.001:
		return
	normal = normal.normalized()
	direction = direction.bounce(normal)
	_wall_bounces -= 1

	# Flash cyan sur le point d'impact mural
	_spawn_spark(get_tree().current_scene, result["position"],
		normal * 0.5 + Vector3.UP * 0.3, 1.2, C_NORMAL)
