# =============================================================
# HUD.gd — Interface joueur
# Rebound Protocol
# =============================================================
# Barre HP fixe en haut à gauche — style cyberpunk RPG.
# • Panel semi-transparent avec coins décoratifs
# • Header « SYS · INTEGRITY »
# • Barre segmentée avec glow et highlight
# • Couleur : cyan → orange → rouge selon les HP
# • Pulsation rouge quand HP < 30 %
# • Vignette de dégât plein écran
# • Barre de boss en bas de l'écran
# • Pointeur d'objectif
# =============================================================
extends CanvasLayer

const ShopScript      := preload("res://scripts/ui/shop.gd")
const _SFX_HOVER:      AudioStream = preload("res://audio/sfx/ui/btn_hover.wav")
const _SFX_CLICK:      AudioStream = preload("res://audio/sfx/ui/btn_click.wav")
const _SFX_SHOP_OPEN:  AudioStream = preload("res://audio/sfx/ui/shop_open.wav")
const _SFX_SHOP_CLOSE: AudioStream = preload("res://audio/sfx/ui/shop_close.wav")
var _sfx_player: AudioStreamPlayer = null

# --- Dimensions du panel HP -----------------------------------
const PANEL_W    := 260.0
const PANEL_H    := 74.0
const PANEL_X    := 16.0
const PANEL_Y    := 16.0
const BAR_W      := 228.0
const BAR_H      := 14.0
const BAR_X      := 16.0          # offset X dans le panel
const BAR_Y      := 34.0          # offset Y dans le panel
const SEGMENTS   := 8             # séparateurs dans la barre
const CORNER_LEN := 9.0
const CORNER_THK := 2.0
const XP_PANEL_H := 60.0   # Hauteur du panel XP (juste sous HP)

# --- Dimensions barre boss ------------------------------------
const BOSS_BAR_WIDTH  := 320.0
const BOSS_BAR_HEIGHT := 14.0

# --- Palette --------------------------------------------------
const COLOR_CYAN   := Color(0.00, 0.85, 1.00)
const COLOR_BG     := Color(0.012, 0.040, 0.090, 0.92)
const COLOR_BORDER := Color(0.00, 0.80, 1.00, 0.80)
const COLOR_SEP    := Color(0.00, 0.80, 1.00, 0.22)
const COLOR_HEADER := Color(0.55, 0.97, 1.00, 0.70)
const COLOR_HPNUM  := Color(0.85, 1.00, 1.00, 0.90)

