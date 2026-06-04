# =============================================================
# slot_select.gd — Écran de sélection de slot de sauvegarde
# =============================================================

extends CanvasLayer

const COLOR_CYAN   := Color(0.0,  0.851, 1.0,  1.0)
const COLOR_GOLD   := Color(1.0,  0.82,  0.0,  1.0)
const COLOR_ORANGE := Color(1.0,  0.55,  0.1,  1.0)
const COLOR_RED    := Color(1.0,  0.3,   0.3,  1.0)
const COLOR_PANEL  := Color(0.04, 0.08,  0.12, 0.97)
const COLOR_DIM    := Color(0.35, 0.4,   0.45, 1.0)
const FONT_PATH    := "res://ui_theme/fonts/Xolonium-Regular.ttf"

var _M: float = 1.6 if OS.has_feature("mobile") else 1.0

var _font: FontFile = null
var _confirm_overlay: Control = null

func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	SaveData.reload_from_disk()
	_build_ui()

func _build_ui() -> void:
	var is_new := SaveData.new_game_mode

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.03, 0.07, 1.0) if is_new else Color(0.0, 0.04, 0.09, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 20)
	center.add_child(root_vbox)

	_build_header(root_vbox, is_new)

	var slots_vbox := VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(slots_vbox)

	for i in SaveData.MAX_SLOTS:
		slots_vbox.add_child(_build_slot_card(i, is_new))

	var back_btn := _make_button(tr("UI_SLOT_BACK"), _on_back, COLOR_CYAN, false)
	back_btn.custom_minimum_size = Vector2(160 * _M, 38 * _M)
	root_vbox.add_child(back_btn)

func _build_header(parent: VBoxContainer, is_new: bool) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	parent.add_child(vbox)

	if is_new:
		var title := _make_label(tr("UI_SLOT_TITLE_NEW"), int(32 * _M), COLOR_CYAN)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		var sub := _make_label(tr("UI_SLOT_SUB_NEW"), int(13 * _M), COLOR_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sub)
	else:
		var title := _make_label(tr("UI_SLOT_TITLE_LOAD"), int(32 * _M), COLOR_GOLD)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		var sub := _make_label(tr("UI_SLOT_SUB_LOAD"), int(13 * _M), COLOR_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sub)

	var sep := HSeparator.new()
	var sep_col := COLOR_CYAN if is_new else COLOR_GOLD
	sep.add_theme_color_override("color", Color(sep_col.r, sep_col.g, sep_col.b, 0.3))
	parent.add_child(sep)

func _build_slot_card(slot: int, is_new: bool) -> PanelContainer:
	var info: Dictionary = SaveData.get_slot_info(slot)
	var used: bool       = info["used"]
	if is_new:
		return _build_card_new_game(slot, info, used)
	else:
		return _build_card_continue(slot, info, used)

func _build_card_new_game(slot: int, info: Dictionary, used: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left   = 18.0 * _M; style.content_margin_right  = 18.0 * _M
	style.content_margin_top    = 12.0 * _M; style.content_margin_bottom = 12.0 * _M
	panel.custom_minimum_size   = Vector2(560 * _M, 0)

	if used:
		style.bg_color     = Color(0.08, 0.04, 0.04, 0.95)
		style.border_color = Color(0.6, 0.2, 0.2, 0.5)
	else:
		style.bg_color     = Color(0.0, 0.08, 0.14, 0.95)
		style.border_color = Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, 0.55)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(16 * _M))
	panel.add_child(hbox)

	var icon_vbox := VBoxContainer.new()
	icon_vbox.custom_minimum_size = Vector2(60 * _M, 0)
	icon_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(icon_vbox)

	var icon := _make_label("⚠" if used else "+", int((28 if used else 36) * _M), COLOR_ORANGE if used else COLOR_CYAN)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_vbox.add_child(icon)
	var num := _make_label("%d" % (slot + 1), int(11 * _M), COLOR_DIM)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_vbox.add_child(num)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", int(3 * _M))
	hbox.add_child(info_vbox)

	if used:
		info_vbox.add_child(_make_label(tr("UI_SLOT_USED"), int(11 * _M), COLOR_ORANGE))
		var level_txt: String = _get_level_display_name(info["level"])
		info_vbox.add_child(_make_label(level_txt, int(14 * _M), Color(0.7, 0.6, 0.6)))
		info_vbox.add_child(_make_stats_row(info["xp_level"], info["coins"], info["hp"], int(12 * _M), Color(0.6, 0.5, 0.5)))
		info_vbox.add_child(_make_label(_format_timestamp(info["timestamp"]), int(10 * _M), Color(0.4, 0.35, 0.35)))
	else:
		info_vbox.add_child(_make_label(tr("UI_SLOT_EMPTY"), int(14 * _M), COLOR_CYAN))
		info_vbox.add_child(_make_label(tr("UI_SLOT_EMPTY_DESC"), int(11 * _M), COLOR_DIM))

	var btn_vbox := VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(btn_vbox)

	var btn := _make_button(tr("UI_SLOT_OVERWRITE") if used else tr("UI_SLOT_CHOOSE"),
		func(): _on_new_game_confirm(slot) if used else _on_new_game(slot),
		COLOR_RED if used else COLOR_CYAN, true)
	btn.custom_minimum_size = Vector2(130 * _M, 40 * _M)
	btn_vbox.add_child(btn)
	return panel

