# =============================================================
# CoopDeathScreen.gd — Overlay de mort en mode coopératif
# =============================================================
# Comportement :
#   • Flash blanc à la mort, on reste sur la propre POV du joueur.
#   • Panel tactique compact (bas-centre) après ~1.5 s.
#   • ← → / boutons < > pour cycler : soi-même + alliés vivants.
#   • Bordure rouge pulsante + scan lines + glitch sur le titre.
#   • Cleanup automatique au signal player_respawned.
# =============================================================
extends CanvasLayer

# --- Couleurs cohérentes avec HUD.gd --------------------------
const ALLY_COLORS: Array[Color] = [
	Color(1.00, 0.12, 0.12),
	Color(0.15, 1.00, 0.45),
	Color(0.70, 0.18, 1.00),
	Color(0.00, 0.85, 1.00),
]
const C_RED    := Color(0.90, 0.12, 0.12)
const C_CYAN   := Color(0.00, 0.85, 1.00)
const C_DARK   := Color(0.012, 0.030, 0.065, 0.90)
const C_BORDER := Color(0.90, 0.12, 0.12, 0.70)
const C_DIM    := Color(0.40, 0.55, 0.65, 0.60)

# --- Refs UI --------------------------------------------------
var _flash_rect:     ColorRect = null
var _panel:          Control   = null
var _border_rects:   Array[ColorRect] = []   # les 4 bords (pulsent)
var _title_label:    Label     = null
var _sub_label:      Label     = null
var _pov_label:      Label     = null
var _btn_prev:       Button    = null
var _btn_next:       Button    = null

# --- Spectateur -----------------------------------------------
var _spectate_list:   Array  = []
var _spectate_index:  int    = 0
var _active_ally_cam: Player = null
var _local_player:    Player = null

# --- Animations -----------------------------------------------
var _glitch_timer:  float = 0.0
var _is_glitching:  bool  = false
var _pulse_time:    float = 0.0   # pour bordure pulsante

# --- Entrée ---------------------------------------------------
var _switch_cooldown: float = 0.0

var _M: float = 1.6 if OS.has_feature("mobile") else 1.0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer        = 64
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_play_death_sequence()
	if _local_player != null and is_instance_valid(_local_player):
		_local_player.player_respawned.connect(_on_player_respawned, CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	_switch_cooldown = maxf(0.0, _switch_cooldown - delta)

	if not _panel.visible:
		return

	# ── Bordure pulsante ─────────────────────────────────────
	_pulse_time += delta * 2.2
	var pulse   := (sin(_pulse_time) * 0.5 + 0.5)   # 0…1
	var bc      := Color(C_RED.r, C_RED.g, C_RED.b, 0.35 + pulse * 0.50)
	for r in _border_rects:
		r.color = bc

	# ── Glitch titre ─────────────────────────────────────────
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		_is_glitching = not _is_glitching
		_glitch_timer = 0.055 if _is_glitching else randf_range(1.5, 4.0)
	if _is_glitching:
		_title_label.position.x += randf_range(-2.0, 2.0)
		_title_label.add_theme_color_override("font_color",
			C_RED.lerp(Color.WHITE, randf_range(0.0, 0.30)))
	else:
		_title_label.add_theme_color_override("font_color", C_RED)

	# ── Caméra spectateur ─────────────────────────────────────
	_update_spectate_camera()

	# ── Navigation clavier / manette ─────────────────────────
	if _switch_cooldown <= 0.0:
		if Input.is_action_just_pressed("ui_left"):
			_cycle(-1);  _switch_cooldown = 0.20
		elif Input.is_action_just_pressed("ui_right"):
			_cycle(1);   _switch_cooldown = 0.20


# =============================================================
# SÉQUENCE DE MORT
# =============================================================

func _play_death_sequence() -> void:
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.80)
	create_tween().tween_property(_flash_rect, "color", Color(1.0, 1.0, 1.0, 0.0), 0.40)

	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return

	_panel.show()
	_glitch_timer = randf_range(0.6, 1.8)
	_rebuild_spectate_list()
	_spectate_index = 0
	_apply_spectate(0)


# =============================================================
# SPECTATEUR
# =============================================================

func _rebuild_spectate_list() -> void:
	_spectate_list.clear()
	if _local_player != null and is_instance_valid(_local_player):
		_spectate_list.append(_local_player)
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Player and is_instance_valid(p) \
				and p != _local_player and not (p as Player).is_dead:
			_spectate_list.append(p)


func _cycle(dir: int) -> void:
	_rebuild_spectate_list()
	if _spectate_list.size() <= 1:
		return
	_spectate_index = (_spectate_index + dir + _spectate_list.size()) % _spectate_list.size()
	_apply_spectate(_spectate_index)