# --- Shader vignette dégât ------------------------------------
const DAMAGE_VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float edge = min(1.0 - abs(uv.x), 1.0 - abs(uv.y));
	float rim   = smoothstep(0.18, 0.0,  edge);
	float glow  = smoothstep(0.38, 0.10, edge) * 0.18;
	float alpha = clamp(rim * 0.7 + glow, 0.0, 1.0) * intensity;
	vec3 col = mix(vec3(0.55, 0.0, 0.0), vec3(1.0, 0.12, 0.12), rim);
	COLOR = vec4(col, alpha);
}
"""

# --- Refs UI --------------------------------------------------
var _container:    Control
var _fill:         ColorRect
var _highlight:    ColorRect
var _glow1:        ColorRect
var _glow2:        ColorRect
var _hp_label:     Label
var _corners:      Array[ColorRect] = []

# --- Facteur d'échelle mobile ---------------------------------
var _M: float = 1.6 if OS.has_feature("mobile") else 1.0

# --- État animation -------------------------------------------
var _player:       Player   = null
var _camera:       Camera3D = null
var _current_fill: float    = 1.0
var _target_fill:  float    = 1.0
var _pulse_time:   float    = 0.0

# --- Vignette dégât -------------------------------------------
var _vignette_rect: ColorRect      = null
var _vignette_mat:  ShaderMaterial = null
var _vignette_tween: Tween         = null

# --- Pointeur objectif ----------------------------------------
var _guide_icon:  TextureRect = null
var guide_target: Node3D      = null

# --- Coin counter + boutique ----------------------------------
var _coin_label_hud:  Label        = null
var _shop_open:       bool         = false
var _shop_instance:   CanvasLayer  = null   # référence pour fermer via B

# --- Barre boss -----------------------------------------------
var _boss_bar_container: Control   = null
var _boss_bar_bg:        ColorRect = null
var _boss_bar_fill:      ColorRect = null
var _boss_name_label:    Label     = null
var _boss_hp_label:      Label     = null
var _boss_max_hp:        int       = 1
var _boss_target_fill:   float     = 1.0
var _boss_current_fill:  float     = 1.0

# --- Barre XP -------------------------------------------------
var _xp_bar_fill:    ColorRect = null
var _xp_bar_label:   Label     = null
var _xp_level_label: Label     = null
var _xp_current_fill: float    = 0.0
var _xp_target_fill:  float    = 0.0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # reçoit l'input même quand le jeu est en pause

	_sfx_player     = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)

	_build_ui()
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("HUD: joueur introuvable.")
		return
	_camera       = get_viewport().get_camera_3d()
	_target_fill  = float(_player.current_hp) / float(_player.max_hp)
	_current_fill = _target_fill
	_refresh_bar(_current_fill)
	_update_label(_player.current_hp)
	_player.hp_changed.connect(_on_hp_changed)
	_player.player_died.connect(_on_player_died)

	# --- Connexion XpManager (optionnel — absent dans les menus) ---
	var xp_mgr := get_node_or_null("/root/XpManager")
	if xp_mgr != null:
		xp_mgr.xp_changed.connect(_on_xp_changed)
		_on_xp_changed(int(xp_mgr.get("current_xp")), int(xp_mgr.get("xp_to_next")))


func _process(delta: float) -> void:
	if _player == null:
		return

	# --- Pièces ---
	if _coin_label_hud != null:
		_coin_label_hud.text = "%d" % SaveData.get_coins()

	# --- Barre HP boss (interpolée) ---
	if _boss_bar_container != null and _boss_bar_container.visible:
		_boss_current_fill = lerp(_boss_current_fill, _boss_target_fill, 10.0 * delta)
		_boss_bar_fill.size.x = BOSS_BAR_WIDTH * _M * _boss_current_fill
		var bc: Color
		if _boss_current_fill > 0.5:
			bc = Color(1.0, 0.2, 0.2).lerp(Color(1.0, 0.55, 0.0), (_boss_current_fill - 0.5) * 2.0)
		else:
			bc = Color(0.5, 0.0, 0.8).lerp(Color(1.0, 0.2, 0.2), _boss_current_fill * 2.0)
		_boss_bar_fill.color = bc

	# --- Barre XP (interpolée) ---
	if _xp_bar_fill != null:
		_xp_current_fill      = lerp(_xp_current_fill, _xp_target_fill, 8.0 * delta)
		_xp_bar_fill.size.x   = BAR_W * _M * _xp_current_fill

	# --- Barre HP joueur (interpolée, fixe en haut à gauche) ---
	_current_fill = lerp(_current_fill, _target_fill, 12.0 * delta)
	_refresh_bar(_current_fill)

	if _target_fill < 0.3:
		_pulse_time += delta * 5.0
		var p := sin(_pulse_time) * 0.5 + 0.5
		var pulse_col := Color(1.0, 0.08 + p * 0.15, 0.08)
		_fill.color  = pulse_col
		_glow1.color = Color(pulse_col.r, pulse_col.g, pulse_col.b, 0.30)
		_glow2.color = Color(pulse_col.r, pulse_col.g, pulse_col.b, 0.14)
		for c in _corners:
			c.color = pulse_col
	else:
		_pulse_time = 0.0

	# --- Pointeur objectif ---
	if _camera != null and guide_target != null and is_instance_valid(guide_target):
		if _camera.is_position_behind(guide_target.global_position):
			_guide_icon.hide()
		else:
			var tp := _camera.unproject_position(guide_target.global_position)
			var ts := _guide_icon.texture.get_size() if _guide_icon.texture else Vector2(32, 32)
			_guide_icon.position = tp - ts * 0.5
			_guide_icon.show()
	elif _guide_icon != null and _guide_icon.visible:
		_guide_icon.hide()


# =============================================================
# BUILD UI
# =============================================================

func _build_ui() -> void:
	_build_coin_panel()
	_build_xp_bar()

	# --- Vignette dégât (plein écran, derrière tout) ---
	var shader         := Shader.new()
	shader.code         = DAMAGE_VIGNETTE_SHADER
	_vignette_mat       = ShaderMaterial.new()
	_vignette_mat.shader = shader
	_vignette_rect      = ColorRect.new()
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.material     = _vignette_mat
	add_child(_vignette_rect)

	# --- Pointeur objectif ---
	_guide_icon = TextureRect.new()
	_guide_icon.texture      = preload("res://ui_theme/png/cursor/cursor_pointer3D.png")
	_guide_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_icon.hide()
	add_child(_guide_icon)

	# --- Panel HP (haut gauche) ---
	var M   := _M
	var pw  := PANEL_W * M
	var ph  := PANEL_H * M
	var px  := PANEL_X * M
	var py  := PANEL_Y * M
	var bw  := BAR_W   * M
	var bh  := BAR_H   * M
	var bx  := BAR_X   * M
	var by  := BAR_Y   * M

	_container              = Control.new()
	_container.name         = "HPPanel"
	_container.size         = Vector2(pw, ph)
	_container.position     = Vector2(px, py)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	# Fond sombre
	var bg             := ColorRect.new()
	bg.color            = COLOR_BG
	bg.size             = Vector2(pw, ph)
	bg.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bg)

	# Ligne décorative verticale gauche (accent)
	var accent_line        := ColorRect.new()
	accent_line.color       = Color(COLOR_CYAN, 0.80)
	accent_line.position    = Vector2(0.0, 0.0)
	accent_line.size        = Vector2(3.0 * M, ph)
	accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(accent_line)

	# Header « SYS · INTEGRITY »
	var header              := Label.new()
	header.text              = "SYS · INTEGRITY"
	header.position          = Vector2(bx, 7.0 * M)
	header.size              = Vector2(160.0 * M, 14.0 * M)
	header.add_theme_font_size_override("font_size", int(9 * M))
	header.add_theme_color_override("font_color", COLOR_HEADER)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(header)

	# Icône ◈ + "HP" à droite du header
	var icon_label              := Label.new()
	icon_label.text              = "◈  HP"
	icon_label.position          = Vector2(pw - 58.0 * M, 7.0 * M)
	icon_label.size              = Vector2(50.0 * M, 14.0 * M)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	icon_label.add_theme_font_size_override("font_size", int(9 * M))
	icon_label.add_theme_color_override("font_color", Color(COLOR_CYAN, 0.55))
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(icon_label)

	# Séparateur fin
	var sep            := ColorRect.new()
	sep.color           = COLOR_SEP
	sep.position        = Vector2(bx, 24.0 * M)
	sep.size            = Vector2(pw - bx * 2.0, 1.0)
	sep.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	_container.add_child(sep)

	# --- Barre ---

	# Fond de la barre
	var bar_bg         := ColorRect.new()
	bar_bg.color        = Color(0.0, 0.03, 0.07, 1.0)
	bar_bg.position     = Vector2(bx, by)
	bar_bg.size         = Vector2(bw, bh)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bar_bg)

	# Glow bas (simulé avec deux rects semi-transparents sous la barre)
	_glow2              = ColorRect.new()
	_glow2.color        = Color(COLOR_CYAN, 0.10)
	_glow2.position     = Vector2(bx, by + bh + 2.0 * M)
	_glow2.size         = Vector2(bw, 4.0 * M)
	_glow2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_glow2)

	_glow1              = ColorRect.new()
	_glow1.color        = Color(COLOR_CYAN, 0.22)
	_glow1.position     = Vector2(bx, by + bh)
	_glow1.size         = Vector2(bw, 3.0 * M)
	_glow1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_glow1)

	# Remplissage principal
	_fill               = ColorRect.new()
	_fill.color         = COLOR_CYAN
	_fill.position      = Vector2(bx, by)
	_fill.size          = Vector2(bw, bh)
	_fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_fill)

	# Highlight (ligne brillante en haut de la barre)
	_highlight              = ColorRect.new()
	_highlight.color         = Color(1.0, 1.0, 1.0, 0.28)
	_highlight.position      = Vector2(bx, by)
	_highlight.size          = Vector2(bw, 3.0 * M)
	_highlight.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_highlight)

	# Séparateurs de segments
	for i in SEGMENTS:
		var dx         := bx + bw * float(i + 1) / float(SEGMENTS + 1)
		var seg        := ColorRect.new()
		seg.color       = Color(0.0, 0.0, 0.0, 0.45)
		seg.position    = Vector2(dx, by)
		seg.size        = Vector2(1.5, bh)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(seg)

	# Label HP numérique
	_hp_label               = Label.new()
	_hp_label.position       = Vector2(bx, by + bh + 8.0 * M)
	_hp_label.size           = Vector2(bw, 14.0 * M)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.add_theme_font_size_override("font_size", int(9 * M))
	_hp_label.add_theme_color_override("font_color", COLOR_HPNUM)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_hp_label.add_theme_constant_override("outline_size", 2)
	_hp_label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_hp_label)

	# Coins décoratifs (sur tout le panel)
	_corners = _make_corners(Vector2.ZERO, Vector2(pw, ph), COLOR_BORDER)
	for c in _corners:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(c)


# =============================================================
# COIN COUNTER + BOUTIQUE
# =============================================================

func _build_coin_panel() -> void:
	var M      := _M
	var COIN_W := 180.0 * M
	var COIN_H := 36.0  * M
	var COIN_X := PANEL_X * M
	var COIN_Y := (PANEL_Y + PANEL_H + 6.0 + XP_PANEL_H + 6.0) * M

	var container := Control.new()
	container.name         = "CoinPanel"
	container.position     = Vector2(COIN_X, COIN_Y)
	container.size         = Vector2(COIN_W, COIN_H)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	# Fond
	var bg := ColorRect.new()
	bg.color        = COLOR_BG
	bg.size         = Vector2(COIN_W, COIN_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)

	# Ligne décorative gauche
	var accent := ColorRect.new()
	accent.color       = Color(COLOR_GOLD, 0.85)
	accent.position    = Vector2(0.0, 0.0)
	accent.size        = Vector2(3.0 * M, COIN_H)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(accent)

	# Icône pièce dessinée (compatible toutes plateformes, sans emoji)
	var coin_icon := _CoinIcon.new()
	coin_icon.position     = Vector2(10.0 * M, 8.0 * M)
	coin_icon.size         = Vector2(20.0 * M, 20.0 * M)
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(coin_icon)

	# Label montant uniquement (plus d'emoji)
	_coin_label_hud = Label.new()
	_coin_label_hud.text     = "0"
	_coin_label_hud.position = Vector2(34.0 * M, 0.0)
	_coin_label_hud.size     = Vector2(COIN_W - 34.0 * M, COIN_H)
	_coin_label_hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_label_hud.add_theme_font_size_override("font_size", int(14 * M))
	_coin_label_hud.add_theme_color_override("font_color", COLOR_GOLD)
	_coin_label_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_coin_label_hud)

	# Bouton BOUTIQUE
	# Sur mobile : icône sac de shopping circulaire (tap-friendly)
	# Sur desktop : bouton texte classique + raccourci [B]
	var shop_btn          := Button.new()
	shop_btn.process_mode  = Node.PROCESS_MODE_ALWAYS

	var style_n            := StyleBoxFlat.new()
	style_n.bg_color        = Color(0.0, 0.08, 0.14, 0.90)
	style_n.border_color    = Color(COLOR_CYAN, 0.55)
	style_n.set_border_width_all(1)
	shop_btn.add_theme_stylebox_override("normal", style_n)
	var style_h            := StyleBoxFlat.new()
	style_h.bg_color        = Color(0.0, 0.20, 0.32, 0.95)
	style_h.border_color    = COLOR_CYAN
	style_h.set_border_width_all(1)
	shop_btn.add_theme_stylebox_override("hover", style_h)

	if OS.has_feature("mobile"):
		# Bouton rectangulaire sous le panel pièces (colonne HUD gauche)
		# → hors de portée du joystick et des boutons d'action
		var btn_h    := COIN_H * 1.3
		var btn_y    := COIN_Y + COIN_H + 4.0 * M
		shop_btn.text     = ""
		shop_btn.position = Vector2(COIN_X, btn_y)
		shop_btn.size     = Vector2(COIN_W, btn_h)
		style_n.corner_radius_top_left     = int(btn_h * 0.25)
		style_n.corner_radius_top_right    = int(btn_h * 0.25)
		style_n.corner_radius_bottom_left  = int(btn_h * 0.25)
		style_n.corner_radius_bottom_right = int(btn_h * 0.25)
		style_h.corner_radius_top_left     = int(btn_h * 0.25)
		style_h.corner_radius_top_right    = int(btn_h * 0.25)
		style_h.corner_radius_bottom_left  = int(btn_h * 0.25)
		style_h.corner_radius_bottom_right = int(btn_h * 0.25)
		# Icône centrée carrément dans le bouton
		var icon_sz       := btn_h * 0.82
		var bag_icon      := _ShopBagIcon.new()
		bag_icon.position  = Vector2((COIN_W - icon_sz) * 0.5, (btn_h - icon_sz) * 0.5)
		bag_icon.size      = Vector2(icon_sz, icon_sz)
		bag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shop_btn.add_child(bag_icon)
	else:
		# Bouton texte standard avec raccourci clavier
		shop_btn.text     = tr("UI_SHOP_TITLE") + "  [B]"
		shop_btn.position = Vector2(COIN_X, COIN_Y + COIN_H + 4.0 * M)
		shop_btn.size     = Vector2(COIN_W, 28.0 * M)
		shop_btn.add_theme_font_size_override("font_size", int(11 * M))
		shop_btn.add_theme_color_override("font_color", COLOR_CYAN)

	shop_btn.pressed.connect(_open_shop_from_hud)
	shop_btn.mouse_entered.connect(func():
		if _sfx_player and _SFX_HOVER:
			_sfx_player.stream      = _SFX_HOVER
			_sfx_player.volume_db   = 2.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	shop_btn.pressed.connect(func():
		if _sfx_player and _SFX_CLICK:
			_sfx_player.stream      = _SFX_CLICK
			_sfx_player.volume_db   = 5.0
			_sfx_player.pitch_scale = randf_range(0.97, 1.03)
			_sfx_player.play()
	)
	add_child(shop_btn)


func _open_shop_from_hud() -> void:
	if _shop_open or get_tree().paused:
		return
	# Bloquer l'accès si le joueur est mort
	if _player != null and _player.is_dead:
		return
	_shop_open = true
	get_tree().paused = true

	# Son d'ouverture boutique
	if _sfx_player and _SFX_SHOP_OPEN:
		_sfx_player.stream      = _SFX_SHOP_OPEN
		_sfx_player.volume_db   = 0.0
		_sfx_player.pitch_scale = 1.0
		_sfx_player.play()

	_shop_instance = ShopScript.new()
	get_tree().root.add_child(_shop_instance)
	_shop_instance.tree_exiting.connect(func():
		get_tree().paused = false
		_shop_open    = false
		_shop_instance = null
	)


func _close_shop_from_hud() -> void:
	if not _shop_open or _shop_instance == null:
		return
	# Son de fermeture boutique
	if _SFX_SHOP_CLOSE != null:
		var p := AudioStreamPlayer.new()
		p.stream      = _SFX_SHOP_CLOSE
		p.bus         = "SFX"
		p.volume_db   = 0.0
		p.pitch_scale = 1.0
		get_tree().root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	_shop_instance.queue_free()


# =============================================================
# BARRE XP
# =============================================================

func _build_xp_bar() -> void:
	# Panel XP — juste sous le panel HP, même largeur, style symétrique
	const XP_ACCENT := Color(0.58, 0.20, 1.00, 0.85)   # violet
	const XP_FILL   := Color(0.52, 0.14, 1.00, 1.00)
	const XP_HDR    := Color(0.72, 0.52, 1.00, 0.70)
	const XP_NUM    := Color(0.82, 0.65, 1.00, 0.90)
	const XP_SEP_C  := Color(0.52, 0.20, 1.00, 0.22)
	const XP_SEGS   := 5

	var M    := _M
	var XP_BH := 10.0 * M   # hauteur de la barre
	var XP_BY := 28.0 * M   # offset Y barre dans le panel
	var XP_BX := BAR_X * M
	var XP_BW := BAR_W * M
	var PW    := PANEL_W    * M
	var PH    := XP_PANEL_H * M

	var px := PANEL_X * M
	var py := (PANEL_Y + PANEL_H + 6.0) * M

	var container := Control.new()
	container.name         = "XPPanel"
	container.position     = Vector2(px, py)
	container.size         = Vector2(PW, PH)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	# Fond sombre
	var bg := ColorRect.new()
	bg.color        = COLOR_BG
	bg.size         = Vector2(PW, PH)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)

	# Accent vertical gauche (violet)
	var accent := ColorRect.new()
	accent.color       = XP_ACCENT
	accent.position    = Vector2(0.0, 0.0)
	accent.size        = Vector2(3.0 * M, PH)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(accent)

	# Header "SYS · EXPERIENCE"
	var header := Label.new()
	header.text     = "SYS · EXPERIENCE"
	header.position = Vector2(XP_BX, 7.0 * M)
	header.size     = Vector2(160.0 * M, 14.0 * M)
	header.add_theme_font_size_override("font_size", int(9 * M))
	header.add_theme_color_override("font_color", XP_HDR)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(header)

	# Icône niveau à droite du header
	_xp_level_label          = Label.new()
	_xp_level_label.text     = "LVL 0"
	_xp_level_label.position = Vector2(PW - 58.0 * M, 7.0 * M)
	_xp_level_label.size     = Vector2(50.0 * M, 14.0 * M)
	_xp_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_level_label.add_theme_font_size_override("font_size", int(9 * M))
	_xp_level_label.add_theme_color_override("font_color", Color(0.72, 0.52, 1.0, 0.90)) # Couleur plus vive
	_xp_level_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_xp_level_label.add_theme_constant_override("outline_size", 2)
	_xp_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_xp_level_label)

	# Séparateur fin
	var sep := ColorRect.new()
	sep.color        = XP_SEP_C
	sep.position    = Vector2(XP_BX, 24.0 * M)
	sep.size        = Vector2(PW - XP_BX * 2.0, 1.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sep)

	# Fond de la barre
	var bar_bg := ColorRect.new()
	bar_bg.color        = Color(0.02, 0.0, 0.06, 1.0)
	bar_bg.position     = Vector2(XP_BX, XP_BY)
	bar_bg.size         = Vector2(XP_BW, XP_BH)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bar_bg)

	# Glow sous la barre
	var glow2 := ColorRect.new()
	glow2.color        = Color(0.52, 0.14, 1.0, 0.10)
	glow2.position     = Vector2(XP_BX, XP_BY + XP_BH + 2.0 * M)
	glow2.size         = Vector2(XP_BW, 4.0 * M)
	glow2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(glow2)

	var glow1 := ColorRect.new()
	glow1.color        = Color(0.52, 0.14, 1.0, 0.22)
	glow1.position     = Vector2(XP_BX, XP_BY + XP_BH)
	glow1.size         = Vector2(XP_BW, 3.0 * M)
	glow1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(glow1)

	# Remplissage XP
	_xp_bar_fill          = ColorRect.new()
	_xp_bar_fill.color    = XP_FILL
	_xp_bar_fill.position = Vector2(XP_BX, XP_BY)
	_xp_bar_fill.size     = Vector2(0.0, XP_BH)
	_xp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_xp_bar_fill)

	# Highlight haut de barre
	var hl := ColorRect.new()
	hl.color        = Color(1.0, 1.0, 1.0, 0.22)
	hl.position     = Vector2(XP_BX, XP_BY)
	hl.size         = Vector2(XP_BW, 2.0 * M)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(hl)

	# Séparateurs de segments
	for i in XP_SEGS:
		var dx  := XP_BX + XP_BW * float(i + 1) / float(XP_SEGS + 1)
		var seg := ColorRect.new()
		seg.color       = Color(0.0, 0.0, 0.0, 0.40)
		seg.position    = Vector2(dx, XP_BY)
		seg.size        = Vector2(1.5, XP_BH)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(seg)

	# Label XP numérique (droite, sous la barre)
	_xp_bar_label          = Label.new()
	_xp_bar_label.text     = "0 / 50 XP"
	_xp_bar_label.position = Vector2(XP_BX, XP_BY + XP_BH + 5.0 * M)
	_xp_bar_label.size     = Vector2(XP_BW, 12.0 * M)
	_xp_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_bar_label.add_theme_font_size_override("font_size", int(9 * M))
	_xp_bar_label.add_theme_color_override("font_color", XP_NUM)
	_xp_bar_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_xp_bar_label.add_theme_constant_override("outline_size", 2)
	_xp_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_xp_bar_label)

	# Coins décoratifs violet
	for c in _make_corners(Vector2.ZERO, Vector2(PW, PH), Color(0.55, 0.22, 1.0, 0.65)):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(c)


func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	_xp_target_fill = minf(float(current_xp) / float(max(xp_to_next, 1)), 1.0)
	
	if _xp_bar_label != null:
		_xp_bar_label.text = "%d / %d XP" % [current_xp, xp_to_next]
	var _xm := get_node_or_null("/root/XpManager")
	if _xp_level_label != null and _xm != null:
		_xp_level_label.text = "LVL %d" % int(_xm.get("level"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			if _shop_open:
				_close_shop_from_hud()
			else:
				_open_shop_from_hud()


const COLOR_GOLD := Color(1.0, 0.82, 0.0, 1.0)


func _make_corners(origin: Vector2, sz: Vector2, color: Color) -> Array[ColorRect]:
	var cl := CORNER_LEN * _M
	var ct := CORNER_THK * _M
	var result: Array[ColorRect] = []
	var positions := [
		[origin,                                          Vector2(cl, ct)],
		[origin,                                          Vector2(ct, cl)],
		[origin + Vector2(sz.x - cl, 0),                 Vector2(cl, ct)],
		[origin + Vector2(sz.x - ct, 0),                 Vector2(ct, cl)],
		[origin + Vector2(0, sz.y - ct),                 Vector2(cl, ct)],
		[origin + Vector2(0, sz.y - cl),                 Vector2(ct, cl)],
		[origin + Vector2(sz.x - cl, sz.y - ct),         Vector2(cl, ct)],
		[origin + Vector2(sz.x - ct, sz.y - cl),         Vector2(ct, cl)],
	]
	for p in positions:
		var r         := ColorRect.new()
		r.color        = color
		r.position     = p[0]
		r.size         = p[1]
		result.append(r)
	return result


# =============================================================
# REFRESH
# =============================================================

func _refresh_bar(fill: float) -> void:
	var w := BAR_W * _M * fill
	_fill.size.x      = w
	_highlight.size.x = w
	_glow1.size.x     = w
	_glow2.size.x     = w

	# Couleur selon le niveau de vie
	var col: Color
	if fill > 0.5:
		col = COLOR_CYAN.lerp(Color(1.0, 0.60, 0.0), (1.0 - fill) * 2.0)
	else:
		col = Color(1.0, 0.60, 0.0).lerp(Color(1.0, 0.08, 0.08), (0.5 - fill) * 2.0)

	if _target_fill >= 0.3:
		_fill.color  = col
		_glow1.color = Color(col.r, col.g, col.b, 0.30)
		_glow2.color = Color(col.r, col.g, col.b, 0.14)
		for c in _corners:
			c.color = Color(col.r * 0.6 + 0.0 * 0.4,
							col.g * 0.4 + 0.8 * 0.6,
							col.b * 0.3 + 1.0 * 0.7,
							COLOR_BORDER.a)


# =============================================================
# CALLBACKS
# =============================================================

func _on_hp_changed(new_hp: int) -> void:
	_target_fill = float(new_hp) / float(_player.max_hp)
	_update_label(new_hp)
	_flash_damage_vignette()


func _on_player_died() -> void:
	_target_fill = 0.0
	_update_label(0)


func _update_label(hp: int) -> void:
	_hp_label.text = "%d / %d" % [hp, _player.max_hp]


func _flash_damage_vignette() -> void:
	if _vignette_mat == null:
		return
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette_mat.set_shader_parameter("intensity", 1.0)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(
		func(v: float): _vignette_mat.set_shader_parameter("intensity", v),
		1.0, 0.0, 0.7
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


# =============================================================
# BARRE HP DU BOSS
# =============================================================

func _build_boss_bar() -> void:
	var M       := _M
	var bbw     := BOSS_BAR_WIDTH  * M
	var bbh     := BOSS_BAR_HEIGHT * M
	var panel_h := bbh + 36.0 * M
	var bar_y   := 22.0 * M
	var bar_x   := 10.0 * M

	_boss_bar_container            = Control.new()
	_boss_bar_container.name       = "BossHPContainer"
	_boss_bar_container.size       = Vector2(bbw + 20.0 * M, panel_h)
	_boss_bar_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_boss_bar_container.anchor_top    = 1.0
	_boss_bar_container.anchor_bottom = 1.0
	_boss_bar_container.offset_top    = -panel_h - 18.0 * M
	_boss_bar_container.offset_bottom = -18.0 * M
	_boss_bar_container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_bar_container)

	_boss_name_label = Label.new()
	_boss_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_boss_name_label.size = Vector2(bbw + 20.0 * M, 20.0 * M)
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", int(12 * M))
	_boss_name_label.add_theme_color_override("font_color", COLOR_CYAN)
	_boss_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_boss_name_label.add_theme_constant_override("outline_size", 4)
	_boss_bar_container.add_child(_boss_name_label)

	_boss_bar_bg          = ColorRect.new()
	_boss_bar_bg.color    = Color(0.0, 0.05, 0.1, 0.9)
	_boss_bar_bg.position = Vector2(bar_x, bar_y)
	_boss_bar_bg.size     = Vector2(bbw, bbh)
	_boss_bar_container.add_child(_boss_bar_bg)

	_boss_bar_fill          = ColorRect.new()
	_boss_bar_fill.color    = Color(1.0, 0.2, 0.2)
	_boss_bar_fill.position = Vector2(bar_x, bar_y)
	_boss_bar_fill.size     = Vector2(bbw, bbh)
	_boss_bar_container.add_child(_boss_bar_fill)

	for corner in _make_corners(
		Vector2(bar_x - 2.0 * M, bar_y - 2.0 * M),
		Vector2(bbw + 4.0 * M, bbh + 4.0 * M),
		COLOR_CYAN
	):
		_boss_bar_container.add_child(corner)

	_boss_hp_label          = Label.new()
	_boss_hp_label.position = Vector2(bar_x, bar_y)
	_boss_hp_label.size     = Vector2(bbw, bbh)
	_boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_boss_hp_label.add_theme_font_size_override("font_size", int(9 * M))
	_boss_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_boss_hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_boss_hp_label.add_theme_constant_override("outline_size", 3)
	_boss_bar_container.add_child(_boss_hp_label)

	_boss_bar_container.hide()


func show_boss_bar(boss_name: String, max_hp: int) -> void:
	if _boss_bar_container == null:
		_build_boss_bar()
	_boss_max_hp       = max_hp
	_boss_target_fill  = 1.0
	_boss_current_fill = 1.0
	_boss_name_label.text = boss_name
	_boss_hp_label.text   = "%d / %d" % [max_hp, max_hp]
	_boss_bar_fill.size.x = BOSS_BAR_WIDTH * _M
	_boss_bar_container.show()


func update_boss_hp(current_hp: int, max_hp: int) -> void:
	if _boss_bar_container == null:
		return
	_boss_target_fill   = float(current_hp) / float(max_hp)
	_boss_hp_label.text = "%d / %d" % [current_hp, max_hp]


func hide_boss_bar() -> void:
	if _boss_bar_container != null:
		_boss_bar_container.hide()


# =============================================================
# ICÔNE PIÈCE — dessinée en code (aucun emoji, compatible partout)
# =============================================================

# =============================================================
# ICÔNE BOUTIQUE — sac de shopping dessiné en code
# =============================================================

class _ShopBagIcon extends Control:
	func _draw() -> void:
		var w   := size.x
		var h   := size.y
		var col := Color(0.0, 0.85, 1.0)
		# Lignes fines + jointures rondes manuelles → look épuré, fidèle à l'aperçu
		var lw  := maxf(w * 0.075, 1.4)
		var cr  := lw * 0.52   # rayon cap arrondi = demi-épaisseur

		# ── Panier (trapèze, fill semi-transparent + contour) ──
		var tl := Vector2(w * 0.26, h * 0.30)
		var tr := Vector2(w * 0.88, h * 0.30)
		var br := Vector2(w * 0.82, h * 0.66)
		var bl := Vector2(w * 0.18, h * 0.66)

		draw_colored_polygon(PackedVector2Array([tl, tr, br, bl]),
							 Color(0.0, 0.85, 1.0, 0.28))
		draw_polyline(PackedVector2Array([tl, tr, br, bl, tl]), col, lw, true)
		for pt: Vector2 in [tl, tr, br, bl]:
			draw_circle(pt, cr, col)

		# ── Poignée en L : horizontal → vertical → coin TL du panier ──
		# Le bras vertical est exactement aligné sur tl.x → L parfait.
		var hnd_corner := Vector2(tl.x, h * 0.14)
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.07, h * 0.14),   # bout gauche poignée
			hnd_corner,                      # coude
			tl,                              # jonction haut-gauche panier
		]), col, lw, true)
		draw_circle(hnd_corner, cr, col)

		# ── Axe (plus espacé du panier) ──
		var ax_corner := Vector2(bl.x, h * 0.80)
		var ax_end    := Vector2(w * 0.70, h * 0.80)
		draw_polyline(PackedVector2Array([bl, ax_corner, ax_end]), col, lw, true)
		draw_circle(ax_corner, cr, col)

		# ── Roues ──
		var wr := maxf(w * 0.092, 2.0)
		draw_circle(Vector2(w * 0.28, h * 0.92), wr, col)
		draw_circle(Vector2(w * 0.60, h * 0.92), wr, col)


# =============================================================
# ICÔNE PIÈCE — dessinée en code (aucun emoji, compatible partout)
# =============================================================

class _CoinIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 1.0

		# Ombre portée
		draw_circle(c + Vector2(1.0, 1.5), r, Color(0.0, 0.0, 0.0, 0.35))

		# Disque or principal
		draw_circle(c, r, Color(1.0, 0.80, 0.0))

		# Anneau sombre intérieur (relief)
		draw_arc(c, r * 0.68, 0.0, TAU, 24, Color(0.55, 0.38, 0.0, 0.55), 1.5)

		# Reflet clair en haut à gauche
		draw_circle(c + Vector2(-r * 0.22, -r * 0.22), r * 0.42, Color(1.0, 0.96, 0.55, 0.50))