func _build_card_continue(slot: int, info: Dictionary, used: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.content_margin_left   = 18.0 * _M; style.content_margin_right  = 18.0 * _M
	style.content_margin_top    = 12.0 * _M; style.content_margin_bottom = 12.0 * _M
	panel.custom_minimum_size   = Vector2(560 * _M, 0)

	if used:
		style.bg_color     = Color(0.02, 0.08, 0.14, 0.98)
		style.border_color = COLOR_GOLD
		style.set_border_width_all(2)
	else:
		style.bg_color     = Color(0.04, 0.05, 0.06, 0.6)
		style.border_color = Color(0.2, 0.22, 0.25, 0.4)
		style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.modulate = Color(1, 1, 1, 1) if used else Color(1, 1, 1, 0.45)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(16 * _M))
	panel.add_child(hbox)

	var icon_vbox := VBoxContainer.new()
	icon_vbox.custom_minimum_size = Vector2(60 * _M, 0)
	icon_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(icon_vbox)

	var icon := _make_label("▶" if used else "—", int(28 * _M), COLOR_GOLD if used else COLOR_DIM)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_vbox.add_child(icon)
	var num := _make_label("%d" % (slot + 1), int(11 * _M), COLOR_DIM)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_vbox.add_child(num)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", int(3 * _M))
	hbox.add_child(info_vbox)

	if used:
		var level_txt: String = _get_level_display_name(info["level"])
		info_vbox.add_child(_make_label(level_txt, int(16 * _M), Color(0.9, 0.95, 1.0)))
		info_vbox.add_child(_make_stats_row(info["xp_level"], info["coins"], info["hp"], int(13 * _M), COLOR_GOLD))
		info_vbox.add_child(_make_label(_format_timestamp(info["timestamp"]), int(11 * _M), COLOR_DIM))
	else:
		info_vbox.add_child(_make_label(tr("UI_SLOT_NONE"), int(14 * _M), COLOR_DIM))

	var btn_vbox := VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(btn_vbox)

	if used:
		var btn := _make_button(tr("UI_SLOT_LOAD_BTN"), func(): _on_continue(slot), COLOR_GOLD, true)
		btn.custom_minimum_size = Vector2(130 * _M, 40 * _M)
		btn_vbox.add_child(btn)
	else:
		var lbl := _make_label(tr("UI_SLOT_EMPTY_SHORT"), int(12 * _M), Color(0.3, 0.32, 0.35))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_vbox.add_child(lbl)

	return panel

func _on_continue(slot: int) -> void:
	SaveData.load_slot(slot)
	var level := SaveData.get_current_level()
	if level == "arena_first_level_1":
		SceneManager.load_level("res://scenes/levels/first_level/arena_first_level_1.tscn")
	elif level == "arena_first_level_2":
		SceneManager.load_level("res://scenes/levels/first_level/arena_first_level_2.tscn")
	elif level == "arena_first_level_3":
		SceneManager.load_level("res://scenes/levels/first_level/arena_first_level_3.tscn")
	else:
		SceneManager.load_level("res://scenes/levels/arena_base.tscn")

func _on_new_game(slot: int) -> void:
	SaveData.new_game(slot)
	SaveData.save_current()
	_show_tutorial_skip_dialog(slot)

