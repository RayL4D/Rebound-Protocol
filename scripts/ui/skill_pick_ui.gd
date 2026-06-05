# =============================================================
# SkillPickUI — Interface de choix de compétence au level-up
# Rebound Protocol
# =============================================================
extends CanvasLayer

signal skill_chosen(id: String)

# --- Palette ---------------------------------------------------
const C_PANEL    := Color(0.03, 0.05, 0.12, 0.98)
const C_GOLD     := Color(1.00, 0.82, 0.00)
const C_CYAN     := Color(0.00, 0.85, 1.00)
const C_TEXT_DIM := Color(0.58, 0.64, 0.72)

# --- Symboles par rareté ---------------------------------------
const RARITY_SYMBOLS: Dictionary = {
	SkillCatalogue.Rarity.COMMON:    "◆",
	SkillCatalogue.Rarity.UNCOMMON:  "◈",
	SkillCatalogue.Rarity.RARE:      "❖",
	SkillCatalogue.Rarity.EPIC:      "✦",
	SkillCatalogue.Rarity.LEGENDARY: "★",
}

# --- Coins décoratifs ------------------------------------------
const _CL := 10.0
const _CT := 2.0

# --- État ------------------------------------------------------
var _level:         int   = 0
var _skills:        Array = []
var _cards_visible: bool  = false   # bloque [1]/[2] pendant l'animation

# Infos rareté (communes aux deux phases)
var _rarity_val: int   = 0
var _rc:         Color = Color.WHITE
var _rn:         String = ""

var _M: float = 1.6 if OS.has_feature("mobile") else 1.0
var _is_waiting: bool = false   # true → ne pas queue_free après le choix (coop)

var _sfx_hover:  AudioStreamPlayer = null
var _sfx_choose: AudioStreamPlayer = null
const _SFX_HOVER_PATH  := "res://audio/sfx/ui/btn_hover.wav"
const _SFX_CHOOSE_PATH := "res://audio/sfx/ui/btn_click.wav"


# =============================================================
# SETUP
# =============================================================

func setup(new_level: int, skills: Array) -> void:
	_level        = new_level
	_skills       = skills
	process_mode  = Node.PROCESS_MODE_ALWAYS
	layer         = 60
	_sfx_hover    = _make_sfx()
	_sfx_choose   = _make_sfx()
	get_tree().paused = true
	_build_ui()


func _make_sfx() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus          = "SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


# =============================================================
# PHASE 1 — Suspense : annonce + tirage de rareté
# =============================================================

