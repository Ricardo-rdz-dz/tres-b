extends Control

@onready var goal_label: Label = $MarginContainer/MainLayout/TopBar/GoalLabel
@onready var capital_label: Label = $MarginContainer/MainLayout/TopBar/CapitalLabel
@onready var views_label: Label = $MarginContainer/MainLayout/ViewsLabel
@onready var chat_box: VBoxContainer = $MarginContainer/MainLayout/ChatBox
@onready var reply_buttons: VBoxContainer = $MarginContainer/MainLayout/ReplyButtons
@onready var clock_label: Label = $MarginContainer/MainLayout/TopBar/ClockRow/ClockLabel
@onready var speed_button: Button = $MarginContainer/MainLayout/TopBar/ClockRow/SpeedButton

var selected_chat_id: int = -1
var show_profile_panel: bool = false
var _incoming_timer: Timer

func _ready() -> void:
	GameState.start_clock()
	GameState.time_updated.connect(_on_time_updated)
	speed_button.pressed.connect(_on_speed_button_pressed)
	GameState.goals_updated.connect(func(_lvl, _goals): _update_header())
	GameState.chats_updated.connect(_refresh_ui)

	chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_on_time_updated(GameState.current_day, GameState.get_current_hour(), GameState.get_current_minute(), GameState.get_formatted_time())
	_update_header()

	if GameState.inventory.is_empty():
		views_label.text = "Sin inventario. Compra equipos para recibir mensajes."
		_clear_container(chat_box)
		_clear_container(reply_buttons)
		_add_reply_button("Ir a Inventario", func(): get_tree().change_scene_to_file("res://ui/InventoryApp.tscn"))
		return

	# Si la bandeja está vacía, generamos 2 chats iniciales para empezar
	if GameState.active_chats.is_empty():
		GameState.generate_incoming_chat()
		GameState.generate_incoming_chat()

	# Timer para que sigan llegando mensajes nuevos mientras estás en el celular
	_incoming_timer = Timer.new()
	_incoming_timer.wait_time = 15.0
	_incoming_timer.autostart = true
	_incoming_timer.timeout.connect(_on_incoming_timer_timeout)
	add_child(_incoming_timer)

	_refresh_ui()

func _on_incoming_timer_timeout() -> void:
	if not GameState.inventory.is_empty() and GameState.active_chats.size() < 8:
		GameState.generate_incoming_chat()

func _update_header() -> void:
	goal_label.text = GameState.get_goals_summary_text()
	capital_label.text = "Capital: $%.0f" % GameState.capital

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

func _add_reply_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	reply_buttons.add_child(btn)

func _refresh_ui() -> void:
	if selected_chat_id == -1:
		_render_inbox()
	else:
		_render_chat_view(selected_chat_id)

# ==============================================================================
# VISTA 1: BANDEJA DE CHATS (ESTILO MESSENGER / WHATSAPP)
# ==============================================================================
func _render_inbox() -> void:
	_clear_container(chat_box)
	_clear_container(reply_buttons)

	var chats: Array[Dictionary] = GameState.get_sorted_chats()
	var unread_count: int = 0
	for c in chats:
		if bool(c.get("unread", false)):
			unread_count += 1

	views_label.text = "Marketplace · Chats (%d sin leer)" % unread_count

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_box.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)

	for chat in chats:
		list_vbox.add_child(_create_inbox_card(chat))

	_add_reply_button("+ Esperar / Recibir nuevo mensaje", func(): GameState.generate_incoming_chat())

func _create_inbox_card(chat: Dictionary) -> PanelContainer:
	var is_unread: bool = bool(chat.get("unread", false))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	if is_unread:
		style.bg_color = Color(0.16, 0.24, 0.36, 1.0) # Resaltado no leído
		style.border_width_left = 4
		style.border_color = Color(0.25, 0.65, 1.0, 1.0)
	else:
		style.bg_color = Color(0.14, 0.15, 0.18, 1.0)

	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Fila superior: Nombre + Hora/Día
	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	var name_lbl := Label.new()
	var prefix: String = "● " if is_unread else ""
	var status_tag: String = ""
	match String(chat.get("status", "open")):
		"accepted": status_tag = " [TRATO]"
		"lost": status_tag = " [PERDIDO]"
		"rejected": status_tag = " [RECHAZADO]"

	name_lbl.text = "%s%s%s" % [prefix, chat["client_name"], status_tag]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_unread:
		name_lbl.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0, 1.0))
	top_row.add_child(name_lbl)

	var time_lbl := Label.new()
	time_lbl.text = GameState.format_message_timestamp(int(chat["last_msg_day"]), String(chat["last_msg_time_str"]))
	time_lbl.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78, 1.0))
	top_row.add_child(time_lbl)

	# Fila media: Producto y oferta
	var sub_lbl := Label.new()
	sub_lbl.text = "%s · Oferta: $%.0f" % [chat["item"].get("name", "Equipo"), float(chat["offered_price"])]
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 0.68, 1.0))
	vbox.add_child(sub_lbl)

	# Fila inferior: Último mensaje
	var msgs: Array = chat.get("messages", [])
	var last_text: String = String(msgs[msgs.size() - 1].get("text", "")) if not msgs.is_empty() else ""
	var preview_lbl := Label.new()
	preview_lbl.text = last_text
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_lbl.max_lines_visible = 2
	preview_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
	vbox.add_child(preview_lbl)

	# Botón invisible/discreto para abrir el chat
	var open_btn := Button.new()
	open_btn.text = "Abrir chat"
	open_btn.pressed.connect(func(): _open_chat(int(chat["id"])))
	vbox.add_child(open_btn)

	return card

