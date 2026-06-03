extends Control
## Menu coopératif – Lobby créer/rejoindre un salon.
## Style cyberpunk cohérent avec le main menu (BgFX complet, cyan #00D9FF, Xolonium).

# ── Palette (identique au main menu) ─────────────────────────────────────────
const C_BG      := Color(0.025, 0.045, 0.075)
const C_CYAN    := Color(0.0,   0.851, 1.0)
const C_TEXT    := Color(0.88,  0.92,  0.96)
const C_GRAY    := Color(0.40,  0.45,  0.52)
const C_GREEN   := Color(0.18,  0.85,  0.45)
const C_RED     := Color(0.90,  0.25,  0.25)
const C_DARK    := Color(0.012, 0.022, 0.038)
const FONT_PATH := "res://ui_theme/fonts/Xolonium-Regular.ttf"


# ── État ──────────────────────────────────────────────────────────────────────
enum Screen   { MAIN, LOBBY }
enum JoinMode { CODE, IP }
var _screen:    Screen   = Screen.MAIN
var _join_mode: JoinMode = JoinMode.CODE

var _lbl_status:    Label
var _lbl_code:      Label
var _lbl_lan_ip:    Label
var _lbl_players:   VBoxContainer
var _btn_start:     Button
var _lbl_wait:      Label
var _entry_name:      LineEdit
var _entry_code:      LineEdit   # rejoindre par code relay
var _entry_ip:        LineEdit   # rejoindre par IP directe
var _panel_main:    Control
var _panel_lobby:   Control
var _panel_code:    VBoxContainer
var _panel_ip:      VBoxContainer
var _font:          FontFile = null
var _content_root:  Control
var _btn_copy:      Button


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as FontFile
	_build_ui()
	_show_main()
	call_deferred("_animate_entrance")
	NetworkManager.room_code_ready.connect(_on_room_code_ready)
	NetworkManager.connection_success.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.players_updated.connect(_on_players_updated)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.relay_awake.connect(_on_relay_awake)
	# Réveille le relay dès l'ouverture (Render free tier peut dormir)
	_set_status(tr("UI_COOP_SERVER_RELAY"), false)
	NetworkManager.ping_relay()


func _exit_tree() -> void:
	if NetworkManager.room_code_ready.is_connected(_on_room_code_ready):
		NetworkManager.room_code_ready.disconnect(_on_room_code_ready)
	if NetworkManager.connection_success.is_connected(_on_connection_success):
		NetworkManager.connection_success.disconnect(_on_connection_success)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.players_updated.is_connected(_on_players_updated):
		NetworkManager.players_updated.disconnect(_on_players_updated)
	if NetworkManager.game_started.is_connected(_on_game_started):
		NetworkManager.game_started.disconnect(_on_game_started)
	if NetworkManager.relay_awake.is_connected(_on_relay_awake):
		NetworkManager.relay_awake.disconnect(_on_relay_awake)


# ── Animation d'entrée ────────────────────────────────────────────────────────
func _animate_entrance() -> void:
	if _content_root == null or not is_inside_tree():
		return
	_content_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_content_root, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD)