func _build_ui() -> void:
	_rarity_val = _skills[0].get("rarity", SkillCatalogue.Rarity.COMMON) if _skills.size() > 0 else 0
	_rc         = SkillCatalogue.RARITY_COLORS[_rarity_val]
	_rn         = tr(SkillCatalogue.RARITY_NAMES[_rarity_val])

	var vp := get_viewport().get_visible_rect().size

	# ── Overlay foncé ──────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color        = Color(0.0, 0.01, 0.05, 0.0)
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Flash couleur (révélation)
	var flash := ColorRect.new()
	flash.color        = Color(_rc.r, _rc.g, _rc.b, 0.0)
	flash.process_mode = Node.PROCESS_MODE_ALWAYS
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	# ── Panneau d'annonce (440 × 320, centré) ─────────────────
	var AW := 440.0 * _M
	var AH := 320.0 * _M
	var announce := Control.new()
	announce.size         = Vector2(AW, AH)
	announce.position     = Vector2((vp.x - AW) * 0.5, (vp.y - AH) * 0.5)
	announce.modulate     = Color(1.0, 1.0, 1.0, 0.0)
	announce.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(announce)

	# Fond + contour
	var a_sb := StyleBoxFlat.new()
	a_sb.bg_color    = C_PANEL
	a_sb.border_color = Color(C_CYAN, 0.40)
	a_sb.set_border_width_all(1)
	a_sb.set_corner_radius_all(14)
	var a_panel := PanelContainer.new()
	a_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	a_panel.add_theme_stylebox_override("panel", a_sb)
	a_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce.add_child(a_panel)

	# Ligne déco en haut
	var a_top := ColorRect.new()
	a_top.color    = Color(C_CYAN, 0.55)
	a_top.position = Vector2(30.0, 0.0)
	a_top.size     = Vector2(AW - 60.0, 3.0)
	a_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce.add_child(a_top)

	var ann_corners := _make_corners(Vector2(4, 4), Vector2(AW - 8, AH - 8), Color(C_CYAN, 0.50))
	for cr in ann_corners:
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		announce.add_child(cr)

	# VBox contenu
	var a_vbox := VBoxContainer.new()
	a_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	a_vbox.offset_left   =  24.0 * _M
	a_vbox.offset_right  = -24.0 * _M
	a_vbox.offset_top    =  18.0 * _M
	a_vbox.offset_bottom = -18.0 * _M
	a_vbox.add_theme_constant_override("separation", int(10 * _M))
	a_vbox.process_mode  = Node.PROCESS_MODE_ALWAYS
	announce.add_child(a_vbox)

	# Titre — éclairs dessinés flanquant le texte
	var a_title_row := HBoxContainer.new()
	a_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	a_title_row.add_theme_constant_override("separation", 8)
	a_vbox.add_child(a_title_row)
	var a_bolt_l := _LightningIcon.new()
	a_bolt_l.custom_minimum_size = Vector2(22 * _M, 28 * _M)
	a_title_row.add_child(a_bolt_l)
	var a_header := Label.new()
	a_header.text = tr("UI_SKILL_LEVEL_TITLE") % _level
	a_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a_header.add_theme_font_size_override("font_size", int(28 * _M))
	a_header.add_theme_color_override("font_color", C_GOLD)
	a_header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	a_header.add_theme_constant_override("outline_size", 5)
	a_title_row.add_child(a_header)
	var a_bolt_r := _LightningIcon.new()
	a_bolt_r.custom_minimum_size = Vector2(22 * _M, 28 * _M)
	a_title_row.add_child(a_bolt_r)

	# Sous-titre
	var a_sub := Label.new()
	a_sub.text = tr("UI_SKILL_DRAWING")
	a_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a_sub.add_theme_font_size_override("font_size", int(11 * _M))
	a_sub.add_theme_color_override("font_color", Color(C_CYAN, 0.60))
	a_vbox.add_child(a_sub)

	# Séparateur fin
	var a_sep := ColorRect.new()
	a_sep.color               = Color(C_GOLD, 0.18)
	a_sep.custom_minimum_size = Vector2(0, 1)
	a_sep.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	a_vbox.add_child(a_sep)

	# ── Boîte de tirage (symbole + couleur animée) ─────────────
	var cycle_box := Control.new()
	cycle_box.custom_minimum_size  = Vector2(0, 120 * _M)
	cycle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cycle_box.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	a_vbox.add_child(cycle_box)

	var cycle_border := ColorRect.new()
	cycle_border.color    = Color(C_CYAN, 0.35)
	cycle_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cycle_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_box.add_child(cycle_border)

	var cycle_bg := ColorRect.new()
	cycle_bg.color    = Color(0.02, 0.04, 0.10, 1.0)
	cycle_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cycle_bg.offset_left   = 2.0
	cycle_bg.offset_right  = -2.0
	cycle_bg.offset_top    = 2.0
	cycle_bg.offset_bottom = -2.0
	cycle_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	cycle_box.add_child(cycle_bg)

	var cycle_sym := Label.new()
	cycle_sym.text = "?"
	cycle_sym.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cycle_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cycle_sym.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	cycle_sym.add_theme_font_size_override("font_size", int(54 * _M))
	cycle_sym.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
	cycle_sym.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.70))
	cycle_sym.add_theme_constant_override("outline_size", 5)
	cycle_sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_box.add_child(cycle_sym)

	# Label rareté (sous la boîte)
	var cycle_rar := Label.new()
	cycle_rar.text = "???"
	cycle_rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cycle_rar.add_theme_font_size_override("font_size", int(13 * _M))
	cycle_rar.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
	a_vbox.add_child(cycle_rar)

	# ── Séquence de tirage ─────────────────────────────────────
	var all_r := [
		SkillCatalogue.Rarity.COMMON,
		SkillCatalogue.Rarity.UNCOMMON,
		SkillCatalogue.Rarity.RARE,
		SkillCatalogue.Rarity.EPIC,
		SkillCatalogue.Rarity.LEGENDARY,
	]

	# 10 étapes rapides aléatoires + 4 ralentissements + 1 cible finale
	var sequence: Array[int] = []
	for _i in 10:
		sequence.append(all_r[randi() % all_r.size()])
	for _i in 4:
		sequence.append(all_r[randi() % all_r.size()])
	sequence.append(_rarity_val)   # toujours la rareté réelle en dernier

	# Délais croissants : rapide → lent
	var delays: Array[float] = []
	for _i in 10: delays.append(0.07)
	for d in [0.12, 0.18, 0.27, 0.38]: delays.append(d)
	delays.append(0.52)   # pause finale avant révélation

	# ── Tween principal ────────────────────────────────────────
	var tw := create_tween()

	# Fade-in overlay + panneau
	tw.tween_property(bg,       "color:a",    0.86, 0.25)
	tw.tween_property(announce, "modulate:a", 1.0,  0.28)
	tw.tween_interval(0.32)   # pause dramatique avant le tirage

	# Étapes du tirage
	for i in sequence.size():
		tw.tween_interval(delays[i])
		var r:       int    = sequence[i]
		var c:       Color  = SkillCatalogue.RARITY_COLORS[r]
		var sym_str: String = RARITY_SYMBOLS.get(r, "◆")
		var nm_str:  String = tr(SkillCatalogue.RARITY_NAMES[r])
		tw.tween_callback(func() -> void:
			cycle_sym.text = sym_str
			cycle_sym.add_theme_color_override("font_color", Color(c, 0.92))
			cycle_rar.text = nm_str.to_upper()
			cycle_rar.add_theme_color_override("font_color", Color(c, 0.80))
			cycle_border.color    = Color(c, 0.72)
			cycle_bg.color        = Color(c.r * 0.09, c.g * 0.09, c.b * 0.09, 1.0)
			# Cadre du panneau + ligne + coins déco
			a_sb.border_color = Color(c, 0.55)
			a_top.color       = Color(c, 0.75)
			for cr in ann_corners:
				cr.color = Color(c, 0.70)
		)

	# ── Révélation : flash + texte ─────────────────────────────
	tw.tween_interval(0.25)
	tw.tween_callback(func() -> void:
		# Sous-titre → nom rareté
		a_sub.text = "✦  %s  ✦" % _rn.to_upper()
		a_sub.add_theme_color_override("font_color", Color(_rc, 0.90))
		# Flash blanc sur le symbole puis retour couleur rareté
		var fl := create_tween().set_parallel(true)
		fl.tween_method(
			func(v: Color) -> void: cycle_sym.add_theme_color_override("font_color", v),
			Color(_rc, 0.92), Color.WHITE, 0.09)
		fl.tween_method(
			func(v: Color) -> void: cycle_sym.add_theme_color_override("font_color", v),
			Color.WHITE, Color(_rc, 0.92), 0.24).set_delay(0.09)
		# Flash du bord
		fl.tween_method(
			func(v: Color) -> void: cycle_border.color = v,
			Color(_rc, 0.72), Color.WHITE, 0.09)
		fl.tween_method(
			func(v: Color) -> void: cycle_border.color = v,
			Color.WHITE, Color(_rc, 0.72), 0.24).set_delay(0.09)
	)

	# Pause : le joueur voit la rareté
	tw.tween_interval(0.80)

	# Flash écran couleur rareté
	tw.tween_callback(func() -> void:
		var fw := create_tween().set_parallel(true)
		fw.tween_property(flash, "color:a", 0.55, 0.09)
		fw.tween_property(flash, "color:a", 0.0,  0.50).set_delay(0.09)
		fw.tween_property(announce, "modulate:a", 0.0, 0.28)
	)

	# Transition vers les cartes
	tw.tween_interval(0.38)
	tw.tween_callback(func() -> void:
		announce.queue_free()
		_reveal_cards(bg)
	)


