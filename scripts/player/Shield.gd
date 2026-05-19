# =============================================================
# Shield.gd — Rotation du bouclier + logique de parade + visuel
# Rebound Protocol · Conventions : snake_case vars, PascalCase class
# =============================================================
# Le visuel (MeshInstance3D + ShaderMaterial) est configuré dans
# l'éditeur sur le nœud enfant "ShieldMesh". Le script récupère
# le matériau au démarrage pour gérer les flashes de parade.
# =============================================================
class_name Shield
extends Node3D

# --- Exports -----------------------------------------------------
@export var orbit_radius: float = 0.8

# --- Références nœuds --------------------------------------------
@onready var parry_timer:    ParryTimer      = $ParryTimer
@onready var hit_area:       Area3D          = $HitArea
@onready var _mesh_instance: MeshInstance3D  = $ShieldMesh

# --- Scène de la balle renvoyée ----------------------------------
var _bullet_reflected_scene: PackedScene = preload("res://scenes/enemies/bullet_reflected.tscn")

# --- Sons bouclier -----------------------------------------------
const _SFX_BLOCK:   AudioStream = preload("res://audio/sfx/shield/block.wav")   # Balle bloquée
const _SFX_REFLECT: AudioStream = preload("res://audio/sfx/shield/reflect.wav") # Balle renvoyée
var _sfx_shield: AudioStreamPlayer = null

# Combo : chaque balle successive dans la fenêtre fait monter le pitch
const _COMBO_WINDOW:    float = 0.55   # secondes avant reset du combo
const _COMBO_MAX:       int   = 6      # pitch plafonné à ce nombre de hits
var _block_combo:       int   = 0
var _block_combo_timer: float = 0.0
var _reflect_combo:     int   = 0
var _reflect_combo_timer: float = 0.0

# --- Variables d'état --------------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var _shield_direction: Vector3 = Vector3.FORWARD
var _pending_bullet: Bullet = null

# Valeurs de base avant upgrades (pour recalcul idempotent)
var _base_orbit_radius:      float   = 0.0
var _base_mesh_scale:        Vector3 = Vector3.ONE
var _base_parry_window:      float   = 0.0
var _base_max_parry_window:  float   = 0.0

# --- Compétences runtime ----------------------------------------
var _parry_regen_cd:  float = 0.0    # cooldown parry_hp_regen (5 s)
var _mirror_timer:    float = 0.0    # durée restante du bouclier miroir (3 s)
const _MIRROR_RANGE    := 5.0
const _MIRROR_DURATION := 3.0

# --- Matériau (lu depuis ShieldMesh dans l'éditeur) --------------
var _shield_mat: ShaderMaterial
var _base_color: Color


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	player = get_parent()
	camera = get_viewport().get_camera_3d()

	# Player polyphonique pour les sons bouclier (block + reflect)
	_sfx_shield = AudioStreamPlayer.new()
	_sfx_shield.bus = "SFX"
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 4
	_sfx_shield.stream = poly
	add_child(_sfx_shield)
	_sfx_shield.play()

	hit_area.area_entered.connect(_on_bullet_entered)
	parry_timer.parry_resolved.connect(_on_parry_resolved)

	# Chercher le ShaderMaterial : d'abord en Material Override, sinon en surface 0
	_shield_mat = _mesh_instance.material_override as ShaderMaterial
	if _shield_mat == null:
		_shield_mat = _mesh_instance.get_surface_override_material(0) as ShaderMaterial
	if _shield_mat == null:
		push_error("Shield: aucun ShaderMaterial trouvé sur ShieldMesh — vérifie l'éditeur.")
		return

	# ==============================================================
	# COULEURS CORRIGÉES : Vrai Bleu Cyan (Zéro rouge pour éviter le blanc)
	# ==============================================================
	_shield_mat.set_shader_parameter("shield_color", Color(0.0, 0.2, 0.8, 0.85)) # Bleu très profond pour le fond
	_shield_mat.set_shader_parameter("border_color", Color(0.0, 0.8, 1.0, 1.0))  # Cyan pur et saturé pour les lignes
	_shield_mat.set_shader_parameter("intensity", 3.0)                           # Un peu baissé pour garder la couleur
	# ===============================================================

	# Lire la couleur de base depuis le matériau (pour les clignotements de parade)
	_base_color = _shield_mat.get_shader_parameter("shield_color")

	# ── Stocker les valeurs de base AVANT d'appliquer les upgrades ──
	_base_orbit_radius     = orbit_radius
	_base_mesh_scale       = _mesh_instance.scale
	_base_parry_window     = parry_timer.perfect_window
	_base_max_parry_window = parry_timer.max_parry_window
	_apply_save_upgrades()


