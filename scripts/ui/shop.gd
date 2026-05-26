# =============================================================
# shop.gd — Boutique d'améliorations permanentes
# Rebound Protocol
# =============================================================
# CanvasLayer construit entièrement en code.
# Accessible via PauseMenu (bouton "Boutique").
# =============================================================

class_name Shop
extends CanvasLayer

const COLOR_CYAN  := Color(0.0,  0.851, 1.0,  1.0)
const COLOR_GOLD  := Color(1.0,  0.82,  0.0,  1.0)
const COLOR_GREEN := Color(0.2,  0.9,   0.3,  1.0)
const COLOR_RED   := Color(1.0,  0.35,  0.35, 1.0)
const COLOR_PANEL := Color(0.04, 0.08,  0.12, 0.97)
const COLOR_DIM   := Color(0.45, 0.5,   0.55, 1.0)
const FONT_PATH   := "res://ui_theme/fonts/Xolonium-Regular.ttf"

# Noms affichables des upgrades (clé → [clé_nom, clé_description])
const UPGRADE_LABELS: Dictionary = {
	"hp_max":           ["SHOP_NAME_hp_max", "SHOP_DESC_hp_max"],
	"move_speed":       ["SHOP_NAME_move_speed", "SHOP_DESC_move_speed"],
	"damage_reduction": ["SHOP_NAME_damage_reduction", "SHOP_DESC_damage_reduction"],
	"pickup_radius":    ["SHOP_NAME_pickup_radius", "SHOP_DESC_pickup_radius"],
	"shield_size":      ["SHOP_NAME_shield_size", "SHOP_DESC_shield_size"],
	"shield_duration":  ["SHOP_NAME_shield_duration", "SHOP_DESC_shield_duration"],
	"parry_damage":     ["SHOP_NAME_parry_damage", "SHOP_DESC_parry_damage"],
	"parry_window":     ["SHOP_NAME_parry_window", "SHOP_DESC_parry_window"],
	"hp_regen":         ["SHOP_NAME_hp_regen", "SHOP_DESC_hp_regen"],
	"xp_bonus":         ["SHOP_NAME_xp_bonus", "SHOP_DESC_xp_bonus"],
	"dash_cooldown":    ["SHOP_NAME_dash_cooldown", "SHOP_DESC_dash_cooldown"],
	"stomp_damage":     ["SHOP_NAME_stomp_damage", "SHOP_DESC_stomp_damage"],
	"parry_heal":       ["SHOP_NAME_parry_heal", "SHOP_DESC_parry_heal"],
	"reflect_speed":    ["SHOP_NAME_reflect_speed", "SHOP_DESC_reflect_speed"],
	"coin_bonus":       ["SHOP_NAME_coin_bonus", "SHOP_DESC_coin_bonus"],
	"dash_armor":       ["SHOP_NAME_dash_armor", "SHOP_DESC_dash_armor"],
}

const _SFX_BUY:   AudioStream = preload("res://audio/sfx/ui/shop_buy.wav")
const _SFX_BUY_MAX: AudioStream = preload("res://audio/sfx/ui/shop_buy_max.wav")
const _SFX_HOVER:   AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK:   AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
const _SFX_CLOSE:   AudioStream = preload("res://audio/sfx/ui/shop_close.wav")
var _sfx_player: AudioStreamPlayer = null

var _font: FontFile = null
var _coin_label: Label = null
var _tab_buttons: Dictionary = {}        # cat → Button
var _list_container: VBoxContainer = null
var _current_cat: String = "joueur"
var _buy_rows: Dictionary = {}           # upgrade_id → { "tier_lbl", "price_lbl", "btn" }


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 10   # s'affiche au-dessus du menu pause (layer 0 par défaut)
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)

	_sfx_player              = AudioStreamPlayer.new()
	_sfx_player.bus         = "SFX"
	_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx_player)

	_build_ui()
	_switch_tab("joueur")


# =============================================================
# CONSTRUCTION UI
# =============================================================