func _apply_spectate(index: int) -> void:
	if _active_ally_cam != null and is_instance_valid(_active_ally_cam):
		_active_ally_cam.camera.current = false
		_active_ally_cam = null

	if _spectate_list.is_empty():
		return
	index = clampi(index, 0, _spectate_list.size() - 1)
	var target := _spectate_list[index] as Player

	if target == _local_player:
		if is_instance_valid(_local_player):
			_local_player.camera.current = true
	else:
		if is_instance_valid(_local_player):
			_local_player.camera.current = false
		if is_instance_valid(target) and target.is_inside_tree():
			target.spring_arm.global_position = target.global_position + Vector3(0.0, 0.9, 0.0)
			if is_instance_valid(_local_player):
				target.spring_arm.rotation = _local_player.spring_arm.rotation
			target.camera.current = true
			_active_ally_cam = target

	_refresh_pov_label()


func _update_spectate_camera() -> void:
	if _active_ally_cam == null:
		return
	if not is_instance_valid(_active_ally_cam) \
			or not _active_ally_cam.is_inside_tree() \
			or _active_ally_cam.is_dead:
		_active_ally_cam = null
		if is_instance_valid(_local_player):
			_local_player.camera.current = true
		_rebuild_spectate_list()
		_spectate_index = 0
		_refresh_pov_label()
		return
	if not is_instance_valid(_local_player) or not _local_player.is_inside_tree():
		return
	_active_ally_cam.spring_arm.global_position = \
		_active_ally_cam.global_position + Vector3(0.0, 0.9, 0.0)
	_active_ally_cam.spring_arm.rotation = _local_player.spring_arm.rotation


func _refresh_pov_label() -> void:
	if _spectate_list.is_empty() or _pov_label == null:
		return
	var idx    := clampi(_spectate_index, 0, _spectate_list.size() - 1)
	var target := _spectate_list[idx] as Player
	var slot   := clampi(int(target.get("player_slot")), 0, ALLY_COLORS.size() - 1)
	var col    := ALLY_COLORS[slot]

	var display_name: String
	if target == _local_player:
		display_name = "Vous"
	else:
		var peer_id := target.get_multiplayer_authority()
		var nm      := get_node_or_null("/root/NetworkManager")
		display_name = "Joueur %d" % (slot + 1)
		if nm != null:
			var pd = nm.get("players")
			if pd is Dictionary:
				display_name = pd.get(peer_id, {}).get("name", display_name)

	_pov_label.add_theme_color_override("font_color", col)
	# Flèches visibles si plusieurs POV disponibles
	var arrow_l := "◀  " if _spectate_list.size() > 1 else "   "
	var arrow_r := "  ▶" if _spectate_list.size() > 1 else "   "
	_pov_label.text = "%s%s%s" % [arrow_l, display_name, arrow_r]


# =============================================================
# RESPAWN
# =============================================================

func _on_player_respawned() -> void:
	cleanup()

func cleanup() -> void:
	if _active_ally_cam != null and is_instance_valid(_active_ally_cam):
		_active_ally_cam.camera.current = false
	if is_instance_valid(_local_player):
		_local_player.camera.current = true
	queue_free()


# =============================================================
# BUILD UI
# =============================================================