# =============================================================
# PHASE 2 — Révélation des deux cartes
# =============================================================

func _reveal_cards(bg: ColorRect) -> void:
	_cards_visible = true
	var vp := get_viewport().get_visible_rect().size

	# Lueur ambiante (derrière le panneau)
	var ambient := ColorRect.new()
	ambient.color        = Color(_rc.r, _rc.g, _rc.b, 0.0)
	ambient.process_mode = Node.PROCESS_MODE_ALWAYS
	ambient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ambient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ambient)

	# ── Panneau principal (780 × 530) ─────────────────────────
	var PW := 780.0 * _M
	var PH := 530.0 * _M
	var panel_root := Control.new()
	panel_root.size         = Vector2(PW, PH)
	panel_root.position     = Vector2((vp.x - PW) * 0.5, (vp.y - PH) * 0.5)
	panel_root.modulate      = Color(1.0, 1.0, 1.0, 0.0)
	panel_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel_root)

	# Fond panneau
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color    = C_PANEL
	panel_sb.border_color = Color(_rc, 0.50)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(14)
	var panel_c := PanelContainer.new()
	panel_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_c.add_theme_stylebox_override("panel", panel_sb)
	panel_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_root.add_child(panel_c)

	# Ligne accent haut
	var top_bar := ColorRect.new()
	top_bar.color    = Color(_rc, 0.75)
	top_bar.position = Vector2(36.0 * _M, 0.0)
	top_bar.size     = Vector2(PW - 72.0 * _M, 3.0)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_root.add_child(top_bar)

	# Coins déco
	for c in _make_corners(Vector2(4, 4), Vector2(PW - 8, PH - 8), Color(_rc, 0.80)):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel_root.add_child(c)

	# ── VBox contenu ──────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  30.0 * _M
	vbox.offset_right  = -30.0 * _M
	vbox.offset_top    =  24.0 * _M
	vbox.offset_bottom = -22.0 * _M
	vbox.add_theme_constant_override("separation", int(12 * _M))
	vbox.process_mode  = Node.PROCESS_MODE_ALWAYS
	panel_root.add_child(vbox)

	# Header — éclairs dessinés flanquant le texte
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)
	var bolt_l := _LightningIcon.new()
	bolt_l.custom_minimum_size = Vector2(24 * _M, 30 * _M)
	title_row.add_child(bolt_l)
	var header := Label.new()
	header.text = tr("UI_SKILL_LEVEL_TITLE") % _level
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", int(30 * _M))
	header.add_theme_color_override("font_color", C_GOLD)
	header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	header.add_theme_constant_override("outline_size", 5)
	title_row.add_child(header)
	var bolt_r := _LightningIcon.new()
	bolt_r.custom_minimum_size = Vector2(24 * _M, 30 * _M)
	title_row.add_child(bolt_r)

	# Rangée ── Rareté ──
	var div_row := HBoxContainer.new()
	div_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	div_row.add_theme_constant_override("separation", 10)
	div_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(div_row)

	var line_l := ColorRect.new()
	line_l.color               = Color(_rc, 0.40)
	line_l.custom_minimum_size = Vector2(100 * _M, 1)
	line_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line_l.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	div_row.add_child(line_l)

	var rar_badge := Label.new()
	rar_badge.text = "✦  %s  ✦" % _rn.to_upper()
	rar_badge.add_theme_font_size_override("font_size", int(11 * _M))
	rar_badge.add_theme_color_override("font_color", Color(_rc, 0.92))
	div_row.add_child(rar_badge)

	var line_r := ColorRect.new()
	line_r.color               = Color(_rc, 0.40)
	line_r.custom_minimum_size = Vector2(100 * _M, 1)
	line_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line_r.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	div_row.add_child(line_r)

	# ── Cartes ────────────────────────────────────────────────
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(36 * _M))
	hbox.alignment           = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.process_mode        = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(hbox)

	var card_wrappers: Array = []
	for i in _skills.size():
		var w := _build_card(_skills[i], i + 1)
		hbox.add_child(w)
		card_wrappers.append(w)

	# Hint clavier
	var hint := Label.new()
	hint.text = tr("UI_SKILL_CHOOSE_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", int(10 * _M))
	hint.add_theme_color_override("font_color", Color(C_TEXT_DIM, 0.40))
	vbox.add_child(hint)

	# ── Animation d'entrée ────────────────────────────────────
	var target_y := panel_root.position.y
	panel_root.position.y += 40.0
	for w in card_wrappers:
		w.modulate   = Color(1.0, 1.0, 1.0, 0.0)
		w.position.y += 24.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel_root, "modulate:a",  1.0,      0.28)
	tw.tween_property(panel_root, "position:y",  target_y, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ambient, "color:a", 0.07, 0.45)

	for i in card_wrappers.size():
		var d := 0.16 + i * 0.09
		tw.tween_property(card_wrappers[i], "modulate:a",  1.0, 0.24).set_delay(d)
		tw.tween_property(card_wrappers[i], "position:y",  0.0, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(d)


# =============================================================
# CARTE DE COMPÉTENCE
# =============================================================

func _build_card(skill_data: Dictionary, index: int) -> Control:
	var rarity:     int    = skill_data.get("rarity", SkillCatalogue.Rarity.COMMON)
	var rc:         Color  = SkillCatalogue.RARITY_COLORS[rarity]
	var rn:         String = tr(SkillCatalogue.RARITY_NAMES[rarity])
	var symbol:     String = RARITY_SYMBOLS.get(rarity, "◆")
	var skill_id:   String = skill_data.get("id",          "")
	var skill_name: String = tr(skill_data.get("name",        ""))
	var skill_desc: String = tr(skill_data.get("description", ""))

	var CW := 300.0 * _M
	var CH := 250.0 * _M
	var IH := 80.0 * _M

	# Wrapper
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(CW, CH)
	wrapper.process_mode        = Node.PROCESS_MODE_ALWAYS

	var glow_outer := ColorRect.new()
	glow_outer.color    = Color(rc.r, rc.g, rc.b, 0.0)
	glow_outer.position = Vector2(-20.0, -20.0)
	glow_outer.size     = Vector2(CW + 40.0, CH + 40.0)
	glow_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(glow_outer)

	var glow_inner := ColorRect.new()
	glow_inner.color    = Color(rc.r, rc.g, rc.b, 0.0)
	glow_inner.position = Vector2(-10.0, -10.0)
	glow_inner.size     = Vector2(CW + 20.0, CH + 20.0)
	glow_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(glow_inner)

	# Carte
	var card := Button.new()
	card.custom_minimum_size        = Vector2(CW, CH)
	card.process_mode               = Node.PROCESS_MODE_ALWAYS
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.focus_mode                 = Control.FOCUS_NONE

	var card_style := StyleBoxFlat.new()
	card_style.bg_color    = C_PANEL
	card_style.border_color = Color(rc, 0.60)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("normal",  card_style)
	card.add_theme_stylebox_override("hover",   card_style)
	card.add_theme_stylebox_override("pressed", card_style)
	wrapper.add_child(card)

	# Zone icône
	var icon_bg := ColorRect.new()
	icon_bg.color    = Color(rc.r * 0.20, rc.g * 0.20, rc.b * 0.20, 1.0)
	icon_bg.position = Vector2(2.0, 2.0)
	icon_bg.size     = Vector2(CW - 4.0, IH - 2.0)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_bg)

	var icon_tint := ColorRect.new()
	icon_tint.color    = Color(rc.r, rc.g, rc.b, 0.10)
	icon_tint.position = Vector2(2.0, 2.0)
	icon_tint.size     = Vector2(CW - 4.0, IH - 2.0)
	icon_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_tint)

	var icon_line := ColorRect.new()
	icon_line.color    = Color(rc, 0.85)
	icon_line.position = Vector2(2.0, IH)
	icon_line.size     = Vector2(CW - 4.0, 2.0)
	icon_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_line)

	var sym_lbl := Label.new()
	sym_lbl.text     = symbol
	sym_lbl.position = Vector2(0.0, 4.0)
	sym_lbl.size     = Vector2(CW, IH - 6.0)
	sym_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sym_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sym_lbl.add_theme_font_size_override("font_size", int(38 * _M))
	sym_lbl.add_theme_color_override("font_color", Color(rc, 0.88))
	sym_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	sym_lbl.add_theme_constant_override("outline_size", 5)
	sym_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sym_lbl)

	# Badge [1] / [2]
	var badge_bg := ColorRect.new()
	badge_bg.color    = Color(rc, 0.90)
	badge_bg.position = Vector2(2.0, 2.0)
	badge_bg.size     = Vector2(36.0 * _M, 26.0 * _M)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(badge_bg)

	var badge_lbl := Label.new()
	badge_lbl.text     = "[%d]" % index
	badge_lbl.position = Vector2(2.0, 2.0)
	badge_lbl.size     = Vector2(36.0 * _M, 26.0 * _M)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_size_override("font_size", int(10 * _M))
	badge_lbl.add_theme_color_override("font_color", Color(0.04, 0.04, 0.08, 1.0))
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(badge_lbl)

	# Coins déco sur la carte
	for c in _make_corners(Vector2(2, 2), Vector2(CW - 4, CH - 4), Color(rc, 0.55)):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(c)

	# Zone texte
	var inner := VBoxContainer.new()
	inner.position = Vector2(16.0, IH + 10.0)
	inner.size     = Vector2(CW - 32.0, CH - IH - 18.0)
	inner.add_theme_constant_override("separation", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inner)

	var rar_lbl := Label.new()
	rar_lbl.text = rn.to_upper()
	rar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rar_lbl.add_theme_font_size_override("font_size", int(9 * _M))
	rar_lbl.add_theme_color_override("font_color", Color(rc, 0.70))
	rar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rar_lbl)

	var name_lbl := Label.new()
	name_lbl.text = skill_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", int(17 * _M))
	name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.90))
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_lbl)

	var hsep := ColorRect.new()
	hsep.color               = Color(rc, 0.28)
	hsep.custom_minimum_size = Vector2(0, 1)
	hsep.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	inner.add_child(hsep)

	var desc_lbl := Label.new()
	desc_lbl.text = skill_desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", int(11 * _M))
	desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	inner.add_child(desc_lbl)

	# Hover : glow + flottement
	card.mouse_entered.connect(func() -> void:
		_play_hover()
		card_style.border_color = rc
		card_style.set_border_width_all(3)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(glow_inner, "color:a", 0.18, 0.14)
		tw.tween_property(glow_outer, "color:a", 0.09, 0.14)
		tw.tween_property(wrapper, "position:y", -8.0, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
	card.mouse_exited.connect(func() -> void:
		card_style.border_color = Color(rc, 0.60)
		card_style.set_border_width_all(2)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(glow_inner, "color:a", 0.0, 0.20)
		tw.tween_property(glow_outer, "color:a", 0.0, 0.20)
		tw.tween_property(wrapper, "position:y", 0.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
	card.pressed.connect(func() -> void: _on_card_chosen(skill_id))

	return wrapper


# =============================================================
# UTILITAIRES
# =============================================================

func _make_corners(origin: Vector2, sz: Vector2, color: Color) -> Array[ColorRect]:
	var result: Array[ColorRect] = []
	var cl := _CL * _M
	var ct := _CT * _M
	var defs := [
		[origin,                                       Vector2(cl, ct)],
		[origin,                                       Vector2(ct, cl)],
		[origin + Vector2(sz.x - cl, 0.0),             Vector2(cl, ct)],
		[origin + Vector2(sz.x - ct, 0.0),             Vector2(ct, cl)],
		[origin + Vector2(0.0, sz.y - ct),              Vector2(cl, ct)],
		[origin + Vector2(0.0, sz.y - cl),              Vector2(ct, cl)],
		[origin + Vector2(sz.x - cl, sz.y - ct),        Vector2(cl, ct)],
		[origin + Vector2(sz.x - ct, sz.y - cl),        Vector2(ct, cl)],
	]
	for d in defs:
		var r := ColorRect.new()
		r.color    = color
		r.position = d[0]
		r.size     = d[1]
		result.append(r)
	return result


# =============================================================
# INPUT CLAVIER [1] / [2]  — bloqué pendant l'animation suspense
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _cards_visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: if _skills.size() > 0: _on_card_chosen(_skills[0].get("id", ""))
			KEY_2: if _skills.size() > 1: _on_card_chosen(_skills[1].get("id", ""))


# =============================================================
# CALLBACKS
# =============================================================

func _play_hover() -> void:
	if _sfx_hover == null:
		return
	var stream: AudioStream = load(_SFX_HOVER_PATH)
	if stream:
		_sfx_hover.stream      = stream
		_sfx_hover.volume_db   = 0.0
		_sfx_hover.pitch_scale = randf_range(0.97, 1.03)
		_sfx_hover.play()


func _on_card_chosen(skill_id: String) -> void:
	if skill_id.is_empty():
		return
	if _sfx_choose != null:
		var stream: AudioStream = load(_SFX_CHOOSE_PATH)
		if stream:
			_sfx_choose.stream      = stream
			_sfx_choose.volume_db   = 5.0
			_sfx_choose.pitch_scale = 0.85
			_sfx_choose.play()
	var _finish := func() -> void:
		get_tree().paused = false
		skill_chosen.emit(skill_id)
		if not _is_waiting:
			queue_free()
		# Sinon : CoopArena appellera enter_waiting_mode() puis queue_free()
		# quand tous les joueurs auront choisi.
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(_finish)


# =============================================================
# MODE ATTENTE COOP — affiché quand le joueur a choisi mais attend les autres
# =============================================================

## Garde la fenêtre ouverte, désactive les cartes, affiche un message propre au-dessus.
## Appelé par CoopArena juste après skill_chosen (UI encore vivante).
func enter_waiting_mode() -> void:
	_is_waiting = true

	# Désactiver toutes les cartes (plus cliquables)
	_disable_buttons_recursive(self)

	# Fond semi-transparent sur les cartes
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.0, 0.0, 0.0, 0.45)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dimmer)

	# Message centré, propre, texte uniquement
	var M := _M
	var lbl := Label.new()
	lbl.text = "En attente des coéquipiers..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -250.0 * M
	lbl.offset_right  =  250.0 * M
	lbl.offset_top    = -20.0  * M
	lbl.offset_bottom =  20.0  * M
	lbl.add_theme_font_size_override("font_size", int(18 * M))
	lbl.add_theme_color_override("font_color",         Color(0.4, 1.0, 0.85))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_constant_override("outline_size", 4)
	add_child(lbl)


func _disable_buttons_recursive(node: Node) -> void:
	if node is Button:
		(node as Button).disabled = true
	for child in node.get_children():
		_disable_buttons_recursive(child)


# =============================================================
# ICÔNE ÉCLAIR — dessinée (compatible toutes plateformes)
# =============================================================

class _LightningIcon extends Control:
	func _draw() -> void:
		var c   := size * 0.5
		var s   := minf(size.x, size.y) * 0.44
		var col := Color(1.0, 0.85, 0.0)
		# Éclair : polygone en forme de Z inversé
		draw_polygon(PackedVector2Array([
			c + Vector2( s * 0.28, -s),
			c + Vector2(-s * 0.08, -s * 0.06),
			c + Vector2( s * 0.38, -s * 0.06),
			c + Vector2(-s * 0.28,  s),
			c + Vector2( s * 0.08,  s * 0.06),
			c + Vector2(-s * 0.38,  s * 0.06),
		]), PackedColorArray([col, col, col, col, col, col]))