func _open_chat(chat_id: int) -> void:
	selected_chat_id = chat_id
	show_profile_panel = false
	GameState.mark_chat_read(chat_id)
	_refresh_ui()

# ==============================================================================
# VISTA 2: CONVERSACIÓN CON BURBUJAS + INSPECTOR DE PERFIL (RED FLAGS)
# ==============================================================================
func _render_chat_view(chat_id: int) -> void:
	_clear_container(chat_box)
	_clear_container(reply_buttons)

	var chat: Dictionary = GameState.get_chat_by_id(chat_id)
	if chat.is_empty():
		selected_chat_id = -1
		_render_inbox()
		return

	var route: Dictionary = GameState.get_route_summary(String(chat["location_id"]))
	views_label.text = "%s · %s (%.1f km · ~%d min)" % [
		chat["client_name"], route["name"], float(route["distance_km"]), int(route["estimated_min"])
	]

	# Barra superior del chat: Volver + Ver Perfil
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 8)
	chat_box.add_child(nav_row)

	var back_btn := Button.new()
	back_btn.text = "← Chats"
	back_btn.pressed.connect(func():
		selected_chat_id = -1
		show_profile_panel = false
		_refresh_ui()
	)
	nav_row.add_child(back_btn)

	var profile_btn := Button.new()
	profile_btn.text = "Ocultar Perfil" if show_profile_panel else "Ver Perfil (Seguridad)"
	profile_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_btn.pressed.connect(func():
		show_profile_panel = not show_profile_panel
		_refresh_ui()
	)
	nav_row.add_child(profile_btn)

	# Panel opcional de Perfil (Red Flags)
	if show_profile_panel:
		chat_box.add_child(_create_profile_card(chat, route))

	# Área con scroll para las burbujas de mensajes
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_box.add_child(scroll)

	var msg_vbox := VBoxContainer.new()
	msg_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(msg_vbox)

	for m in chat.get("messages", []):
		msg_vbox.add_child(_create_message_bubble(m))

	# Botones de acción según estado del chat
	var status: String = String(chat.get("status", "open"))
	if status == "open":
		_add_reply_button("Aceptar oferta ($%.0f)" % float(chat["offered_price"]), func():
			GameState.respond_to_chat(chat_id, "accept")
		)
		if float(chat["offered_price"]) < float(chat["base_price"]):
			_add_reply_button("Pedir precio completo ($%.0f)" % float(chat["base_price"]), func():
				GameState.respond_to_chat(chat_id, "counter_full")
			)
		_add_reply_button("Rechazar", func():
			GameState.respond_to_chat(chat_id, "reject")
		)
	elif status == "accepted":
		_add_reply_button("Preparar entrega (Checklist) ->", func():
			_start_delivery_from_chat(chat)
		)
	else:
		_add_reply_button("Volver a la bandeja", func():
			selected_chat_id = -1
			_refresh_ui()
		)

func _create_profile_card(chat: Dictionary, route: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.14, 0.16, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var p: Dictionary = chat.get("profile", {})
	var photo_txt: String = "Sí tiene foto" if bool(p.get("has_photo", true)) else "Sin foto de perfil"
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "Perfil de %s\n• Foto: %s\n• Antigüedad: %s | Amigos: %d\n• Punto: %s (%.1f km, ~%d min)" % [
		chat["client_name"],
		photo_txt,
		String(p.get("account_age", "Desconocida")),
		int(p.get("friends", 0)),
		route["name"],
		float(route["distance_km"]),
		int(route["estimated_min"])
	]
	panel.add_child(lbl)
	return panel

func _create_message_bubble(msg: Dictionary) -> HBoxContainer:
	var is_player: bool = (String(msg.get("sender", "client")) == "player")
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_player:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size = Vector2(40, 0)
		row.add_child(spacer)

	var bubble := PanelContainer.new()
	bubble.custom_minimum_size = Vector2(320, 0)
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.bg_color = Color(0.11, 0.42, 0.32, 1.0) if is_player else Color(0.20, 0.22, 0.26, 1.0)
	bubble.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	bubble.add_child(vbox)

	var text_lbl := Label.new()
	text_lbl.text = String(msg.get("text", ""))
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(text_lbl)

	var time_lbl := Label.new()
	time_lbl.text = GameState.format_message_timestamp(int(msg.get("day", GameState.current_day)), String(msg.get("time_str", "")))
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.82, 0.85))
	vbox.add_child(time_lbl)

	row.add_child(bubble)

	if not is_player:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size = Vector2(40, 0)
		row.add_child(spacer)

	return row

func _start_delivery_from_chat(chat: Dictionary) -> void:
	GameState.active_order = {
		"buyer_name": chat["client_name"],
		"item": chat["item"],
		"location": chat["location_name"],
		"location_id": chat["location_id"],
		"agreed_price": float(chat["offered_price"]),
		"profile": chat["profile"],
		"archetype_id": chat["archetype_id"]
	}
	get_tree().change_scene_to_file("res://ui/Checklist.tscn")

func _on_time_updated(day: int, _hour: int, _minute: int, formatted_time: String) -> void:
	clock_label.text = "Día %d | %s (%s)" % [day, formatted_time, GameState.get_day_phase_name()]

func _on_speed_button_pressed() -> void:
	var new_speed: float = GameState.toggle_fast_forward()
	speed_button.text = "1x" if new_speed < 2.0 else "2.5x"