# ── Construction UI ────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Fond
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Animation de fond complète (utilisation de la nouvelle classe globale)
	var fx := AnimatedBackground.new()
	add_child(fx)

	# Conteneur centré
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(540, 0)
	root.add_theme_constant_override("separation", 0)
	center.add_child(root)
	_content_root = root

	# ── En-tête ──────────────────────────────────────────────────────────────
	var deco_top := _make_deco_label("◈  ━━━━━━━━━━━━━━━━━━━━━━━━━━━  ◈")
	root.add_child(deco_top)
	_add_spacer(root, 6)

	var title := Label.new()
	title.text = tr("UI_COOP")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_CYAN)
	if _font: title.add_theme_font_override("font", _font)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("UI_COOP_SURVIVAL_MODE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(C_CYAN, 0.5))
	if _font: subtitle.add_theme_font_override("font", _font)
	root.add_child(subtitle)
	_add_spacer(root, 6)

	var deco_bot := _make_deco_label("─  ─  ─  ─  ─  ─  ─  ─  ─  ─  ─  ─")
	root.add_child(deco_bot)
	_add_spacer(root, 22)

	# ── Panneaux ─────────────────────────────────────────────────────────────
	_panel_main  = _make_panel()
	root.add_child(_panel_main)
	_build_main_panel()

	_add_spacer(root, 14)

	_panel_lobby = _make_panel()
	_panel_lobby.visible = false
	root.add_child(_panel_lobby)
	_build_lobby_panel()

	# ── Bouton retour ─────────────────────────────────────────────────────────
	_add_spacer(root, 18)
	var btn_back := _make_menu_button(tr("UI_COOP_BACK_MENU"))
	btn_back.pressed.connect(_on_back_pressed)
	root.add_child(btn_back)

	# ── Label de statut en bas ────────────────────────────────────────────────
	_add_spacer(root, 10)
	_lbl_status = Label.new()
	_lbl_status.text = ""
	_lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lbl_status.add_theme_color_override("font_color", C_RED)
	_lbl_status.add_theme_font_size_override("font_size", 13)
	if _font: _lbl_status.add_theme_font_override("font", _font)
	root.add_child(_lbl_status)


func _build_main_panel() -> void:
	var vb: VBoxContainer = _panel_main.get_child(0)

	# ── Section RÉSEAU ───────────────────────────────────────────────────────
	# ── Section CRÉER ────────────────────────────────────────────────────────
	_add_section_header(vb, tr("UI_CREATE_SALON"))
	_add_spacer(vb, 10)

	_add_field_label(vb, tr("UI_YOUR_NAME"))
	_add_spacer(vb, 5)
	# Génère un nom de robot aléatoire
	_entry_name = _make_line_edit(NetworkManager.generate_random_name(), 20)
	vb.add_child(_entry_name)
	_add_spacer(vb, 12)

	var btn_host := _make_action_button(tr("UI_COOP_CREATE_ONLINE"), C_CYAN)
	btn_host.pressed.connect(_on_host_pressed)
	vb.add_child(btn_host)

	_add_spacer(vb, 6)

	var btn_host_lan := _make_action_button(tr("UI_COOP_CREATE_LAN"), Color(0.18, 0.78, 0.58))
	btn_host_lan.pressed.connect(_on_host_lan_pressed)
	vb.add_child(btn_host_lan)

	# ── Séparateur ───────────────────────────────────────────────────────────
	_add_spacer(vb, 20)
	var sep_row := HBoxContainer.new()
	sep_row.add_theme_constant_override("separation", 10)
	var sep_l := HSeparator.new()
	sep_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep_l.add_theme_color_override("color", Color(C_CYAN, 0.20))
	var sep_lbl := Label.new()
	sep_lbl.text = tr("UI_OR")
	sep_lbl.add_theme_font_size_override("font_size", 11)
	sep_lbl.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
	if _font: sep_lbl.add_theme_font_override("font", _font)
	var sep_r := HSeparator.new()
	sep_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep_r.add_theme_color_override("color", Color(C_CYAN, 0.20))
	sep_row.add_child(sep_l)
	sep_row.add_child(sep_lbl)
	sep_row.add_child(sep_r)
	vb.add_child(sep_row)
	_add_spacer(vb, 20)

	# ── Section REJOINDRE ────────────────────────────────────────────────────
	_add_section_header(vb, tr("UI_JOIN_SALON"))
	_add_spacer(vb, 12)

	# Sélecteur CODE / IP
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	vb.add_child(join_row)

	var btn_by_code := _make_action_button(tr("UI_BY_CODE"), C_CYAN)
	var btn_by_ip   := _make_action_button(tr("UI_BY_IP"), Color(0.18, 0.78, 0.58))
	btn_by_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_by_ip.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	btn_by_ip.modulate.a = 0.55
	btn_by_code.pressed.connect(func(): _set_join_mode(JoinMode.CODE, btn_by_code, btn_by_ip))
	btn_by_ip.pressed.connect(func():   _set_join_mode(JoinMode.IP,   btn_by_code, btn_by_ip))
	join_row.add_child(btn_by_code)
	join_row.add_child(btn_by_ip)
	_add_spacer(vb, 12)

	# Panneau PAR CODE
	_panel_code = VBoxContainer.new()
	_panel_code.add_theme_constant_override("separation", 0)
	vb.add_child(_panel_code)

	_add_field_label(_panel_code, tr("UI_CODE_LABEL"))
	_add_spacer(_panel_code, 5)
	_entry_code = _make_line_edit("ABC123", 6)
	_entry_code.text = ""
	_panel_code.add_child(_entry_code)
	_add_spacer(_panel_code, 10)

	var btn_join_code := _make_action_button(tr("UI_JOIN"), Color(0.0, 0.55, 0.22))
	btn_join_code.pressed.connect(_on_join_pressed)
	_panel_code.add_child(btn_join_code)

	# Panneau PAR IP
	_panel_ip = VBoxContainer.new()
	_panel_ip.add_theme_constant_override("separation", 0)
	_panel_ip.visible = false
	vb.add_child(_panel_ip)

	_add_field_label(_panel_ip, tr("UI_HOST_IP"))
	_add_spacer(_panel_ip, 5)
	_entry_ip = _make_line_edit("192.168.1.x", 64)
	_entry_ip.text = ""
	_panel_ip.add_child(_entry_ip)
	_add_spacer(_panel_ip, 10)
	var btn_join_ip := _make_action_button(tr("UI_JOIN"), Color(0.0, 0.55, 0.22))
	btn_join_ip.pressed.connect(_on_join_lan_pressed)
	_panel_ip.add_child(btn_join_ip)


func _build_lobby_panel() -> void:
	var vb: VBoxContainer = _panel_lobby.get_child(0)

	# ── Code du salon ────────────────────────────────────────────────────────
	_add_section_header(vb, tr("UI_CODE_LABEL_BIS"))
	_add_spacer(vb, 12)

	var code_box := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_DARK
	cs.border_color = Color(C_CYAN, 0.6)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(4)
	cs.set_content_margin_all(16)
	code_box.add_theme_stylebox_override("panel", cs)
	vb.add_child(code_box)

	var code_inner := VBoxContainer.new()
	code_inner.add_theme_constant_override("separation", 4)
	code_box.add_child(code_inner)

	_lbl_code = Label.new()
	_lbl_code.text = "------"
	_lbl_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_code.add_theme_font_size_override("font_size", 48)
	_lbl_code.add_theme_color_override("font_color", C_CYAN)
	if _font: _lbl_code.add_theme_font_override("font", _font)
	code_inner.add_child(_lbl_code)

	var lbl_hint := Label.new()
	lbl_hint.text = tr("UI_SHARE_CODE")
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.add_theme_color_override("font_color", Color(C_CYAN, 0.40))
	lbl_hint.add_theme_font_size_override("font_size", 11)
	if _font: lbl_hint.add_theme_font_override("font", _font)
	code_inner.add_child(lbl_hint)

	_add_spacer(code_inner, 8)

	# IP LAN toujours visible en dessous (utile pour rejoindre par IP directe)
	var lbl_lan_row := HBoxContainer.new()
	lbl_lan_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lbl_lan_row.add_theme_constant_override("separation", 6)
	code_inner.add_child(lbl_lan_row)

	var lbl_ip_prefix := Label.new()
	lbl_ip_prefix.text = tr("UI_IP_LAN")
	lbl_ip_prefix.add_theme_font_size_override("font_size", 12)
	lbl_ip_prefix.add_theme_color_override("font_color", Color(C_CYAN, 0.35))
	if _font: lbl_ip_prefix.add_theme_font_override("font", _font)
	lbl_lan_row.add_child(lbl_ip_prefix)

	_lbl_lan_ip = Label.new()
	_lbl_lan_ip.text = NetworkManager.get_lan_ip()
	_lbl_lan_ip.add_theme_font_size_override("font_size", 12)
	_lbl_lan_ip.add_theme_color_override("font_color", Color(C_CYAN, 0.75))
	if _font: _lbl_lan_ip.add_theme_font_override("font", _font)
	lbl_lan_row.add_child(_lbl_lan_ip)

	# ── Bouton Copier le code ─────────────────────────────────────────────────
	_add_spacer(vb, 8)
	_btn_copy = _make_action_button(tr("UI_COPY_CODE"), C_CYAN)
	_btn_copy.pressed.connect(_on_copy_pressed)
	vb.add_child(_btn_copy)

	_add_spacer(vb, 22)

	# ── Joueurs connectés ────────────────────────────────────────────────────
	_add_section_header(vb, tr("UI_PLAYERS_CONNECTED"))
	_add_spacer(vb, 10)

	_lbl_players = VBoxContainer.new()
	_lbl_players.add_theme_constant_override("separation", 6)
	vb.add_child(_lbl_players)

	# Slots vides par défaut
	_rebuild_player_slots({})

	_add_spacer(vb, 22)

	# ── Actions ──────────────────────────────────────────────────────────────
	_btn_start = _make_action_button(tr("UI_START_GAME"), C_CYAN)
	_btn_start.visible = false
	_btn_start.pressed.connect(_on_start_pressed)
	vb.add_child(_btn_start)

	_lbl_wait = Label.new()
	_lbl_wait.text = tr("UI_WAITING_HOST")
	_lbl_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_wait.add_theme_color_override("font_color", Color(C_CYAN, 0.50))
	_lbl_wait.add_theme_font_size_override("font_size", 13)
	if _font: _lbl_wait.add_theme_font_override("font", _font)
	_lbl_wait.visible = false
	vb.add_child(_lbl_wait)


# ── Changement d'écran ────────────────────────────────────────────────────────
func _show_main() -> void:
	_screen = Screen.MAIN
	_panel_main.visible = true
	_panel_lobby.visible = false


func _show_lobby() -> void:
	_screen = Screen.LOBBY
	_panel_main.visible = false
	_panel_lobby.visible = true
	_lbl_code.text = NetworkManager.room_code if NetworkManager.room_code != "" else "------"
	if _lbl_lan_ip != null:
		_lbl_lan_ip.text = NetworkManager.get_lan_ip()
	# Le bouton LANCER n'apparaît que lorsqu'il y a au moins 2 joueurs (via _on_players_updated)
	_btn_start.visible = NetworkManager.is_host and NetworkManager.players.size() >= 2
	_lbl_wait.visible  = not NetworkManager.is_host
	# Adapte le label du bouton copier : IP directe ou code relay
	if _btn_copy != null:
		var is_ip: bool = "." in NetworkManager.room_code
		_btn_copy.text = tr("UI_COPY_IP") if is_ip else tr("UI_COPY_CODE")


# ── Handlers boutons ──────────────────────────────────────────────────────────

func _set_join_mode(mode: JoinMode, btn_code: Button, btn_ip: Button) -> void:
	_join_mode = mode
	var is_code := mode == JoinMode.CODE
	_panel_code.visible = is_code
	_panel_ip.visible   = not is_code
	btn_code.modulate.a = 1.0 if is_code else 0.55
	btn_ip.modulate.a   = 1.0 if not is_code else 0.55


func _on_host_lan_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	# Si le champ est vide, on génère un nom et on l'affiche dans l'UI
	if n.is_empty():
		n = NetworkManager.generate_random_name()
		_entry_name.text = n
		
	_set_status(tr("UI_SALON_CREATION"), false)
	NetworkManager.host_lan(n)


func _on_join_lan_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	var ip := _entry_ip.text.strip_edges()
	
	if n.is_empty():
		n = NetworkManager.generate_random_name()
		_entry_name.text = n
		
	if ip.is_empty():
		_set_status(tr("UI_ENTER_IP"), true)
		return
		
	_set_status(tr("UI_CONNEXION_AT") % ip, false)
	NetworkManager.join_lan(ip, n)


func _on_host_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	
	if n.is_empty():
		n = NetworkManager.generate_random_name()
		_entry_name.text = n
		
	_set_status(tr("UI_SALON_CREATION"), false)
	NetworkManager.host_game(n)


func _on_join_pressed() -> void:
	var n := _entry_name.text.strip_edges()
	var c := _entry_code.text.strip_edges().to_upper()
	
	if n.is_empty():
		n = NetworkManager.generate_random_name()
		_entry_name.text = n
		
	if c.length() != 6:
		_set_status(tr("UI_ERROR_CODE"), true)
		return
		
	_set_status(tr("UI_CONNEXION_LOADING"), false)
	NetworkManager.join_game(c, n)


func _on_start_pressed() -> void:
	if NetworkManager.players.size() < 2:
		_set_status(tr("UI_OTHER_PLAYER"), false)
		return
	NetworkManager.start_game()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_game()
	if _screen == Screen.LOBBY:
		_set_status("", false)
		_show_main()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_copy_pressed() -> void:
	var code: String = NetworkManager.room_code
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	var original_label: String = _btn_copy.text
	_btn_copy.text = tr("UI_COPIED")
	var tw := _btn_copy.create_tween()
	tw.tween_interval(1.8)
	tw.tween_callback(func(): _btn_copy.text = original_label)


# ── Callbacks NetworkManager ──────────────────────────────────────────────────
func _on_room_code_ready(code: String) -> void:
	_show_lobby()
	_lbl_code.text = code
	_set_status("", false)


func _on_connection_success() -> void:
	_show_lobby()


func _on_connection_failed(reason: String) -> void:
	_set_status(reason, true)
	if _screen == Screen.LOBBY:
		_show_main()


func _on_players_updated(updated: Dictionary) -> void:
	_rebuild_player_slots(updated)
	if _screen == Screen.LOBBY and NetworkManager.is_host:
		_btn_start.visible = updated.size() >= 2


func _on_relay_awake(ok: bool) -> void:
	if ok:
		_set_status("", false)
	else:
		_set_status(tr("UI_ERROR_RELAY"), true)


func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/coop/coop_arena.tscn")


# ── Construction des slots joueurs ────────────────────────────────────────────
func _rebuild_player_slots(updated: Dictionary) -> void:
	for child in _lbl_players.get_children():
		child.queue_free()

	for slot in MAX_PLAYERS:
		var slot_box := PanelContainer.new()
		var ss := StyleBoxFlat.new()
		var keys: Array = updated.keys()
		var filled: bool = slot < keys.size()
		var pid: int = keys[slot] if filled else -1

		ss.bg_color = Color(0.0, 0.851, 1.0, 0.06) if filled else Color(0.0, 0.0, 0.0, 0.0)
		ss.border_color = Color(C_CYAN, 0.35) if filled else Color(C_CYAN, 0.12)
		ss.set_border_width_all(1)
		ss.set_corner_radius_all(3)
		ss.set_content_margin_all(12)
		slot_box.add_theme_stylebox_override("panel", ss)
		_lbl_players.add_child(slot_box)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		slot_box.add_child(row)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = C_GREEN if filled else Color(C_CYAN, 0.15)
		row.add_child(dot)

		var lbl_slot := Label.new()
		lbl_slot.text = "P%d" % (slot + 1)
		lbl_slot.add_theme_font_size_override("font_size", 11)
		lbl_slot.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
		if _font: lbl_slot.add_theme_font_override("font", _font)
		lbl_slot.custom_minimum_size = Vector2(28, 0)
		row.add_child(lbl_slot)

		var lbl_name := Label.new()
		if filled:
			var pinfo: Dictionary = updated[pid]
			lbl_name.text = pinfo.get("name", "Joueur")
			if pid == 1:
				lbl_name.text += tr("UI_LABEL_HOST")
			lbl_name.add_theme_color_override("font_color", C_TEXT)
		else:
			lbl_name.text = tr("UI_WAITING")
			lbl_name.add_theme_color_override("font_color", Color(C_CYAN, 0.25))
		lbl_name.add_theme_font_size_override("font_size", 14)
		if _font: lbl_name.add_theme_font_override("font", _font)
		row.add_child(lbl_name)


# ── Helpers visuels ───────────────────────────────────────────────────────────
const MAX_PLAYERS := 4

func _set_status(text: String, error: bool) -> void:
	_lbl_status.text = text
	_lbl_status.add_theme_color_override("font_color", C_RED if error else Color(C_CYAN, 0.55))


func _make_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	s.border_color = Color(C_CYAN, 0.22)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(24)
	pc.add_theme_stylebox_override("panel", s)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	pc.add_child(vb)
	return pc


func _add_section_header(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(C_CYAN, 0.70))
	if _font: lbl.add_theme_font_override("font", _font)
	parent.add_child(lbl)


func _add_field_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_CYAN, 0.40))
	if _font: lbl.add_theme_font_override("font", _font)
	parent.add_child(lbl)