func _apply_save_upgrades() -> void:
	refresh_skill_upgrades()   # Délègue au recalcul unifié save + skill


## Recalcule orbit_radius, max_parry_window et perfect_window en combinant
## les upgrades de boutique (SaveData) ET les multiplicateurs de compétence (XpManager).
## Idempotent — peut être appelée plusieurs fois sans effet de bord.
func refresh_skill_upgrades() -> void:
	# — Taille du bouclier —
	var save_size  := (1.0 + SaveData.get_upgrade_value("shield_size")) if SaveData.active_slot >= 0 else 1.0
	var skill_size := XpManager.shield_radius_mult if get_tree().root.has_node("XpManager") else 1.0
	orbit_radius         = _base_orbit_radius * save_size * skill_size
	_mesh_instance.scale = _base_mesh_scale   * save_size * skill_size

	# — Durée parade —
	var save_dur  := (1.0 + SaveData.get_upgrade_value("shield_duration")) if SaveData.active_slot >= 0 else 1.0
	var skill_dur := XpManager.shield_duration_mult if get_tree().root.has_node("XpManager") else 1.0
	parry_timer.max_parry_window = _base_max_parry_window * save_dur * skill_dur

	# — Fenêtre critique —
	var extra_frames := SaveData.get_upgrade_value("parry_window") if SaveData.active_slot >= 0 else 0.0
	var skill_win    := XpManager.parry_window_mult if get_tree().root.has_node("XpManager") else 1.0
	parry_timer.perfect_window = _base_parry_window * skill_win + extra_frames / 60.0


## Rappelée depuis Player.refresh_upgrades() après un achat en boutique.
func refresh_upgrades() -> void:
	refresh_skill_upgrades()   # Idempotent grâce aux valeurs de base


func _process(delta: float) -> void:
	_orbit_toward_mouse()
	# Décrémenter les timers de combo — reset quand la fenêtre expire
	if _block_combo_timer > 0.0:
		_block_combo_timer -= delta
		if _block_combo_timer <= 0.0:
			_block_combo = 0
	if _reflect_combo_timer > 0.0:
		_reflect_combo_timer -= delta
		if _reflect_combo_timer <= 0.0:
			_reflect_combo = 0
	# Timers des compétences
	if _parry_regen_cd > 0.0:
		_parry_regen_cd -= delta
	if _mirror_timer > 0.0:
		_mirror_timer -= delta


# =============================================================
# ROTATION ORBITALE
# =============================================================

func _orbit_toward_mouse() -> void:
	if camera == null:
		return

	var dir := Vector3.ZERO

	# --- Joystick mobile prioritaire ---
	var p := player as Player
	if p != null and p._joystick_aim_dir.length_squared() > 0.04:
		var cb        := camera.global_transform.basis
		var cam_right := Vector3(cb.x.x, 0.0, cb.x.z).normalized()
		var cam_fwd   := -Vector3(cb.z.x, 0.0, cb.z.z).normalized()
		dir = cam_right * p._joystick_aim_dir.x - cam_fwd * p._joystick_aim_dir.y
		dir.y = 0.0
	else:
		# --- Souris (desktop) ---
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_orig  := camera.project_ray_origin(mouse_pos)
		var ray_dir   := camera.project_ray_normal(mouse_pos)
		var plane_y   := player.global_position.y

		if abs(ray_dir.y) > 0.001:
			var t := (plane_y - ray_orig.y) / ray_dir.y
			if t > 0.0:
				var world_pos := ray_orig + ray_dir * t
				dir = (world_pos - player.global_position)
				dir.y = 0.0

		# Souris vers le ciel (t ≤ 0) → projection horizontale du rayon
		if dir.length() < 0.01:
			dir = Vector3(ray_dir.x, 0.0, ray_dir.z)

	if dir.length() < 0.01:
		return

	dir               = dir.normalized()
	_shield_direction  = dir
	global_position    = player.global_position + dir * orbit_radius
	global_position.y  = player.global_position.y
	global_rotation.y  = atan2(dir.x, dir.z)