func _build_ui() -> void:
	# Fond semi-transparent
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Panneau principal centré
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 670)
	var style := StyleBoxFlat.new()
	style.bg_color    = COLOR_PANEL
	style.border_color = COLOR_CYAN
	style.set_border_width_all(2)
	style.content_margin_left   = 28.0
	style.content_margin_right  = 28.0
	style.content_margin_top    = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	# ── En-tête : titre + pièces ─────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	var title := _make_label(tr("UI_SHOP_TITLE"), 28, COLOR_CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 6)
	header.add_child(coin_box)
	coin_box.add_child(_make_label("🪙", 20, COLOR_GOLD))
	_coin_label = _make_label("0", 20, COLOR_GOLD)
	coin_box.add_child(_coin_label)

	root.add_child(_make_separator())

	# ── Onglets ──────────────────────────────────────────────
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)

	var label_map := {
		"joueur": "UI_SHOP_TAB_PLAYER", 
		"bouclier": "UI_SHOP_TAB_SHIELD", 
		"passifs": "UI_SHOP_TAB_PASSIVES"
	}
	
	for cat in ["joueur", "bouclier", "passifs"]:
		var btn := _make_tab_button(tr(label_map[cat]), cat)
		tabs.add_child(btn)
		_tab_buttons[cat] = btn

	# ── Liste scrollable ─────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 6)
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_container)

	root.add_child(_make_separator())

	# ── Bouton fermer ────────────────────────────────────────
	var close_btn := _make_button(tr("UI_SHOP_CLOSE"), _on_close)
	close_btn.custom_minimum_size = Vector2(160, 40)
	var close_center := CenterContainer.new()
	close_center.add_child(close_btn)
	root.add_child(close_center)


# =============================================================
# ONGLETS
# =============================================================

func _switch_tab(cat: String) -> void:
	_current_cat = cat
	_buy_rows.clear()

	# Mettre à jour l'apparence des onglets
	for c in _tab_buttons:
		var btn: Button = _tab_buttons[c]
		if c == cat:
			btn.add_theme_color_override("font_color", COLOR_CYAN)
			btn.modulate = Color(1, 1, 1, 1)
		else:
			btn.add_theme_color_override("font_color", COLOR_DIM)
			btn.modulate = Color(0.7, 0.7, 0.7, 1)

	# Vider la liste et la reconstruire
	for child in _list_container.get_children():
		child.queue_free()

	for id in SaveData.CATALOG:
		var entry: Dictionary = SaveData.CATALOG[id]
		if entry["cat"] != cat:
			continue
		_list_container.add_child(_build_upgrade_row(id, entry))

	_refresh_coins()


# =============================================================
# LIGNE D'UPGRADE
# =============================================================

