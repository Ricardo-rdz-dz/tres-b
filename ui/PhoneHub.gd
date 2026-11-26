extends Control

@onready var goal_label: Label = $MarginContainer/MainLayout/TopBar/GoalLabel
@onready var capital_label: Label = $MarginContainer/MainLayout/TopBar/CapitalLabel
@onready var views_label: Label = $MarginContainer/MainLayout/ViewsLabel
@onready var chat_box: VBoxContainer = $MarginContainer/MainLayout/ChatBox
@onready var reply_buttons: VBoxContainer = $MarginContainer/MainLayout/ReplyButtons
@onready var clock_label: Label = $MarginContainer/MainLayout/TopBar/ClockRow/ClockLabel
@onready var speed_button: Button = $MarginContainer/MainLayout/TopBar/ClockRow/SpeedButton

var selected_chat_id: int = -1
var active_tab: String = "chats" # "chats" o "scheduled"
var show_profile_panel: bool = false
var _incoming_timer: Timer
var selected_route_ids: Array[int] = []
var show_route_planner: bool = false

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
	if not GameState.inventory.is_empty() and GameState.get_open_chats_count() < 8:
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
	if show_route_planner:
		_render_route_planner()
	elif selected_chat_id == -1:
		_render_inbox()
	else:
		_render_chat_view(selected_chat_id)

# ==============================================================================
# VISTA 1: BANDEJA DE CHATS (ESTILO MESSENGER / WHATSAPP)
# ==============================================================================
func _render_inbox() -> void:
	_clear_container(chat_box)
	_clear_container(reply_buttons)

	var all_chats: Array = GameState.get_sorted_chats()
	var scheduled_chats: Array = []
	var inbox_chats: Array = []

	for c in all_chats:
		var st: String = String(c.get("status", "open"))
		if st == "scheduled" or st == "accepted":
			scheduled_chats.append(c)
		else:
			inbox_chats.append(c)

	# Barra de pestañas: Chats vs Agendados
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	chat_box.add_child(tabs_row)

	var chats_tab_btn := Button.new()
	chats_tab_btn.text = "Chats (%d)" % inbox_chats.size()
	chats_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chats_tab_btn.disabled = (active_tab == "chats")
	chats_tab_btn.pressed.connect(func():
		active_tab = "chats"
		_refresh_ui()
	)
	tabs_row.add_child(chats_tab_btn)

	var sched_tab_btn := Button.new()
	sched_tab_btn.text = "📅 Agendados (%d)" % scheduled_chats.size()
	sched_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sched_tab_btn.disabled = (active_tab == "scheduled")
	sched_tab_btn.pressed.connect(func():
		active_tab = "scheduled"
		_refresh_ui()
	)
	tabs_row.add_child(sched_tab_btn)

	# Lista filtrada según la pestaña seleccionada
	var list_to_show: Array = scheduled_chats if active_tab == "scheduled" else inbox_chats

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_box.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)

	if list_to_show.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.text = (
			"No tienes citas agendadas todavía. Negocia un chat para agendar tu próxima entrega."
			if active_tab == "scheduled"
			else "Esperando mensajes de compradores en Marketplace..."
		)
		list_vbox.add_child(empty_lbl)
	else:
		for c in list_to_show:
			list_vbox.add_child(_create_inbox_card(c))
	# Barra inferior para armar ruta múltiple (solo Nivel 2+ en pestaña Agendados)
	var max_stops: int = GameState.get_max_route_stops()
	if active_tab == "scheduled" and max_stops > 1:
		# Limpiar IDs que ya no estén en estado "accepted"
		var valid_ids: Array[int] = []
		for rid in selected_route_ids:
			var rc: Dictionary = GameState.get_chat_by_id(rid)
			if not rc.is_empty() and String(rc.get("status", "")) == "accepted":
				valid_ids.append(rid)
		selected_route_ids = valid_ids

		if not selected_route_ids.is_empty():
			var summary: Dictionary = GameState.calculate_multi_stop_route(selected_route_ids)
			var info_txt: String = "Ruta: %d/%d paradas · %.1f km (ida y vuelta) · ~%d min · ~$%.0f gas" % [
				selected_route_ids.size(),
				max_stops,
				float(summary["total_km"]),
				int(summary["total_min"]),
				float(summary["total_fuel"])
			]
			_add_reply_button("🗺️ Ordenar ruta y salir -> (%s)" % info_txt, func():
				show_route_planner = true
				_refresh_ui()
			)