# =============================================================
# DÉTECTION BALLE
# =============================================================

func _on_bullet_entered(area: Area3D) -> void:
	if not area is Bullet:
		return

	# Bouclier miroir actif : renvoyer automatiquement sans parry
	if _mirror_timer > 0.0 and get_tree().root.has_node("XpManager") and XpManager.has_skill("mirror_shield"):
		_spawn_reflected_bullet(10, false)
		_flash_shield(Color(0.6, 0.3, 1.0, 1.0), 0.18)
		area.queue_free()
		return

	# Si le cooldown est actif (parade vient de se résoudre), absorber
	# la balle directement — sans ça elle passe à travers car on_bullet_impact()
	# ignore les appels pendant le cooldown.
	if parry_timer.is_on_cooldown():
		# Appliquer le même état que la parade précédente (lu directement depuis le timer)
		match parry_timer.get_last_resolved_state():
			ParryTimer.ParryState.STANDARD:
				_spawn_reflected_bullet(10, false)
				_flash_shield(Color(1.0, 1.0, 1.0, 1.0), 0.2)
				_play_reflect_sfx()
			ParryTimer.ParryState.CRITICAL:
				_spawn_reflected_bullet(25, true)
				_flash_shield(Color(1.0, 0.75, 0.0, 1.0), 0.3)
				_play_reflect_sfx()
			_:
				_flash_shield(Color(0.5, 0.6, 0.8, 0.6), 0.15)
				_play_block_sfx()
		area.queue_free()
		return
	_pending_bullet = area
	parry_timer.on_bullet_impact()


# =============================================================
# RÉSOLUTION DE LA PARADE
# =============================================================

func _on_parry_resolved(state: ParryTimer.ParryState) -> void:
	if _pending_bullet == null:
		return

	var has_xp := get_tree().root.has_node("XpManager")

	match state:
		ParryTimer.ParryState.ABSORB:
			_pending_bullet.queue_free()
			_flash_shield(Color(0.5, 0.6, 0.8, 0.6), 0.25)
			_play_block_sfx()

		ParryTimer.ParryState.STANDARD:
			_spawn_reflected_bullet(10, false)
			_spawn_impact_vfx(_pending_bullet.global_position, false) # <--- NOUVEAU !
			_pending_bullet.queue_free()
			_flash_shield(Color(1.0, 1.0, 1.0, 1.0), 0.3)
			_play_reflect_sfx()
			# Régénération HP (parry_hp_regen — commune)
			_apply_parry_regen(has_xp)
			# Invulnérabilité flash (invuln_flash — légendaire)
			if has_xp and XpManager.has_skill("invuln_flash") and player is Player:
				(player as Player).grant_invincibility(0.5)

		ParryTimer.ParryState.CRITICAL:
			_spawn_reflected_bullet(25, true)
			_spawn_impact_vfx(_pending_bullet.global_position, true)
			_pending_bullet.queue_free()
			_flash_shield(Color(1.0, 0.75, 0.0, 1.0), 0.45)
			_reflect_combo        = min(_reflect_combo + 1, _COMBO_MAX)
			_reflect_combo_timer  = _COMBO_WINDOW
			_play_shield_sfx(_SFX_REFLECT, 0.0, randf_range(0.88, 0.94))

			# Soin parade critique boutique (upgrade "parry_heal")
			var heal_amount: int = int(SaveData.get_upgrade_value("parry_heal")) if SaveData.active_slot >= 0 else 0
			if heal_amount > 0 and player is Player:
				(player as Player).heal(heal_amount)

			# Soin parade critique (compétence "critical_parry_heal" — rare)
			if has_xp and XpManager.has_skill("critical_parry_heal") and player is Player:
				(player as Player).heal(3)

			# Régénération HP commune
			_apply_parry_regen(has_xp)

			# Shield nova (légendaire)
			if has_xp and XpManager.has_skill("shield_nova"):
				_do_shield_nova()

			# Bouclier miroir : armer pour 3 secondes (épique)
			if has_xp and XpManager.has_skill("mirror_shield"):
				_mirror_timer = _MIRROR_DURATION

			# Invulnérabilité flash (légendaire)
			if has_xp and XpManager.has_skill("invuln_flash") and player is Player:
				(player as Player).grant_invincibility(0.5)

	_pending_bullet = null