func _build_upgrade_row(id: String, _entry: Dictionary) -> Control:
	var keys: Array   = UPGRADE_LABELS.get(id, ["", ""])
	var name_str: String = tr(keys[0])
	var desc_str: String = tr(keys[1])
	var max_tier: int    = SaveData.CATALOG[id]["max_tier"]

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.05, 0.09, 0.14, 0.95)
	style.border_color = Color(COLOR_CYAN, 0.2)
	style.set_border_width_all(1)
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 7.0
	style.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	# ── Nom + description ────────────────────────────────────────
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)
	info_vbox.add_child(_make_label(name_str, 14, Color(0.92, 0.97, 1.0)))
	var desc_lbl := _make_label(desc_str, 10, COLOR_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_lbl)

	# ── Barre de progression + compteur ─────────────────────────
	var bar_vbox := VBoxContainer.new()
	bar_vbox.custom_minimum_size = Vector2(130, 0)
	bar_vbox.add_theme_constant_override("separation", 4)
	bar_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(bar_vbox)

	var tier_lbl := _make_label("", 10, COLOR_DIM)
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_vbox.add_child(tier_lbl)

	# Rangée de segments — largeur adaptée au nombre de paliers
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 2)
	bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_vbox.add_child(bar_row)

	var seg_w: int = clamp(int(126.0 / max_tier) - 2, 6, 26)
	var segments: Array = []
	for _i in max_tier:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(seg_w, 7)
		seg.color = Color(0.12, 0.18, 0.24)
		bar_row.add_child(seg)
		segments.append(seg)

	# ── Prix ─────────────────────────────────────────────────────
	var price_lbl := _make_label("", 13, COLOR_GOLD)
	price_lbl.custom_minimum_size = Vector2(72, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(price_lbl)

	# ── Bouton acheter ────────────────────────────────────────────
	var btn := _make_button(tr("UI_SHOP_BUY"), func(): _on_buy(id))
	btn.custom_minimum_size = Vector2(90, 34)
	hbox.add_child(btn)

	_buy_rows[id] = {
		"tier_lbl":  tier_lbl,
		"price_lbl": price_lbl,
		"btn":       btn,
		"segments":  segments,
		"max_tier":  max_tier,
	}
	_refresh_row(id)
	return panel


# =============================================================
# REFRESH
# =============================================================

func _refresh_coins() -> void:
	if _coin_label == null:
		return
	var coins := SaveData.get_coins()
	_coin_label.text = str(coins)
	# Rafraîchir aussi tous les boutons
	for id in _buy_rows:
		_refresh_row(id)


func _refresh_row(id: String) -> void:
	if not _buy_rows.has(id):
		return
	var row: Dictionary   = _buy_rows[id]
	var entry: Dictionary = SaveData.CATALOG[id]
	var tier: int         = SaveData.get_upgrade_tier(id)
	var max_tier: int     = row["max_tier"]
	var price: int        = SaveData.get_next_tier_price(id)
	var coins: int        = SaveData.get_coins()

	var tier_lbl:  Label  = row["tier_lbl"]
	var price_lbl: Label  = row["price_lbl"]
	var btn:       Button = row["btn"]
	var segments:  Array  = row["segments"]

	tier_lbl.text = "%d / %d" % [tier, max_tier]

	# Segments : gradient cyan → or selon la progression
	for i in segments.size():
		var seg: ColorRect = segments[i]
		if i < tier:
			var t := float(i) / float(max(max_tier - 1, 1))
			seg.color = COLOR_CYAN.lerp(COLOR_GOLD, t * 0.7)
		else:
			seg.color = Color(0.12, 0.18, 0.24)

	if price < 0:
		price_lbl.text = tr("UI_SHOP_MAX")
		price_lbl.add_theme_color_override("font_color", COLOR_GREEN)
		btn.disabled = true
		btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		price_lbl.text = "🪙 %d" % price
		if coins >= price:
			price_lbl.add_theme_color_override("font_color", COLOR_GOLD)
			btn.disabled = false
			btn.modulate = Color(1, 1, 1, 1)
		else:
			price_lbl.add_theme_color_override("font_color", COLOR_RED)
			btn.disabled = true
			btn.modulate = Color(0.6, 0.6, 0.6, 0.8)


# =============================================================
# CALLBACKS
# =============================================================

func _on_buy(id: String) -> void:
	if SaveData.buy_upgrade(id):
		_refresh_coins()

		# Appliquer immédiatement l'upgrade sur le joueur en cours de jeu
		var player := get_tree().get_first_node_in_group("player") as Player
		if player:
			player.refresh_upgrades()

		# Son d'achat : pitch qui monte progressivement avec le palier
		var new_tier: int = SaveData.get_upgrade_tier(id)
		var max_tier: int = SaveData.CATALOG[id]["max_tier"]
		if new_tier >= max_tier:
			if _sfx_player and _SFX_BUY_MAX:
				_sfx_player.stream      = _SFX_BUY_MAX
				_sfx_player.volume_db   = -6.0
				_sfx_player.pitch_scale = 1.0
				_sfx_player.play()
		else:
			# Pitch remappé entre 0.85 (1er palier) et 1.25 (avant-dernier)
			var pitch := remap(float(new_tier), 1.0, float(max(max_tier - 1, 1)), 0.85, 1.25)
			if _sfx_player and _SFX_BUY:
				_sfx_player.stream      = _SFX_BUY
				_sfx_player.volume_db   = -6.0
				_sfx_player.pitch_scale = clamp(pitch, 0.85, 1.25)
				_sfx_player.play()


func _on_close() -> void:
	if _SFX_CLOSE != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_CLOSE
		p.bus         = "SFX"
		p.volume_db   = 0.0
		p.pitch_scale = 1.0
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	queue_free()


# =============================================================
# HELPERS
# =============================================================

func _make_tab_button(text: String, cat: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(110, 36)
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COLOR_DIM)
	var style := StyleBoxFlat.new()
	style.bg_color    = Color(0.0, 0.12, 0.2, 0.7)
	style.border_color = Color(COLOR_CYAN, 0.4)
	style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(func(): _switch_tab(cat))
	return btn


func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", COLOR_CYAN)
	var style := StyleBoxFlat.new()
	style.bg_color    = Color(0.0, 0.12, 0.2, 0.85)
	style.border_color = Color(COLOR_CYAN, 0.5)
	style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	var hover := StyleBoxFlat.new()
	hover.bg_color    = Color(0.0, 0.25, 0.4, 0.9)
	hover.border_color = COLOR_CYAN
	hover.set_border_width_all(1)
	btn.add_theme_stylebox_override("hover", hover)
	btn.mouse_entered.connect(func():
		if _sfx_player and _SFX_HOVER:
			_sfx_player.stream      = _SFX_HOVER
			_sfx_player.volume_db   = 2.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	btn.pressed.connect(func():
		if _sfx_player and _SFX_CLICK:
			_sfx_player.stream      = _SFX_CLICK
			_sfx_player.volume_db   = 5.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	btn.pressed.connect(callback)
	return btn


func _make_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if _font:
		lbl.add_theme_font_override("font", _font)
	return lbl


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(COLOR_CYAN, 0.3)
	style.content_margin_top    = 1.0
	style.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", style)
	return sep


# =============================================================
# INPUTS
# =============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_on_close()
		get_viewport().set_input_as_handled()