func _create_inbox_card(chat: Dictionary) -> PanelContainer:
	var is_unread: bool = bool(chat.get("unread", false))
	var status: String = String(chat.get("status", "open"))

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
	style.border_width_left = 5

	var badge_text: String = ""
	var badge_color: Color = Color.WHITE
	var name_color: Color = Color(0.92, 0.94, 0.96, 1.0)
	var text_alpha: float = 1.0

	if status == "accepted":
		# Verde: trato cerrado, listo para entregar
		style.bg_color = Color(0.11, 0.22, 0.16, 1.0)
		style.border_color = Color(0.22, 0.80, 0.45, 1.0)
		badge_text = "✓ TRATO CERRADO"
		badge_color = Color(0.45, 0.95, 0.60, 1.0)
	elif status == "completed":
		style.bg_color = Color(0.11, 0.20, 0.16, 1.0)
		style.border_color = Color(0.25, 0.78, 0.48, 1.0)
		badge_text = "✓ ENTREGADO"
		badge_color = Color(0.45, 0.90, 0.62, 1.0)
	elif status == "scheduled":
		var conf_state: String = GameState.get_confirmation_state(chat)
		if conf_state == "ready":
			# Naranja alerta: ya faltan <= 2 horas, toca confirmar
			style.bg_color = Color(0.26, 0.18, 0.10, 1.0)
			style.border_color = Color(1.0, 0.62, 0.18, 1.0)
			badge_text = "⏰ CONFIRMAR CITA"
			badge_color = Color(1.0, 0.72, 0.30, 1.0)
		else:
			# Morado: cita agendada a futuro
			style.bg_color = Color(0.18, 0.14, 0.24, 1.0)
			style.border_color = Color(0.68, 0.45, 0.95, 1.0)
			badge_text = "📅 " + String(chat.get("scheduled_label", "AGENDADA"))
			badge_color = Color(0.80, 0.62, 1.0, 1.0)
	elif status == "lost":
		# Rojo apagado: cliente perdido o fantasma
		style.bg_color = Color(0.16, 0.12, 0.13, 0.85)
		style.border_color = Color(0.65, 0.25, 0.28, 1.0)
		badge_text = "✕ PERDIDO"
		badge_color = Color(0.85, 0.45, 0.45, 1.0)
		name_color = Color(0.68, 0.65, 0.66, 1.0)
		text_alpha = 0.65
	elif status == "rejected":
		# Gris oscuro: rechazado por ti
		style.bg_color = Color(0.12, 0.12, 0.14, 0.80)
		style.border_color = Color(0.38, 0.38, 0.42, 1.0)
		badge_text = "RECHAZADO"
		badge_color = Color(0.60, 0.60, 0.65, 1.0)
		name_color = Color(0.60, 0.60, 0.65, 1.0)
		text_alpha = 0.60
	elif is_unread:
		# Azul brillante: mensaje nuevo sin leer
		style.bg_color = Color(0.14, 0.23, 0.36, 1.0)
		style.border_color = Color(0.25, 0.68, 1.0, 1.0)
		badge_text = "● NUEVO"
		badge_color = Color(0.45, 0.82, 1.0, 1.0)
		name_color = Color(0.85, 0.95, 1.0, 1.0)
	else:
		# Ámbar / neutro: ya lo abriste, en negociación
		style.bg_color = Color(0.16, 0.17, 0.20, 1.0)
		style.border_color = Color(0.88, 0.68, 0.25, 1.0)
		badge_text = "EN NEGOCIACIÓN"
		badge_color = Color(0.95, 0.78, 0.35, 1.0)

	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Fila superior: Nombre + Hora/Día
	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	var name_lbl := Label.new()
	name_lbl.text = String(chat["client_name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", name_color)
	top_row.add_child(name_lbl)

	var time_lbl := Label.new()
	time_lbl.text = GameState.format_message_timestamp(int(chat["last_msg_day"]), String(chat["last_msg_time_str"]))
	time_lbl.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78, text_alpha))
	top_row.add_child(time_lbl)

	# Fila media: Producto + Etiqueta de estado con color
	var mid_row := HBoxContainer.new()
	vbox.add_child(mid_row)

	var sub_lbl := Label.new()
	sub_lbl.text = "%s · $%.0f" % [chat["item"].get("name", "Equipo"), float(chat["offered_price"])]
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 0.68, text_alpha))
	mid_row.add_child(sub_lbl)

	var status_lbl := Label.new()
	status_lbl.text = badge_text
	status_lbl.add_theme_color_override("font_color", badge_color)
	mid_row.add_child(status_lbl)

	# Fila inferior: Último mensaje
	var msgs: Array = chat.get("messages", [])
	var last_text: String = String(msgs[msgs.size() - 1].get("text", "")) if not msgs.is_empty() else ""
	var preview_lbl := Label.new()
	preview_lbl.text = last_text
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_lbl.max_lines_visible = 2
	preview_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, text_alpha))
	vbox.add_child(preview_lbl)

	var open_btn := Button.new()
	open_btn.text = "Abrir chat"
	open_btn.pressed.connect(func(): _open_chat(int(chat["id"])))
	vbox.add_child(open_btn)
	
	# Botón para encadenar entregas si el trato está cerrado y el nivel permite > 1 parada
	var max_stops: int = GameState.get_max_route_stops()
	if status == "accepted" and active_tab == "scheduled" and max_stops > 1:
		var cid: int = int(chat["id"])
		var in_route: bool = selected_route_ids.has(cid)
		var route_btn := Button.new()
		if in_route:
			route_btn.text = "✓ En ruta (Quitar)"
		else:
			route_btn.text = "+ Agregar a ruta (%d/%d)" % [selected_route_ids.size(), max_stops]
			route_btn.disabled = selected_route_ids.size() >= max_stops
		route_btn.pressed.connect(func():
			if selected_route_ids.has(cid):
				selected_route_ids.erase(cid)
			elif selected_route_ids.size() < max_stops:
				selected_route_ids.append(cid)
			_refresh_ui()
		)
		vbox.add_child(route_btn)

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
	# Como ya estás viendo este chat, lo marcamos leído sin disparar ciclo infinito
	chat["unread"] = false

	var loc_id: String = String(chat.get("location_id", ""))
	if loc_id != "":
		var route: Dictionary = GameState.get_route_with_fuel(loc_id)
		views_label.text = "%s · %s (%.1f km · ~%d min · ~$%.0f gas)" % [
			chat["client_name"], route["name"], float(route["distance_km"]), int(route["estimated_min"]), float(route["fuel_cost"])
		]
	else:
		views_label.text = "%s · %s ($%.0f)" % [
			chat["client_name"], chat["item"].get("name", "Equipo"), float(chat["offered_price"])
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
		chat_box.add_child(_create_profile_card(chat))

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
		var stage: String = String(chat.get("stage", "inquiry"))
		if stage == "inquiry":
			var is_pregunton: bool = String(chat.get("archetype_id", "")) == "pregunton"
			var inquiry_btn: String = (
				"Todo al 100%%, sin detalles ($%.0f)" % float(chat["base_price"])
				if is_pregunton
				else "Sí, sigue disponible ($%.0f)" % float(chat["base_price"])
			)
			_add_reply_button(inquiry_btn, func():
				GameState.respond_to_chat(chat_id, "confirm_available")
			)
			_add_reply_button("Ignorar / Rechazar", func():
				GameState.respond_to_chat(chat_id, "reject")
			)
		elif stage == "haggle":
			_add_reply_button("Aceptar oferta ($%.0f)" % float(chat["offered_price"]), func():
				GameState.respond_to_chat(chat_id, "accept_offer")
			)
			if float(chat["offered_price"]) < float(chat["base_price"]):
				_add_reply_button("Mantener precio ($%.0f)" % float(chat["base_price"]), func():
					GameState.respond_to_chat(chat_id, "counter_full")
				)
			_add_reply_button("Rechazar", func():
				GameState.respond_to_chat(chat_id, "reject")
			)
		elif stage == "location":
			for opt_id in GameState.PLAYER_DELIVERY_OPTIONS:
				var r: Dictionary = GameState.get_route_with_fuel(opt_id)
				var btn_txt: String = "%s (%.1f km · ~%d min · ~$%.0f gas)" % [
					r["name"], float(r["distance_km"]), int(r["estimated_min"]), float(r["fuel_cost"])
				]
				_add_reply_button(btn_txt, func():
					GameState.propose_delivery_location(chat_id, opt_id)
				)
		elif stage == "counter_location":
			var cid: String = String(chat.get("counter_location_id", "punto_medio"))
			var cr: Dictionary = GameState.get_route_with_fuel(cid)
			_add_reply_button("Aceptar ir a %s (%.1f km · ~%d min · ~$%.0f gas)" % [
				cr["name"], float(cr["distance_km"]), int(cr["estimated_min"]), float(cr["fuel_cost"])
			], func():
				GameState.respond_counter_location(chat_id, true)
			)
			_add_reply_button("No me conviene (Rechazar)", func():
				GameState.respond_counter_location(chat_id, false)
			)
		elif stage == "scheduling":
			for opt in GameState.get_scheduling_options():
				var opt_min: float = float(opt["target_total_min"])
				var opt_lbl: String = String(opt["label"])
				var opt_tmrw: bool = bool(opt["is_tomorrow"])
				_add_reply_button("📅 " + opt_lbl, func():
					GameState.schedule_delivery(chat_id, opt_min, opt_lbl, opt_tmrw)
				)
				
	elif status == "scheduled":
		var conf_state: String = GameState.get_confirmation_state(chat)
		var mins_left: float = float(chat.get("scheduled_total_min", 0.0)) - GameState.get_total_game_minutes()
		if conf_state == "ready":
			_add_reply_button("⏰ Enviar confirmación de entrega", func():
				GameState.confirm_scheduled_delivery(chat_id)
			)
		else:
			var hrs: int = int(maxf(0.0, mins_left)) / 60
			var mins: int = int(maxf(0.0, mins_left)) % 60
			var wait_to_confirm: float = maxf(1.0, mins_left - 115.0)
			_add_reply_button("⏳ Faltan %dh %02dm · Avanzar hasta confirmación (-2h)" % [hrs, mins], func():
				GameState.advance_time(wait_to_confirm)
				_refresh_ui()
			)
		_add_reply_button("Cancelar cita", func():
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
			

func _create_profile_card(chat: Dictionary) -> PanelContainer:
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
	lbl.text = "Perfil de %s\n• Foto: %s\n• Antigüedad: %s | Amigos: %d" % [
		chat["client_name"],
		photo_txt,
		String(p.get("account_age", "Desconocida")),
		int(p.get("friends", 0))
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
	if GameState.start_delivery_route([int(chat["id"])]):
		get_tree().change_scene_to_file("res://ui/Checklist.tscn")

func _on_time_updated(day: int, _hour: int, _minute: int, formatted_time: String) -> void:
	clock_label.text = "Día %d | %s (%s)" % [day, formatted_time, GameState.get_day_phase_name()]

func _on_speed_button_pressed() -> void:
	var new_speed: float = GameState.toggle_fast_forward()
	speed_button.text = "1x" if new_speed < 2.0 else "2.5x"
	
func _render_route_planner() -> void:
	_clear_container(chat_box)
	_clear_container(reply_buttons)

	var summary: Dictionary = GameState.calculate_multi_stop_route(selected_route_ids)
	views_label.text = "Planificador de Ruta (%d/%d) · %.1f km · ~%d min · ~$%.0f gas" % [
		selected_route_ids.size(),
		GameState.get_max_route_stops(),
		float(summary["total_km"]),
		int(summary["total_min"]),
		float(summary["total_fuel"])
	]

	var back_btn := Button.new()
	back_btn.text = "← Volver a Agendados"
	back_btn.pressed.connect(func():
		show_route_planner = false
		_refresh_ui()
	)
	chat_box.add_child(back_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_box.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)

	var legs: Array = summary.get("legs", [])
	for i in range(legs.size()):
		var leg: Dictionary = legs[i]
		var cid: int = int(leg["chat_id"])
		var chat: Dictionary = GameState.get_chat_by_id(cid)

		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.17, 0.22, 1.0)
		style.border_width_left = 4
		style.border_color = Color(0.25, 0.72, 1.0, 1.0)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)

		var info_lbl := Label.new()
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_lbl.text = "%d° %s (%s)\n%s · +%.1f km (~%d min)" % [
			i + 1,
			String(leg["name"]),
			String(leg["client_name"]),
			String(chat.get("scheduled_label", "Confirmada")),
			float(leg["distance_km"]),
			int(leg["estimated_min"])
		]
		row.add_child(info_lbl)

		var up_btn := Button.new()
		up_btn.text = "↑"
		up_btn.disabled = (i == 0)
		var idx_up: int = i
		up_btn.pressed.connect(func():
			var tmp: int = selected_route_ids[idx_up - 1]
			selected_route_ids[idx_up - 1] = selected_route_ids[idx_up]
			selected_route_ids[idx_up] = tmp
			_refresh_ui()
		)
		row.add_child(up_btn)

		var down_btn := Button.new()
		down_btn.text = "↓"
		down_btn.disabled = (i == legs.size() - 1)
		var idx_dn: int = i
		down_btn.pressed.connect(func():
			var tmp: int = selected_route_ids[idx_dn + 1]
			selected_route_ids[idx_dn + 1] = selected_route_ids[idx_dn]
			selected_route_ids[idx_dn] = tmp
			_refresh_ui()
		)
		row.add_child(down_btn)

		list_vbox.add_child(panel)

	# Tarjeta informativa del regreso a base
	var ret_leg: Dictionary = summary.get("return_leg", {})
	if not ret_leg.is_empty():
		var ret_lbl := Label.new()
		ret_lbl.text = "🏠 Regreso a Base: +%.1f km (~%d min)" % [
			float(ret_leg["distance_km"]),
			int(ret_leg["estimated_min"])
		]
		ret_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85, 1.0))
		list_vbox.add_child(ret_lbl)

	_add_reply_button("Salir a entregar (%d paradas) ->" % selected_route_ids.size(), func():
		if GameState.start_delivery_route(selected_route_ids):
			selected_route_ids.clear()
			show_route_planner = false
			get_tree().change_scene_to_file("res://ui/Checklist.tscn")
	)