func _show_tutorial_skip_dialog(slot: int) -> void:
	if _confirm_overlay != null: _confirm_overlay.queue_free()
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL; style.border_color = COLOR_CYAN; style.set_border_width_all(2)
	style.content_margin_left = 40.0 * _M; style.content_margin_right = 40.0 * _M
	style.content_margin_top = 32.0 * _M; style.content_margin_bottom = 32.0 * _M
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * _M))
	panel.add_child(vbox)
	vbox.add_child(_make_label(tr("UI_DIALOG_TUTO_TITLE"), int(16 * _M), COLOR_CYAN))
	vbox.add_child(_make_label(tr("UI_DIALOG_TUTO_MSG"), int(18 * _M), Color(0.9, 0.9, 1.0)))
	vbox.add_child(_make_label(tr("UI_DIALOG_TUTO_DESC"), int(12 * _M), COLOR_DIM))
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	var play_btn := _make_button(tr("UI_DIALOG_TUTO_PLAY"), func():
		overlay.queue_free()
		_confirm_overlay = null
		SaveData.set_current_level("arena_base")
		SaveData.save_current()
		# ← Au lieu de load_level directement, on va aux vidéos
		get_tree().change_scene_to_file("res://scenes/ui/tutorial_video.tscn")
	, COLOR_CYAN, true)
	play_btn.custom_minimum_size = Vector2(150 * _M, 44 * _M); hbox.add_child(play_btn)
	var skip_btn := _make_button(tr("UI_DIALOG_TUTO_SKIP"), func():
		overlay.queue_free()
		_confirm_overlay = null
		SaveData.set_current_level("arena_first_level_1"); SaveData.save_current()
		SceneManager.load_level("res://scenes/levels/first_level/arena_first_level_1.tscn")
	, COLOR_GOLD, false)
	skip_btn.custom_minimum_size = Vector2(150 * _M, 44 * _M); hbox.add_child(skip_btn)
	_confirm_overlay = overlay
	add_child(_confirm_overlay)

func _on_new_game_confirm(slot: int) -> void:
	if _confirm_overlay != null: _confirm_overlay.queue_free()
	_confirm_overlay = _build_confirm_dialog(
		tr("UI_DIALOG_CONFIRM_MSG"),
		func(): _on_new_game(slot),
		func(): _confirm_overlay.queue_free()
	)
	add_child(_confirm_overlay)

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _build_confirm_dialog(msg: String, on_yes: Callable, on_no: Callable) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL; style.border_color = COLOR_RED; style.set_border_width_all(2)
	style.content_margin_left = 36.0 * _M; style.content_margin_right = 36.0 * _M
	style.content_margin_top = 28.0 * _M; style.content_margin_bottom = 28.0 * _M
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(8 * _M))
	panel.add_child(vbox)
	vbox.add_child(_make_label(tr("UI_DIALOG_WARN"), int(16 * _M), COLOR_ORANGE))
	vbox.add_child(_make_label(msg, int(18 * _M), Color(0.9, 0.9, 1.0)))
	vbox.add_child(_make_label(tr("UI_DIALOG_CONFIRM_DESC"), int(12 * _M), COLOR_DIM))
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	var yes_btn := _make_button(tr("UI_SLOT_OVERWRITE"), on_yes, COLOR_RED, true)
	yes_btn.custom_minimum_size = Vector2(130 * _M, 40 * _M); hbox.add_child(yes_btn)
	var no_btn := _make_button(tr("UI_DIALOG_CANCEL"), on_no, COLOR_CYAN, false)
	no_btn.custom_minimum_size = Vector2(130 * _M, 40 * _M); hbox.add_child(no_btn)
	return overlay

func _format_timestamp(ts: int) -> String:
	if ts == 0: return ""
	var tz := Time.get_time_zone_from_system()
	var bias_sec := int(tz.get("bias", 0)) * 60
	var local_ts := ts + bias_sec
	var dt := Time.get_datetime_dict_from_unix_time(local_ts)
	return "%02d/%02d/%04d  %02d:%02d" % [dt["day"], dt["month"], dt["year"], dt["hour"], dt["minute"]]

func _make_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if _font: lbl.add_theme_font_override("font", _font)
	return lbl