func _build_ui() -> void:
	var M   := _M
	var vp  := get_viewport().get_visible_rect().size
	var vcx := vp.x * 0.5

	# ── Flash ──────────────────────────────────────────────────
	_flash_rect       = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	# ── Panel dimensions ───────────────────────────────────────
	var PW   := 400.0 * M
	var PH   := 112.0 * M
	var PX   := vcx - PW * 0.5
	var PY   := vp.y - PH - 20.0 * M
	var BT   := 1.5    # border thickness (px, unscaled — ColorRect)

	_panel              = Control.new()
	_panel.position     = Vector2(PX, PY)
	_panel.size         = Vector2(PW, PH)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.hide()
	add_child(_panel)

	# ── Fond ───────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color        = C_DARK
	bg.size         = Vector2(PW, PH)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)

	# ── Scan lines (lignes horizontales fines) ─────────────────
	var scan_root := Control.new()
	scan_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(scan_root)
	var line_count := int(PH / (3.0 * M))
	for i in line_count:
		var sl := ColorRect.new()
		sl.color       = Color(0.0, 0.0, 0.0, 0.10)
		sl.position    = Vector2(0.0, i * 3.0 * M)
		sl.size        = Vector2(PW, 1.0)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scan_root.add_child(sl)

	# ── Bordure pulsante (4 rects = top/bottom/left/right) ─────
	var borders: Array = [
		[Vector2(0,      0),       Vector2(PW, BT)],       # top
		[Vector2(0,      PH - BT), Vector2(PW, BT)],       # bottom
		[Vector2(0,      0),       Vector2(BT, PH)],       # left
		[Vector2(PW-BT,  0),       Vector2(BT, PH)],       # right
	]
	for b in borders:
		var r := ColorRect.new()
		r.position    = b[0]
		r.size        = b[1]
		r.color       = C_BORDER
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(r)
		_border_rects.append(r)

	# ── Barre accent rouge à gauche ────────────────────────────
	var accent := ColorRect.new()
	accent.color       = Color(C_RED, 0.90)
	accent.position    = Vector2(BT, BT)
	accent.size        = Vector2(3.0 * M, PH - BT * 2.0)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(accent)

	# ── Coins décoratifs ───────────────────────────────────────
	for r in _make_corners(Vector2.ZERO, Vector2(PW, PH), C_RED):
		_panel.add_child(r)

	# ── Zone titre (haut, ~46 % de la hauteur) ─────────────────
	var title_h := 64.0 * M
	var inner_x := 8.0 * M + 3.0 * M   # laisse place à l'accent

	# Pastille icône ◈
	var icon := Label.new()
	icon.text     = "◈"
	icon.position = Vector2(inner_x + 2.0 * M, 8.0 * M)
	icon.size     = Vector2(20.0 * M, 20.0 * M)
	icon.add_theme_font_size_override("font_size", int(11 * M))
	icon.add_theme_color_override("font_color", Color(C_RED, 0.80))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(icon)

	# Titre
	_title_label          = Label.new()
	_title_label.text     = "NEUTRALISÉ"
	_title_label.position = Vector2(inner_x, 6.0 * M)
	_title_label.size     = Vector2(PW - inner_x - 8.0 * M, 36.0 * M)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", int(24 * M))
	_title_label.add_theme_color_override("font_color",         C_RED)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.90))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title_label)

	# Sous-titre
	_sub_label          = Label.new()
	_sub_label.text     = "SYS · SIGNAL PERDU"
	_sub_label.position = Vector2(inner_x, 38.0 * M)
	_sub_label.size     = Vector2(PW - inner_x - 8.0 * M, 18.0 * M)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", int(9 * M))
	_sub_label.add_theme_color_override("font_color",         Color(0.45, 0.75, 0.85, 0.75))
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.70))
	_sub_label.add_theme_constant_override("outline_size", 2)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_sub_label)

	# ── Séparateur ─────────────────────────────────────────────
	var sep_y := 60.0 * M
	var sep := ColorRect.new()
	sep.color       = Color(C_RED, 0.22)
	sep.position    = Vector2(inner_x, sep_y)
	sep.size        = Vector2(PW - inner_x - 8.0 * M, 1.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(sep)

	# ── Ligne POV (navigation) ─────────────────────────────────
	var row_y    := sep_y + 8.0 * M
	var row_h    := 30.0 * M
	var btn_sz   := Vector2(30.0 * M, row_h)

	_btn_prev = _make_nav_btn("<", Vector2(inner_x, row_y), btn_sz)
	_btn_prev.pressed.connect(func(): _cycle(-1))
	_btn_prev.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.add_child(_btn_prev)

	_pov_label          = Label.new()
	_pov_label.text     = ""
	_pov_label.position = Vector2(inner_x + btn_sz.x + 4.0 * M, row_y)
	_pov_label.size     = Vector2(PW - inner_x * 2.0 - btn_sz.x * 2.0 - 8.0 * M, row_h)
	_pov_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pov_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_pov_label.add_theme_font_size_override("font_size", int(14 * M))
	_pov_label.add_theme_color_override("font_color",         C_CYAN)
	_pov_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.90))
	_pov_label.add_theme_constant_override("outline_size", 3)
	_pov_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_pov_label)

	_btn_next = _make_nav_btn(">",
		Vector2(PW - inner_x - btn_sz.x, row_y), btn_sz)
	_btn_next.pressed.connect(func(): _cycle(1))
	_btn_next.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.add_child(_btn_next)



# =============================================================
# HELPERS UI
# =============================================================

func _make_nav_btn(txt: String, pos: Vector2, sz: Vector2) -> Button:
	var btn := Button.new()
	btn.text     = txt
	btn.position = pos
	btn.size     = sz
	btn.add_theme_font_size_override("font_size", int(13 * _M))
	btn.add_theme_color_override("font_color",       C_CYAN)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var sn := StyleBoxFlat.new()
	sn.bg_color     = Color(0.0, 0.08, 0.16, 0.65)
	sn.border_color = Color(C_CYAN, 0.30)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(int(3 * _M))
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color     = Color(0.0, 0.22, 0.38, 0.85)
	sh.border_color = Color(C_CYAN, 0.85)
	sh.set_border_width_all(1)
	sh.set_corner_radius_all(int(3 * _M))
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sn)
	return btn


func _make_corners(origin: Vector2, sz: Vector2, color: Color) -> Array[ColorRect]:
	var M  := _M
	var cl := 9.0  * M
	var ct := 1.5
	var result: Array[ColorRect] = []
	for p in [
		[origin,                                     Vector2(cl, ct)],
		[origin,                                     Vector2(ct, cl)],
		[origin + Vector2(sz.x - cl, 0),             Vector2(cl, ct)],
		[origin + Vector2(sz.x - ct, 0),             Vector2(ct, cl)],
		[origin + Vector2(0,         sz.y - ct),     Vector2(cl, ct)],
		[origin + Vector2(0,         sz.y - cl),     Vector2(ct, cl)],
		[origin + Vector2(sz.x - cl, sz.y - ct),     Vector2(cl, ct)],
		[origin + Vector2(sz.x - ct, sz.y - cl),     Vector2(ct, cl)],
	]:
		var r := ColorRect.new()
		r.color        = Color(color, 0.80)
		r.position     = p[0]
		r.size         = p[1]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		result.append(r)
	return result