# =============================================================
# FLASH DE PARADE
# =============================================================

func _flash_shield(flash_color: Color, duration: float) -> void:
	if _shield_mat == null:
		return

	_shield_mat.set_shader_parameter("shield_color", flash_color)
	_shield_mat.set_shader_parameter("intensity",    2.5)

	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		func(c: Color): _shield_mat.set_shader_parameter("shield_color", c),
		flash_color, _base_color, duration
	)
	tween.tween_method(
		func(v: float): _shield_mat.set_shader_parameter("intensity", v),
		2.5, 1.5, duration
	)


# =============================================================
# RENVOI DE BALLE
# =============================================================

func _spawn_reflected_bullet(bullet_damage: int, is_critical: bool = false) -> void:
	# Dégâts : upgrade boutique × multiplicateur skill return_damage_boost
	var dmg_save  := 1.0 + (SaveData.get_upgrade_value("parry_damage") if SaveData.active_slot >= 0 else 0.0)
	var dmg_skill := XpManager.return_damage_mult if get_tree().root.has_node("XpManager") else 1.0
	var final_dmg := int(round(float(bullet_damage) * dmg_save * dmg_skill))

	var has_xp := get_tree().root.has_node("XpManager")

	# Balle principale
	var bullet: BulletReflected = _bullet_reflected_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.init(global_position, _shield_direction, final_dmg, is_critical)

	# Double renvoi (rare) : deuxième balle à ±15°
	if has_xp and XpManager.has_skill("double_bullet"):
		var dir2 := _shield_direction.rotated(Vector3.UP, PI / 12.0)
		var bullet2: BulletReflected = _bullet_reflected_scene.instantiate()
		get_tree().current_scene.add_child(bullet2)
		bullet2.init(global_position, dir2, final_dmg, is_critical)

	# Balle omnidirectionnelle (légendaire) : balle opposée
	if has_xp and XpManager.has_skill("omni_bullet"):
		var bullet3: BulletReflected = _bullet_reflected_scene.instantiate()
		get_tree().current_scene.add_child(bullet3)
		bullet3.init(global_position, -_shield_direction, final_dmg, false, true)


# =============================================================
# SON DE BLOCK
# =============================================================

func _play_shield_sfx(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null or _sfx_shield == null:
		return
	var pb := _sfx_shield.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb:
		pb.play_stream(stream, 0.0, vol_db, pitch)


## Son de block : pitch monte légèrement à chaque balle successive dans la fenêtre combo.
func _play_block_sfx() -> void:
	_block_combo        = min(_block_combo + 1, _COMBO_MAX)
	_block_combo_timer  = _COMBO_WINDOW
	# Pitch : +0.04 par hit (1.0 → 1.24 max), variation aléatoire réduite
	var pitch: float = 0.95 + (_block_combo - 1) * 0.04 + randf_range(-0.02, 0.02)
	# Volume : légèrement plus présent au fil du combo
	var vol: float   = -9.0 + (_block_combo - 1) * 0.8
	_play_shield_sfx(_SFX_BLOCK, vol, pitch)


## Soin de parade si compétence parry_hp_regen acquise et cooldown écoulé.
func _apply_parry_regen(has_xp: bool) -> void:
	if not has_xp or not XpManager.has_skill("parry_hp_regen"):
		return
	if _parry_regen_cd > 0.0:
		return
	if player is Player:
		(player as Player).heal(1)
	_parry_regen_cd = 5.0


## Onde circulaire qui blesse tous les ennemis visibles (shield_nova).
func _do_shield_nova() -> void:
	const NOVA_RANGE  := 9.0
	const NOVA_DAMAGE := 15
	var enemies := get_tree().get_nodes_in_group("enemies")
	
	for node: Node in enemies:
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.has_method("take_damage"):			
			continue
			
		var dist := (node as Node3D).global_position.distance_to(global_position)
		if dist <= NOVA_RANGE:
			(node as Enemy).take_damage(NOVA_DAMAGE, true)

	# Visuel : anneau d'onde
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius  = 0.1
	mesh.outer_radius  = 0.3
	mesh.rings         = 16
	mesh.ring_segments = 24
	ring.mesh          = mesh
	ring.rotation.x    = PI * 0.5
	ring.global_position = global_position
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = Color(1.0, 0.80, 0.0, 0.9)
	mat.emission_enabled          = true
	mat.emission                  = Color(1.0, 0.70, 0.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.set_surface_override_material(0, mat)
	get_tree().current_scene.add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(NOVA_RANGE * 2.0, 1, NOVA_RANGE * 2.0), 0.40)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.40)
	tw.tween_callback(ring.queue_free)