func _make_deco_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(C_CYAN, 0.45))
	if _font: l.add_theme_font_override("font", _font)
	return l


func _make_line_edit(placeholder: String, max_length: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.max_length = max_length
	le.custom_minimum_size = Vector2(0, 46)
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_DARK
	sn.border_color = Color(C_CYAN, 0.28)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(3)
	sn.set_content_margin_all(10)
	var sf := sn.duplicate() as StyleBoxFlat
	sf.border_color = Color(C_CYAN, 0.80)
	sf.bg_color = Color(0.0, 0.851, 1.0, 0.05)
	le.add_theme_stylebox_override("normal", sn)
	le.add_theme_stylebox_override("focus",  sf)
	le.add_theme_color_override("font_color", C_TEXT)
	le.add_theme_color_override("font_placeholder_color", Color(C_CYAN, 0.25))
	le.add_theme_color_override("caret_color", C_CYAN)
	le.add_theme_font_size_override("font_size", 18)
	if _font: le.add_theme_font_override("font", _font)
	return le


func _make_action_button(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 50)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(color, 0.0)
	sn.border_color = Color(color, 0.65)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(3)
	sn.set_content_margin_all(12)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(color, 0.12)
	sh.border_color = Color(color, 1.0)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(color, 0.22)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 14)
	if _font: btn.add_theme_font_override("font", _font)
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.10)
	)
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12)
	)
	return btn


func _make_menu_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 42)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sn.border_color = Color(C_CYAN, 0.25)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(3)
	sn.set_content_margin_all(10)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(C_CYAN, 0.07)
	sh.border_color = Color(C_CYAN, 0.65)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	btn.add_theme_color_override("font_color", Color(C_CYAN, 0.6))
	btn.add_theme_color_override("font_hover_color", C_CYAN)
	btn.add_theme_font_size_override("font_size", 13)
	if _font: btn.add_theme_font_override("font", _font)
	return btn


func _add_spacer(parent: Control, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)
