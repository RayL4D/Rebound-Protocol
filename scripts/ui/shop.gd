# =============================================================
# shop.gd — Boutique d'améliorations permanentes
# Rebound Protocol
# =============================================================
# CanvasLayer construit entièrement en code.
# Accessible via PauseMenu (bouton "Boutique").
#
# Layout :
#   ┌─ En-tête : pièces courantes ──────────────────────────┐
#   │  Onglets : JOUEUR | BOUCLIER | PASSIFS                 │
#   │  ┌─ Liste scrollable des upgrades ──────────────────┐  │
#   │  │  [Nom]  [Palier]  [Desc]  [Prix]  [ACHETER]      │  │
#   │  └───────────────────────────────────────────────────┘  │
#   └─ Bouton FERMER ───────────────────────────────────────┘
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

# Noms affichables des upgrades (clé → [nom, description])
const UPGRADE_LABELS: Dictionary = {
	"hp_max":           ["HP Maximum",          "+1 HP max par palier"],
	"move_speed":       ["Vitesse",              "+5 % vitesse de déplacement"],
	"damage_reduction": ["Réduction dégâts",     "−5 % dégâts reçus par palier"],
	"pickup_radius":    ["Rayon collecte",        "+20 % portée des pièces"],
	"shield_size":      ["Taille bouclier",       "+8 % rayon du bouclier"],
	"shield_duration":  ["Durée activation",     "+10 % durée de parade active"],
	"parry_damage":     ["Dégâts renvoi",         "+10 % dégâts balles renvoyées"],
	"parry_window":     ["Fenêtre critique",      "+1 frame de fenêtre critique"],
	"hp_regen":         ["Régén. HP",             "Palier 1→30s, 2→20s, 3→12s"],
	"xp_bonus":         ["Bonus XP",              "+10 % XP par ennemi tué"],
}

const _SFX_BUY_1:   AudioStream = preload("res://audio/sfx/ui/shop_buy_1.wav")
const _SFX_BUY_2:   AudioStream = preload("res://audio/sfx/ui/shop_buy_2.wav")
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

	_sfx_player             = AudioStreamPlayer.new()
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
	panel.custom_minimum_size = Vector2(600, 520)
	var style := StyleBoxFlat.new()
	style.bg_color    = COLOR_PANEL
	style.border_color = COLOR_CYAN
	style.set_border_width_all(2)
	style.content_margin_left   = 28.0
	style.content_margin_right  = 28.0
	style.content_margin_top    = 22.0
	style.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	panel.add_child(root)

	# ── En-tête : titre + pièces ─────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	var title := _make_label("BOUTIQUE", 28, COLOR_CYAN)
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

	for cat in ["joueur", "bouclier", "passifs"]:
		var label_map := {"joueur": "JOUEUR", "bouclier": "BOUCLIER", "passifs": "PASSIFS"}
		var btn := _make_tab_button(label_map[cat], cat)
		tabs.add_child(btn)
		_tab_buttons[cat] = btn

	# ── Liste scrollable ─────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	root.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 10)
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_container)

	root.add_child(_make_separator())

	# ── Bouton fermer ────────────────────────────────────────
	var close_btn := _make_button("FERMER", _on_close)
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

	# Vider la liste et la reconstruire (free() immédiat, pas queue_free())
	for child in _list_container.get_children():
		child.free()

	for id in SaveData.CATALOG:
		var entry: Dictionary = SaveData.CATALOG[id]
		if entry["cat"] != cat:
			continue
		_list_container.add_child(_build_upgrade_row(id, entry))

	_refresh_coins()


# =============================================================
# LIGNE D'UPGRADE
# =============================================================

func _build_upgrade_row(id: String, entry: Dictionary) -> Control:
	var labels: Array = UPGRADE_LABELS.get(id, [id, ""])
	var name_str: String = labels[0]
	var desc_str: String = labels[1]

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color    = Color(0.06, 0.10, 0.15, 0.9)
	style.border_color = Color(COLOR_CYAN, 0.25)
	style.set_border_width_all(1)
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Nom + description
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	info_vbox.add_child(_make_label(name_str, 15, Color(0.9, 0.95, 1.0)))
	info_vbox.add_child(_make_label(desc_str, 11, COLOR_DIM))

	# Palier actuel
	var tier_lbl := _make_label("", 13, COLOR_CYAN)
	tier_lbl.custom_minimum_size = Vector2(70, 0)
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(tier_lbl)

	# Prix
	var price_lbl := _make_label("", 13, COLOR_GOLD)
	price_lbl.custom_minimum_size = Vector2(80, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(price_lbl)

	# Bouton acheter
	var btn := _make_button("ACHETER", func(): _on_buy(id))
	btn.custom_minimum_size = Vector2(90, 34)
	hbox.add_child(btn)

	_buy_rows[id] = {"tier_lbl": tier_lbl, "price_lbl": price_lbl, "btn": btn}
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
	var row: Dictionary    = _buy_rows[id]
	var entry: Dictionary  = SaveData.CATALOG[id]
	var tier: int          = SaveData.get_upgrade_tier(id)
	var max_tier: int      = entry["max_tier"]
	var price: int         = SaveData.get_next_tier_price(id)
	var coins: int         = SaveData.get_coins()

	var tier_lbl:  Label  = row["tier_lbl"]
	var price_lbl: Label  = row["price_lbl"]
	var btn:       Button = row["btn"]

	tier_lbl.text = "%d / %d" % [tier, max_tier]

	if price < 0:
		# Palier max
		price_lbl.text = "MAX"
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

		# Choisir le son selon le palier atteint
		var new_tier: int = SaveData.get_upgrade_tier(id)
		var max_tier: int = SaveData.UPGRADES[id]["max_tier"]
		var sfx: AudioStream
		if new_tier >= max_tier:
			sfx = _SFX_BUY_MAX
		elif new_tier >= 2:
			sfx = _SFX_BUY_2
		else:
			sfx = _SFX_BUY_1
		if _sfx_player and sfx:
			_sfx_player.stream      = sfx
			_sfx_player.volume_db   = -6.0
			_sfx_player.pitch_scale = 1.0
			_sfx_player.play()


func _on_close() -> void:
	# Son de fermeture boutique — floating player car queue_free() suit immédiatement
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
	btn.pressed.connect(callback)
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
		get_viewport().set_input_as_handled() # Indique à Godot que l'action a été traitée