## Son de reflect : pitch monte plus franchement — chaîne de renvois très satisfaisante.
func _play_reflect_sfx() -> void:
	_reflect_combo        = min(_reflect_combo + 1, _COMBO_MAX)
	_reflect_combo_timer  = _COMBO_WINDOW
	# Pitch : +0.06 par hit (1.0 → 1.30 max)
	var pitch: float = 1.0 + (_reflect_combo - 1) * 0.06 + randf_range(-0.02, 0.02)
	# Volume : monte avec le combo pour souligner la chaîne
	var vol: float   = -5.0 + (_reflect_combo - 1) * 1.0
	_play_shield_sfx(_SFX_REFLECT, vol, pitch)


func _spawn_impact_vfx(hit_pos: Vector3, is_critical: bool) -> void:
	var vfx_root = Node3D.new()
	get_tree().current_scene.add_child(vfx_root)
	vfx_root.global_position = hit_pos
	
	var look_dir = (hit_pos - player.global_position).normalized()
	var up_vec = Vector3.UP if abs(look_dir.y) < 0.99 else Vector3.RIGHT
	vfx_root.look_at(hit_pos + look_dir, up_vec)
	
	# Couleurs un peu plus denses/visibles (alpha à 0.9)
	var color_core = Color(1.0, 1.0, 1.0, 0.9)
	var color_glow = Color(1.0, 0.6, 0.0, 0.9) if is_critical else Color(0.2, 0.7, 1.0, 0.9)
	
	var tw = vfx_root.create_tween().set_parallel(true)
	
	# ==========================================
	# 1. ÉCLAT CENTRAL (Un peu plus gros)
	# ==========================================
	var core = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.08  # Plus gros que l'ancien (0.05)
	sphere.height = 0.16
	core.mesh = sphere
	var mat_core = StandardMaterial3D.new()
	mat_core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_core.albedo_color = color_core
	core.set_surface_override_material(0, mat_core)
	vfx_root.add_child(core)
	
	tw.tween_property(core, "scale", Vector3(2.0, 2.0, 2.0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "scale", Vector3.ZERO, 0.15).set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# ==========================================
	# 2. ONDE LÉGÈRE (Anneau plus visible)
	# ==========================================
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.20
	torus.outer_radius = 0.23 # Plus épais
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	ring.rotation.x = PI / 2.0
	
	var mat_ring = StandardMaterial3D.new()
	mat_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_ring.albedo_color = color_glow
	ring.set_surface_override_material(0, mat_ring)
	vfx_root.add_child(ring)
	
	ring.scale = Vector3(0.5, 0.5, 0.5)
	tw.tween_property(ring, "scale", Vector3(2.2, 2.2, 2.2), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat_ring, "albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# ==========================================
	# 3. ÉTINCELLES (Plus lisibles)
	# ==========================================
	var num_spikes = 6 if is_critical else 4 # Légèrement plus d'étincelles
	for i in range(num_spikes):
		var pivot = Node3D.new()
		vfx_root.add_child(pivot)
		
		var angle = (TAU / num_spikes) * i + randf_range(-0.2, 0.2)
		pivot.rotation.z = angle
		pivot.rotation.x = randf_range(-0.1, 0.1)
		
		var spike = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.01, 1.0, 0.01) # Épaisseur x2 par rapport à avant !
		spike.mesh = box
		
		var mat_spike = StandardMaterial3D.new()
		mat_spike.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_spike.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_spike.albedo_color = color_glow
		spike.set_surface_override_material(0, mat_spike)
		pivot.add_child(spike)
		
		spike.position.y = 0.1
		spike.scale.y = 0.0
		
		var spike_len = randf_range(0.5, 0.9) # S'étirent un peu plus
		tw.tween_property(spike, "scale:y", spike_len, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spike, "position:y", 0.5, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spike, "scale:y", 0.0, 0.15).set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Nettoyage après 0.35s
	tw.tween_callback(vfx_root.queue_free).set_delay(0.35)