func _make_button(text: String, callback: Callable, color: Color, filled: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	if _font: btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", int(13 * _M))
	var normal := StyleBoxFlat.new(); var hover := StyleBoxFlat.new()
	normal.set_border_width_all(1); hover.set_border_width_all(1)
	normal.set_corner_radius_all(3); hover.set_corner_radius_all(3)
	if filled:
		normal.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.9)
		normal.border_color = color
		hover.bg_color = Color(color.r * 0.45, color.g * 0.45, color.b * 0.45, 1.0)
		hover.border_color = color
		btn.add_theme_color_override("font_color", color)
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	else:
		normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		normal.border_color = Color(color.r, color.g, color.b, 0.4)
		hover.bg_color = Color(color.r * 0.1, color.g * 0.1, color.b * 0.1, 0.6)
		hover.border_color = color
		btn.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.7))
		btn.add_theme_color_override("font_hover_color", color)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(callback)
	return btn

## Ligne de stats avec icônes dessinées (compatibles vieux PC — pas d'emoji).
func _make_stats_row(xp_level: int, coins: int, hp: int, font_size: int, color: Color) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)

	var icon_size := Vector2(font_size + 2, font_size + 2)

	# ── Niveau ──
	var lv_icon := _LevelIcon.new()
	lv_icon.custom_minimum_size = icon_size
	hbox.add_child(lv_icon)
	var lv_lbl := _make_label(tr("UI_SLOT_STAT_LV") % xp_level, font_size, color)
	hbox.add_child(lv_lbl)

	var sep1 := _make_label("   ", font_size, color)
	hbox.add_child(sep1)

	# ── Pièces ──
	var coin_icon := _CoinIconSmall.new()
	coin_icon.custom_minimum_size = icon_size
	hbox.add_child(coin_icon)
	var coins_lbl := _make_label(tr("UI_SLOT_STAT_COINS") % coins, font_size, color)
	hbox.add_child(coins_lbl)

	var sep2 := _make_label("   ", font_size, color)
	hbox.add_child(sep2)

	# ── HP ──
	var hp_icon := _HpIcon.new()
	hp_icon.custom_minimum_size = icon_size
	hbox.add_child(hp_icon)
	var hp_lbl := _make_label(tr("UI_SLOT_STAT_HP") % hp, font_size, color)
	hbox.add_child(hp_lbl)

	return hbox


func _get_level_display_name(level_id: String) -> String:
	if level_id == "":
		return tr("UI_SLOT_LEVEL_UNKNOWN")
		
	match level_id:
		"arena_base":
			return tr("ARENA_BASE_TITLE")
		"arena_first_level_1":
			return tr("ARENA_FIRST_LEVEL_1_TITLE")
		_:
			# Si le niveau n'est pas dans la liste, on affiche l'ID brut par sécurité
			return level_id.capitalize()


# =============================================================
# ICÔNES DESSINÉES — compatibles toutes plateformes (pas d'emoji)
# =============================================================

## Étoile à 8 branches cyan — indicateur de niveau
class _LevelIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in 8:
			var a   := TAU / 8.0 * float(i) - PI / 2.0
			var rad := r if i % 2 == 0 else r * 0.38
			pts.append(c + Vector2(cos(a) * rad, sin(a) * rad))
			cols.append(Color(0.0, 0.85, 1.0))
		draw_polygon(pts, cols)


## Disque or avec reflet — icône pièce (même rendu que le HUD)
class _CoinIconSmall extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c + Vector2(1.0, 1.5), r, Color(0.0, 0.0, 0.0, 0.35))
		draw_circle(c, r, Color(1.0, 0.80, 0.0))
		draw_arc(c, r * 0.68, 0.0, TAU, 24, Color(0.55, 0.38, 0.0, 0.55), 1.5)
		draw_circle(c + Vector2(-r * 0.22, -r * 0.22), r * 0.42, Color(1.0, 0.96, 0.55, 0.50))


## Cœur rouge — indicateur HP
class _HpIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.42
		var col := Color(0.95, 0.15, 0.15)
		# Deux cercles pour les bosses du haut
		draw_circle(c + Vector2(-s * 0.42, -s * 0.18), s * 0.53, col)
		draw_circle(c + Vector2( s * 0.42, -s * 0.18), s * 0.53, col)
		# Triangle pour la pointe basse
		draw_polygon(PackedVector2Array([
			c + Vector2(-s * 0.95,  0.0),
			c + Vector2( s * 0.95,  0.0),
			c + Vector2( 0.0,       s * 0.92),
		]), PackedColorArray([col, col, col]))
