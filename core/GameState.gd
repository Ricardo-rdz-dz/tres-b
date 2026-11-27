extends Node

# Perfil y finanzas
var player_name: String = ""
var business_type: String = "electronics"
var capital: float = 5000.0        # Dinero para surtir mercancía
var goal_progress: float = 0.0     # Ganancia neta acumulada hacia la meta

# Meta activa
var active_goal_name: String = "Pay Rent"
var active_goal_target: float = 3000.0

# Estado del mundo
var current_day: int = 1
var is_night: bool = false

# Inventario: lista de diccionarios { "id", "name", "cost", "sell_price", "stock" }
var inventory: Array[Dictionary] = []
# Venta agendada actual { "buyer_name", "item", "location", "agreed_price" }
var active_order: Dictionary = {}
var delivery_queue: Array[Dictionary] = []
var current_route_origin_id: String = "base"
var current_route_total_stops: int = 0
var current_route_completed_stops: int = 0

func register_sale(cost: float, final_price: float) -> void:
	var profit: float = final_price - cost
	capital += cost
	if profit > 0:
		goal_progress += profit

func apply_fine(amount: float) -> void:
	# Las multas se descuentan primero del capital
	capital = max(0.0, capital - amount)
	
# # ==============================================================================
# BLOQUE 2.1: RELOJ IN-GAME Y CICLO DÍA / NOCHE
# ==============================================================================

enum DayPhase { MORNING, AFTERNOON, EVENING, NIGHT }

signal time_updated(day: int, hour: int, minute: int, formatted_time: String)
signal phase_changed(new_phase: DayPhase, phase_name: String)
signal day_changed(new_day: int)

var time_in_minutes: float = 480.0 # Inicia a las 08:00 AM (8 * 60)
var is_clock_running: bool = false
var clock_speed: float = 1.0 # 0.0 = pausa, 1.0 = normal, 2.5 = rápido
var base_minutes_per_second: float = 2.0 # A velocidad 1x: 1 seg real = 2 min en juego
var is_time_paused: bool = false

var _last_emitted_minute: int = -1
var _current_phase: DayPhase = DayPhase.MORNING

func toggle_time_pause() -> bool:
	is_time_paused = not is_time_paused
	return is_time_paused

func _process(delta: float) -> void:
	if not is_clock_running or clock_speed <= 0.0:
		return
	if is_time_paused:
		return
	advance_time(delta * base_minutes_per_second * clock_speed)

func advance_time(minutes: float) -> void:
	if minutes <= 0.0:
		return
	check_scheduled_chats()

	time_in_minutes += minutes

	# Cambio de día al pasar de las 23:59 (1440 minutos)
	while time_in_minutes >= 1440.0:
		time_in_minutes -= 1440.0
		current_day += 1
		day_changed.emit(current_day)

	var total_mins: int = floori(time_in_minutes)
	if total_mins != _last_emitted_minute:
		_last_emitted_minute = total_mins
		var hour: int = get_current_hour()
		var minute: int = get_current_minute()
		time_updated.emit(current_day, hour, minute, get_formatted_time())

		var new_phase: DayPhase = get_day_phase()
		if new_phase != _current_phase:
			_current_phase = new_phase
			is_night = (_current_phase == DayPhase.NIGHT)
			phase_changed.emit(new_phase, get_day_phase_name())

func start_clock() -> void:
	is_clock_running = true

func pause_clock() -> void:
	is_clock_running = false

func set_clock_speed(multiplier: float) -> void:
	clock_speed = clampf(multiplier, 0.0, 5.0)

func toggle_fast_forward() -> float:
	clock_speed = 2.5 if clock_speed < 2.0 else 1.0
	return clock_speed

func start_new_day() -> void:
	current_day += 1
	time_in_minutes = 480.0 # 08:00 AM
	_last_emitted_minute = -1
	_current_phase = DayPhase.MORNING
	is_night = false
	day_changed.emit(current_day)
	phase_changed.emit(_current_phase, get_day_phase_name())
	time_updated.emit(current_day, 8, 0, get_formatted_time())

func get_current_hour() -> int:
	return int(floor(time_in_minutes / 60.0)) % 24

func get_current_minute() -> int:
	return floori(time_in_minutes) % 60

func get_formatted_time() -> String:
	var hour: int = get_current_hour()
	var minute: int = get_current_minute()
	var period: String = "AM" if hour < 12 else "PM"
	var display_hour: int = hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%02d:%02d %s" % [display_hour, minute, period]

func get_day_phase() -> DayPhase:
	var hour: int = get_current_hour()
	if hour >= 6 and hour < 12:
		return DayPhase.MORNING
	elif hour >= 12 and hour < 18:
		return DayPhase.AFTERNOON
	elif hour >= 18 and hour < 21:
		return DayPhase.EVENING
	return DayPhase.NIGHT

func get_day_phase_name() -> String:
	match get_day_phase():
		DayPhase.MORNING:
			return "Mañana"
		DayPhase.AFTERNOON:
			return "Tarde"
		DayPhase.EVENING:
			return "Atardecer"
		_:
			return "Noche"
			
# ==============================================================================
# BLOQUE 2.1 (PASO 2): MAPA DE CIUDAD, UBICACIONES Y CÁLCULOS DE RUTA
# ==============================================================================

const KM_PER_MAP_UNIT: float = 0.15 # Escala: 100 unidades de mapa = 15 km de lado a lado
const FUEL_COST_PER_KM: float = 2.8 # Consumo base en pesos MXN por km aprox.

var current_location_id: String = "casa"
var odometer_km: float = 0.0
var fuel_level: float = 100.0 # Porcentaje de 0.0 a 100.0

var city_locations: Dictionary = {
	"casa": {
		"name": "Tu Base (Casa)",
		"type": "base",
		"pos": Vector2(50, 50),
		"risk_level": 0.0
	},
	"plaza_central": {
		"name": "Plaza Central",
		"type": "plaza",
		"pos": Vector2(58, 42),
		"risk_level": 0.05
	},
	"plaza_norte": {
		"name": "Plaza Galerías Norte",
		"type": "plaza",
		"pos": Vector2(30, 18),
		"risk_level": 0.05
	},
	"tienda_tech": {
		"name": "Zona Comercial Centro",
		"type": "tienda",
		"pos": Vector2(72, 55),
		"risk_level": 0.10
	},
	"super_este": {
		"name": "Supermercado Este",
		"type": "tienda",
		"pos": Vector2(85, 35),
		"risk_level": 0.15
	},
	"colonia_sur": {
		"name": "Colonia Residencial Sur",
		"type": "domicilio",
		"pos": Vector2(45, 82),
		"risk_level": 0.25
	},
	"fracc_oeste": {
		"name": "Fraccionamiento Oeste",
		"type": "domicilio",
		"pos": Vector2(15, 60),
		"risk_level": 0.30
	},
	"zona_industrial": {
		"name": "Parque Industrial",
		"type": "domicilio",
		"pos": Vector2(88, 85),
		"risk_level": 0.40
	 }, 
	"centro_civico": {
		"name": "Centro Cívico",
		"type": "plaza",
		"pos": Vector2(54, 48),
		"risk_level": 0.05
	},
	"galerias_del_valle": {
		"name": "Galerías del Valle",
		"type": "plaza",
		"pos": Vector2(68, 66),
		"risk_level": 0.05
	},
	"plaza_carranza": {
		"name": "Plaza Carranza",
		"type": "plaza",
		"pos": Vector2(82, 46),
		"risk_level": 0.08
	},
	"costco": {
		"name": "Costco",
		"type": "tienda",
		"pos": Vector2(62, 60),
		"risk_level": 0.05
	},
	"villas_del_rey": {
		"name": "Villas del Rey",
		"type": "domicilio",
		"pos": Vector2(36, 74),
		"risk_level": 0.20
	},
	"punto_medio": {
		"name": "Punto Medio Acordado",
		"type": "plaza",
		"pos": Vector2(52, 54),
		"risk_level": 0.10
	},
	"a_domicilio": {
		"name": "Domicilio del Cliente",
		"type": "domicilio",
		"pos": Vector2(22, 70),
		"risk_level": 0.30
	}
}

func get_location_data(loc_id: String) -> Dictionary:
	return city_locations.get(loc_id, city_locations["casa"])

func get_distance_km(from_id: String, to_id: String) -> float:
	var from_pos: Vector2 = get_location_data(from_id)["pos"]
	var to_pos: Vector2 = get_location_data(to_id)["pos"]
	# Multiplicador 1.25 para simular calles reales (no línea recta)
	var dist_km: float = from_pos.distance_to(to_pos) * KM_PER_MAP_UNIT * 1.25
	return snappedf(maxf(dist_km, 0.5), 0.1)

func get_estimated_minutes(from_id: String, to_id: String, speed_kmh: float = 50.0) -> int:
	var dist_km: float = get_distance_km(from_id, to_id)
	var mins: float = (dist_km / maxf(speed_kmh, 10.0)) * 60.0
	return maxi(int(round(mins)), 3)

func get_route_summary(to_id: String, speed_kmh: float = 50.0) -> Dictionary:
	var dist_km: float = get_distance_km(current_location_id, to_id)
	var est_min: int = get_estimated_minutes(current_location_id, to_id, speed_kmh)
	var loc: Dictionary = get_location_data(to_id)
	var night_bonus: float = 0.40 if is_night else 0.0
	return {
		"id": to_id,
		"name": loc["name"],
		"distance_km": dist_km,
		"estimated_min": est_min,
		"fuel_percent": snappedf(dist_km * 1.8, 0.1),
		"risk": clampf(loc["risk_level"] + night_bonus, 0.0, 0.95)
	}
	
	
	# ==============================================================================
# BLOQUE 2.1 (PASO 3): SISTEMA DE METAS Y PROGRESIÓN POR NIVELES
# ==============================================================================

signal goals_updated(level: int, goals: Array)
signal goal_completed(goal: Dictionary)
signal level_completed(completed_level: int, next_level: int)

var current_level: int = 2
var active_goals: Array[Dictionary] = []

# Plantillas base de metas por nivel (puedes editar montos o nombres luego)
var level_templates: Dictionary = {
	1: [
		{"id": "renta_n1", "name": "Pagar Renta", "target": 3500.0, "progress": 0.0, "completed": false, "urgent": false}
	],
	2: [
		{"id": "renta_n2", "name": "Pagar Renta", "target": 4000.0, "progress": 0.0, "completed": false, "urgent": false},
		{"id": "luz_n2", "name": "Recibo de Luz", "target": 1500.0, "progress": 0.0, "completed": false, "urgent": false}
	],
	3: [
		{"id": "renta_n3", "name": "Pagar Renta", "target": 4500.0, "progress": 0.0, "completed": false, "urgent": false},
		{"id": "servicios_n3", "name": "Luz e Internet", "target": 2200.0, "progress": 0.0, "completed": false, "urgent": false},
		{"id": "ahorro_auto", "name": "Enganche Auto", "target": 12000.0, "progress": 0.0, "completed": false, "urgent": false}
	]
}

func load_level_goals(level: int) -> void:
	current_level = maxi(level, 1)
	active_goals.clear()

	if level_templates.has(current_level):
		for template in level_templates[current_level]:
			active_goals.append(template.duplicate(true))
	else:
		# Si supera los niveles predefinidos, genera metas escalables automáticamente
		var scale_factor: float = float(current_level)
		active_goals.append({
			"id": "meta_nivel_%d" % current_level,
			"name": "Expansión Nivel %d" % current_level,
			"target": 5000.0 * scale_factor,
			"progress": 0.0,
			"completed": false,
			"urgent": false
		})

	goals_updated.emit(current_level, active_goals)

func add_custom_goal(goal_name: String, target_amount: float, is_urgent: bool = false) -> void:
	var new_goal: Dictionary = {
		"id": "custom_%d" % Time.get_ticks_msec(),
		"name": goal_name,
		"target": maxf(target_amount, 100.0),
		"progress": 0.0,
		"completed": false,
		"urgent": is_urgent
	}
	# Si es urgente (ej. llantas), la pone al principio para darle prioridad
	if is_urgent:
		active_goals.push_front(new_goal)
	else:
		active_goals.append(new_goal)
	goals_updated.emit(current_level, active_goals)

func contribute_to_goals(amount: float) -> void:
	if amount <= 0.0:
		return
	if active_goals.is_empty():
		load_level_goals(current_level)

	var remaining: float = amount
	for goal in active_goals:
		if goal["completed"] or remaining <= 0.0:
			continue

		var needed: float = goal["target"] - goal["progress"]
		var applied: float = minf(remaining, needed)
		goal["progress"] += applied
		remaining -= applied

		if goal["progress"] >= goal["target"]:
			goal["progress"] = goal["target"]
			goal["completed"] = true
			goal_completed.emit(goal)

	goals_updated.emit(current_level, active_goals)
	_check_level_completion()

func _check_level_completion() -> void:
	if active_goals.is_empty():
		return
	for goal in active_goals:
		if not goal["completed"]:
			return

	var finished_level: int = current_level
	current_level += 1
	level_completed.emit(finished_level, current_level)
	load_level_goals(current_level)

func get_goals_summary_text() -> String:
	if active_goals.is_empty():
		load_level_goals(current_level)
	var lines: Array[String] = ["Nivel %d:" % current_level]
	for goal in active_goals:
		var check: String = "✓" if goal["completed"] else "•"
		var tag: String = " [URGENTE]" if goal["urgent"] else ""
		lines.append("%s %s%s: $%.0f / $%.0f" % [check, goal["name"], tag, goal["progress"], goal["target"]])
	return "\n".join(lines)
	
# ==============================================================================
# BLOQUE 2.1 (PASO 4): GUARDADO LOCAL CIFRADO Y BANCARROTA
# ==============================================================================

const SAVE_PATH: String = "user://savegame.dat"
const SAVE_PASS: String = "tres_b_save_key_2026"
const MIN_VIABLE_CAPITAL: float = 500.0 # Capital mínimo para comprar el producto más barato

signal game_saved()
signal game_loaded()
signal bankruptcy_triggered(current_capital: float)

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> bool:
	var save_data: Dictionary = {
		"capital": capital,
		"inventory": inventory,
		"current_day": current_day,
		"time_in_minutes": time_in_minutes,
		"is_night": is_night,
		"current_location_id": current_location_id,
		"odometer_km": odometer_km,
		"fuel_level": fuel_level,
		"current_level": current_level,
		"active_goals": active_goals
	}

	var file: FileAccess = FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, SAVE_PASS)
	if file == null:
		push_error("No se pudo abrir el archivo de guardado: %s" % FileAccess.get_open_error())
		return false

	file.store_string(JSON.stringify(save_data))
	file.close()
	game_saved.emit()
	return true

func load_game() -> bool:
	if not has_save_file():
		return false

	var file: FileAccess = FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.READ, SAVE_PASS)
	if file == null:
		push_error("No se pudo leer el archivo de guardado.")
		return false

	var json_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("El archivo de guardado está dañado.")
		return false

	var data: Dictionary = parsed
	capital = float(data.get("capital", 5000.0))

	if data.has("inventory") and typeof(data["inventory"]) == TYPE_ARRAY:
		inventory.assign(data["inventory"])

	current_day = int(data.get("current_day", 1))
	time_in_minutes = float(data.get("time_in_minutes", 480.0))
	is_night = bool(data.get("is_night", false))
	current_location_id = String(data.get("current_location_id", "casa"))
	odometer_km = float(data.get("odometer_km", 0.0))
	fuel_level = float(data.get("fuel_level", 100.0))
	current_level = int(data.get("current_level", 1))

	active_goals.clear()
	if data.has("active_goals") and typeof(data["active_goals"]) == TYPE_ARRAY:
		for g in data["active_goals"]:
			if typeof(g) == TYPE_DICTIONARY:
				active_goals.append(g)

	if active_goals.is_empty():
		load_level_goals(current_level)

	_last_emitted_minute = -1
	_current_phase = get_day_phase()
	is_night = (_current_phase == DayPhase.NIGHT)

	goals_updated.emit(current_level, active_goals)
	time_updated.emit(current_day, get_current_hour(), get_current_minute(), get_formatted_time())
	game_loaded.emit()
	return true

func delete_save() -> void:
	if has_save_file():
		DirAccess.remove_absolute(SAVE_PATH)

func check_bankruptcy() -> bool:
	# Quiebra si no tienes inventario para vender y tu capital no alcanza para comprar stock
	if inventory.is_empty() and capital < MIN_VIABLE_CAPITAL:
		bankruptcy_triggered.emit(capital)
		return true
	return false

func take_emergency_loan(amount: float = 2000.0, interest_rate: float = 0.25) -> void:
	capital += amount
	var total_to_pay: float = amount * (1.0 + interest_rate)
	add_custom_goal("Préstamo de Emergencia", total_to_pay, true)
	save_game()
	
# ==============================================================================
# BLOQUE 2.2: CATÁLOGO DE DIÁLOGOS Y BANDEJA DE CHATS (ESTILO MESSENGER)
# ==============================================================================

const DIALOGUES_PATH: String = "res://data/dialogues.json"

signal chats_updated()
signal new_chat_received(chat: Dictionary)

var dialogues_catalog: Dictionary = {}
var active_chats: Array[Dictionary] = []
var _next_chat_id: int = 1

const PLAYER_DELIVERY_OPTIONS: Array[String] = [
	"centro_civico",
	"galerias_del_valle",
	"plaza_carranza",
	"costco",
	"plaza_central"
]

func get_route_with_fuel(loc_id: String) -> Dictionary:
	var info: Dictionary = get_route_summary(loc_id).duplicate()
	var km: float = float(info.get("distance_km", 2.0))
	# Estimado ida y vuelta (~$5 MXN por km de distancia lineal, redondeado a $5)
	var fuel_cost: float = maxf(10.0, snappedf(km * 5.0, 5.0))
	info["fuel_cost"] = fuel_cost
	return info
func get_max_route_stops() -> int:
	# Nivel 1: 1 entrega (sin rutas múltiples) | Nivel 2: 2 | ... | Nivel 5+: máx 5
	return clampi(current_level, 1, 5)

func _get_location_coords(loc_id: String) -> Vector2:
	if loc_id == "" or loc_id == "base":
		# Si tu base usa una variable distinta a Vector2.ZERO, ponla aquí
		return city_locations.get("base", {}).get("pos", Vector2.ZERO)
	return city_locations.get(loc_id, {}).get("pos", Vector2.ZERO)

func get_leg_summary(from_loc_id: String, to_loc_id: String) -> Dictionary:
	var from_pos: Vector2 = _get_location_coords(from_loc_id)
	var to_pos: Vector2 = _get_location_coords(to_loc_id)
	var km: float = maxf(0.5, snappedf(from_pos.distance_to(to_pos) / 30.0, 0.1))
	var est_min: int = maxi(2, int(round(km * 1.4)))
	var fuel_cost: float = maxf(5.0, snappedf(km * 2.5, 5.0))
	var dest_name: String = "Base" if (to_loc_id == "" or to_loc_id == "base") else String(city_locations.get(to_loc_id, {}).get("name", to_loc_id))
	return {
		"from_id": from_loc_id,
		"to_id": to_loc_id,
		"name": dest_name,
		"distance_km": km,
		"estimated_min": est_min,
		"fuel_cost": fuel_cost
	}
func _pick_random_client_origin() -> String:
	var valid_ids: Array[String] = []
	for key in city_locations.keys():
		var k: String = String(key)
		if k != "base" and k != "punto_medio" and k != "domicilio":
			valid_ids.append(k)
	if valid_ids.is_empty():
		return "centro_civico"
	return valid_ids[randi() % valid_ids.size()]

func calculate_multi_stop_route(chat_ids: Array) -> Dictionary:
	var legs: Array[Dictionary] = []
	var total_km: float = 0.0
	var total_min: int = 0
	var current_origin: String = "base"

	for raw_id in chat_ids:
		var chat: Dictionary = get_chat_by_id(int(raw_id))
		if chat.is_empty():
			continue
		var dest_id: String = String(chat.get("location_id", ""))
		if dest_id == "":
			continue
		var leg: Dictionary = get_leg_summary(current_origin, dest_id)
		leg["chat_id"] = int(chat["id"])
		leg["client_name"] = String(chat.get("client_name", "Cliente"))
		legs.append(leg)
		total_km += float(leg["distance_km"])
		total_min += int(leg["estimated_min"])
		current_origin = dest_id

	# Sumar el tramo de regreso desde la última parada hasta la base
	var return_leg: Dictionary = {}
	if not legs.is_empty():
		return_leg = get_leg_summary(current_origin, "base")
		total_km += float(return_leg["distance_km"])
		total_min += int(return_leg["estimated_min"])

	var total_fuel: float = maxf(10.0, snappedf(total_km * 2.5, 5.0)) if not legs.is_empty() else 0.0
	return {
		"legs": legs,
		"return_leg": return_leg,
		"total_km": snappedf(total_km, 0.1),
		"total_min": total_min,
		"total_fuel": total_fuel
	}
func start_delivery_route(chat_ids: Array) -> bool:
	delivery_queue.clear()
	current_route_origin_id = "base"
	current_route_completed_stops = 0

	var max_stops: int = get_max_route_stops()
	for raw_id in chat_ids:
		if delivery_queue.size() >= max_stops:
			break
		var chat: Dictionary = get_chat_by_id(int(raw_id))
		if chat.is_empty() or String(chat.get("status", "")) != "accepted":
			continue
		delivery_queue.append({
			"chat_id": int(chat["id"]),
			"client_name": String(chat.get("client_name", "Cliente")),
			"buyer_name": String(chat.get("client_name", "Cliente")),
			"item": chat.get("item", {}).duplicate(true),
			"price": float(chat.get("offered_price", 0.0)),
			"agreed_price": float(chat.get("offered_price", 0.0)),
			"location_id": String(chat.get("location_id", "")),
			"location_name": String(chat.get("location_name", "")),
			"location": String(chat.get("location_name", "")),
			"scheduled_total_min": float(chat.get("scheduled_total_min", 0.0)),
			"profile": chat.get("profile", {}).duplicate(true),
			"archetype_id": String(chat.get("archetype_id", "serio"))
		})

	if delivery_queue.is_empty():
		current_route_total_stops = 0
		return false

	current_route_total_stops = delivery_queue.size()
	return _load_next_stop_into_active_order()

func _load_next_stop_into_active_order() -> bool:
	prune_expired_queued_stops()
	if delivery_queue.is_empty():
		finish_delivery_route()
		return false

	var next_stop: Dictionary = delivery_queue.pop_front()
	var leg: Dictionary = get_leg_summary(current_route_origin_id, String(next_stop["location_id"]))
	next_stop["leg"] = leg
	active_order = next_stop
	return true

func has_next_delivery_stop() -> bool:
	prune_expired_queued_stops()
	return not delivery_queue.is_empty()

func complete_current_stop_and_advance() -> bool:
	if not active_order.is_empty():
		var finished_chat_id: int = int(active_order.get("chat_id", -1))
		mark_chat_completed(finished_chat_id)
		current_route_origin_id = String(active_order.get("location_id", "base"))
		current_route_completed_stops += 1

	return _load_next_stop_into_active_order()

func prune_expired_queued_stops() -> void:
	if delivery_queue.is_empty():
		return
	var now_total: float = get_total_game_minutes()
	var kept: Array[Dictionary] = []
	var changed: bool = false

	for stop in delivery_queue:
		var target_min: float = float(stop.get("scheduled_total_min", 0.0))
		if target_min > 0.0 and now_total > target_min + 45.0:
			var cid: int = int(stop.get("chat_id", -1))
			var chat: Dictionary = get_chat_by_id(cid)
			if not chat.is_empty() and String(chat.get("status", "")) == "accepted":
				append_chat_message(cid, "client", "Ya te esperé mucho tiempo, ya no lo quiero, gracias.")
				chat["status"] = "lost"
				chat["stage"] = "closed"
				chat["unread"] = true
			changed = true
		else:
			kept.append(stop)

	delivery_queue = kept
	if changed:
		chats_updated.emit()

func finish_delivery_route() -> void:
	delivery_queue.clear()
	current_route_origin_id = "base"
	current_route_total_stops = 0
	current_route_completed_stops = 0

func mark_chat_completed(chat_id: int) -> void:
	if chat_id == -1:
		return
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty():
		return
	if String(chat.get("status", "")) != "lost":
		chat["status"] = "completed"
		chat["stage"] = "closed"
		chat["unread"] = false
		chats_updated.emit()

func load_dialogues_catalog() -> bool:
	if not dialogues_catalog.is_empty():
		return true
	if not FileAccess.file_exists(DIALOGUES_PATH):
		push_error("No se encontró %s" % DIALOGUES_PATH)
		return false

	var file: FileAccess = FileAccess.open(DIALOGUES_PATH, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Error al parsear dialogues.json")
		return false

	dialogues_catalog = parsed
	return true

func get_total_game_minutes() -> float:
	return float((current_day - 1) * 1440) + time_in_minutes

func format_message_timestamp(msg_day: int, msg_time_str: String) -> String:
	if msg_day == current_day:
		return msg_time_str
	return "Día %d · %s" % [msg_day, msg_time_str]

func _fill_template(template: String, vars: Dictionary) -> String:
	var result: String = template
	for key in vars.keys():
		var val: String = str(vars[key])
		result = result.replace("${%s}" % str(key), val)
		result = result.replace("{%s}" % str(key), val)
	return result

func _pick_random_str(arr: Array, fallback: String) -> String:
	if arr.is_empty():
		return fallback
	return String(arr[randi() % arr.size()])

func _pick_weighted_archetype(archetypes: Array) -> Dictionary:
	var valid: Array = []
	for a in archetypes:
		if String(a.get("id", "")) != "post_venta":
			valid.append(a)
	if valid.is_empty():
		return archetypes[0]

	var total_weight: float = 0.0
	var weights: Array[float] = []
	for a in valid:
		var raw_f: Variant = a.get("frecuencia_aproximada", 0.06)
		var w: float = 0.06 if raw_f == null else maxf(float(raw_f), 0.02)
		weights.append(w)
		total_weight += w

	var roll: float = randf() * total_weight
	var acc: float = 0.0
	for i in range(valid.size()):
		acc += weights[i]
		if roll <= acc:
			return valid[i]
	return valid[0]

func _get_suggested_hour_str() -> String:
	var future_hour: int = (get_current_hour() + randi_range(1, 3)) % 24
	var suffix: String = "AM" if future_hour < 12 else "PM"
	var h12: int = future_hour % 12
	if h12 == 0:
		h12 = 12
	return "%d:00 %s" % [h12, suffix]

func generate_incoming_chat() -> Dictionary:
	if inventory.is_empty():
		return {}
	if not load_dialogues_catalog():
		return {}

	var archetypes: Array = dialogues_catalog.get("archetypes", [])
	var names: Array = dialogues_catalog.get("names", ["Cliente"])
	if archetypes.is_empty():
		return {}

	var arch: Dictionary = _pick_weighted_archetype(archetypes)
	var client_name: String = _pick_random_str(names, "Cliente")
	var item: Dictionary = inventory[randi() % inventory.size()]

	var item_name: String = String(item.get("name", "Equipo"))
	var item_cost: float = float(item.get("cost", 1000.0))
	var base_price: float = float(item.get("price", item.get("sell_price", snappedf(item_cost * 1.35, 50.0))))
	var offer_price: float = snappedf(base_price * float(arch.get("offer_multiplier", 1.0)), 50.0)

	var pref_locs: Array = arch.get("preferred_locations", [])
	var loc_id: String = _pick_random_str(pref_locs, "punto_medio")
	var route_info: Dictionary = get_route_summary(loc_id)

	var profile_pool: Array = arch.get("profile_pool", [])
	var profile: Dictionary = {"has_photo": true, "account_age": "1 año", "friends": 100, "red_flag_score": 0}
	if not profile_pool.is_empty():
		profile = profile_pool[randi() % profile_pool.size()].duplicate(true)

	var raw_opener: String = _pick_random_str(arch.get("openers", []), "Hola, ¿sigue disponible el ${producto}?")
	var vars: Dictionary = {
		"producto": item_name,
		"precio": "$%d" % int(base_price),
		"oferta": "$%d" % int(offer_price),
		"ubicacion": route_info["name"],
		"hora": _get_suggested_hour_str(),
		"descripcion": _pick_random_str(["camisa azul", "gorra negra", "sudadera gris", "carro blanco"], "camisa azul"),
		"detalle": _pick_random_str(["la batería", "el touch", "el cargador"], "la batería"),
		"color": _pick_random_str(["negro", "azul", "blanco", "gris"], "negro")
	}
	var opener_text: String = _fill_template(raw_opener, vars)

	var raw_ghost: Variant = arch.get("probabilidad_desaparecer", 0.2)
	var ghost_chance: float = 0.15 if raw_ghost == null else float(raw_ghost)

	var now_total: float = get_total_game_minutes()
	var now_str: String = get_formatted_time()

	var arch_id: String = String(arch.get("id", "serio"))
	var haggle_archetypes: Array[String] = ["regateador", "lowballer", "urgido", "sospechoso"]
	var initial_stage: String = "haggle" if haggle_archetypes.has(arch_id) else "inquiry"

	var chat: Dictionary = {
		"id": _next_chat_id,
		"client_name": client_name,
		"archetype_id": String(arch.get("id", "serio")),
		"archetype_label": String(arch.get("label", "Cliente")),
		"item": item.duplicate(true),
		"base_price": base_price,
		"offered_price": offer_price,
		"location_id": "",
		"location_name": "Por acordar",
		"preferred_location_id": loc_id,
		"preferred_locations": pref_locs.duplicate(),
		"counter_location_id": "",
		"client_origin_id": _pick_random_client_origin(),
		"profile": profile,
		"patience_minutes": float(arch.get("patience_minutes", 180.0)),
		"late_chance": float(arch.get("late_still_interested_chance", 0.5)),
		"ghost_chance": ghost_chance,
		"vars": vars,
		"unread": true,
		"stage": initial_stage, # inquiry, haggle, location, counter_location, closed
		"status": "open",       # open, accepted, lost, rejected
		"created_total_min": now_total,
		"last_updated_total_min": now_total,
		"last_msg_day": current_day,
		"last_msg_time_str": now_str,
		"messages": [
			{
				"sender": "client",
				"text": opener_text,
				"day": current_day,
				"time_str": now_str
			}
		]
	}

	_next_chat_id += 1
	active_chats.append(chat)
	new_chat_received.emit(chat)
	chats_updated.emit()
	return chat



func get_sorted_chats() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = active_chats.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("last_updated_total_min", 0.0)) > float(b.get("last_updated_total_min", 0.0))
	)
	return sorted

func get_chat_by_id(chat_id: int) -> Dictionary:
	for chat in active_chats:
		if int(chat.get("id", -1)) == chat_id:
			return chat
	return {}

func mark_chat_read(chat_id: int) -> void:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty():
		return
	if bool(chat.get("unread", false)):
		chat["unread"] = false
		chats_updated.emit()

func append_chat_message(chat_id: int, sender: String, text: String) -> void:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty():
		return
	var now_str: String = get_formatted_time()
	var msgs: Array = chat["messages"]
	msgs.append({
		"sender": sender,
		"text": text,
		"day": current_day,
		"time_str": now_str
	})
	chat["last_updated_total_min"] = get_total_game_minutes()
	chat["last_msg_day"] = current_day
	chat["last_msg_time_str"] = now_str
	if sender == "client":
		chat["unread"] = true
	chats_updated.emit()

func _get_archetype_by_id(arch_id: String) -> Dictionary:
	for a in dialogues_catalog.get("archetypes", []):
		if String(a.get("id", "")) == arch_id:
			return a
	return {}

func respond_to_chat(chat_id: int, action: String) -> String:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty() or chat["status"] != "open":
		return "closed"

	var arch: Dictionary = _get_archetype_by_id(String(chat["archetype_id"]))
	var vars: Dictionary = chat.get("vars", {}).duplicate()
	vars["producto"] = String(chat["item"].get("name", "Equipo"))
	vars["precio"] = "$%d" % int(chat["base_price"])
	vars["oferta"] = "$%d" % int(chat["offered_price"])

	if action == "reject":
		var stage: String = String(chat.get("stage", "inquiry"))
		if stage == "inquiry":
			append_chat_message(chat_id, "player", "Hola, por el momento ya lo tengo apartado, gracias.")
		else:
			append_chat_message(chat_id, "player", "Por el momento no me conviene la oferta, gracias.")
		chat["status"] = "rejected"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "rejected"

	# 1. Mensaje natural del jugador según la etapa
	if action == "confirm_available":
		append_chat_message(chat_id, "player", "Sí, todavía está disponible en $%d." % int(chat["base_price"]))
	elif action == "counter_full":
		append_chat_message(chat_id, "player", "Lo menos son $%d, ¿te animas?" % int(chat["base_price"]))
	elif action == "accept_offer":
		append_chat_message(chat_id, "player", "Va, te acepto los $%d." % int(chat["offered_price"]))

	# 2. El Fantasma suele dejar en visto aquí
	if String(chat["archetype_id"]) == "fantasma" and randf() <= float(chat.get("ghost_chance", 0.95)):
		var ghost_text: String = _pick_random_str(arch.get("late_lost", []), "(El comprador dejó de responder. El chat quedó en visto.)")
		append_chat_message(chat_id, "client", _fill_template(ghost_text, vars))
		chat["status"] = "lost"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "lost"

	# 3. Revisar si contestaste tarde (incluso al día siguiente)
	var elapsed_min: float = get_total_game_minutes() - float(chat["created_total_min"])
	if elapsed_min > float(chat["patience_minutes"]):
		if randf() > float(chat["late_chance"]):
			var lost_raw: String = _pick_random_str(arch.get("late_lost", []), "Ya compré otro, gracias.")
			append_chat_message(chat_id, "client", _fill_template(lost_raw, vars))
			chat["status"] = "lost"
			chat["stage"] = "closed"
			chats_updated.emit()
			return "lost"

	# 4. Si mantuviste el precio ante un regateo
	if action == "counter_full":
		if String(chat["archetype_id"]) == "lowballer" or randf() > 0.55:
			var leave_raw: String = _pick_random_str(arch.get("reject_haggle_leave", []), "Así está caro, paso. Gracias.")
			append_chat_message(chat_id, "client", _fill_template(leave_raw, vars))
			chat["status"] = "lost"
			chat["stage"] = "closed"
			chats_updated.emit()
			return "lost"
		else:
			chat["offered_price"] = chat["base_price"]
			vars["oferta"] = vars["precio"]
			append_chat_message(chat_id, "client", "Bueno está bien, te doy los %s. ¿Dónde entregas?" % vars["precio"])
			chat["stage"] = "location"
			chats_updated.emit()
			return "location"

	# 5. Perfil Dudoso siempre insiste en su zona desde el inicio
	if String(chat["archetype_id"]) == "sospechoso":
		var pref_id: String = String(chat.get("preferred_location_id", "zona_industrial"))
		var pref_info: Dictionary = get_route_with_fuel(pref_id)
		chat["counter_location_id"] = pref_id
		append_chat_message(chat_id, "client", "Sí lo quiero, pero ahorita no tengo carro. Solo puedo en %s, ¿te animas?" % pref_info["name"])
		chat["stage"] = "counter_location"
		chats_updated.emit()
		return "counter_location"

	# 6. Flujo normal: pasan a negociar el punto de entrega
	append_chat_message(chat_id, "client", "Perfecto, sí me interesa en $%d. ¿Dónde entregas?" % int(chat["offered_price"]))
	chat["stage"] = "location"
	chats_updated.emit()
	return "location"

func propose_delivery_location(chat_id: int, loc_id: String) -> String:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty() or chat["status"] != "open":
		return "closed"

	var chosen_info: Dictionary = get_route_with_fuel(loc_id)
	append_chat_message(chat_id, "player", "Puedo entregar en %s, ¿te queda bien?" % chosen_info["name"])

	var origin_id: String = String(chat.get("client_origin_id", ""))
	if origin_id == "":
		origin_id = _pick_random_client_origin()
		chat["client_origin_id"] = origin_id

	# Medimos qué tan lejos le queda al cliente el punto que propusiste desde su zona
	var dist_for_client: float = float(get_leg_summary(origin_id, loc_id).get("distance_km", 0.0))
	var arch_id: String = String(chat.get("archetype_id", "serio"))

	# El cliente urgido tolera más distancia; en punto medio toleran un poco más
	var max_comfortable_km: float = 2.5
	if arch_id == "urgido":
		max_comfortable_km = 4.0
	elif loc_id == "punto_medio":
		max_comfortable_km = 3.2

	var accepts_player_spot: bool = (loc_id == origin_id) or (dist_for_client <= max_comfortable_km)

	if accepts_player_spot:
		chat["location_id"] = loc_id
		chat["location_name"] = chosen_info["name"]
		var vars: Dictionary = chat.get("vars", {}).duplicate()
		vars["ubicacion"] = chosen_info["name"]
		vars["precio"] = "$%d" % int(chat["offered_price"])
		vars["oferta"] = "$%d" % int(chat["offered_price"])
		append_chat_message(chat_id, "client", "Perfecto, me queda bien en %s. ¿Qué día y a qué hora nos vemos?" % chosen_info["name"])
		chat["stage"] = "scheduling"
		chats_updated.emit()
		return "accepted"
	else:
		# El cliente contrapropone su propia zona de origen
		var counter_id: String = origin_id
		if counter_id == loc_id or counter_id == "":
			counter_id = "a_domicilio"
		var counter_info: Dictionary = get_route_with_fuel(counter_id)
		chat["counter_location_id"] = counter_id
		append_chat_message(
			chat_id,
			"client",
			"%s me queda retirado (como a %.1f km de donde estoy). Sí lo quiero, pero mejor en %s, ¿puedes venir para acá?" % [
				chosen_info["name"],
				dist_for_client,
				counter_info["name"]
			]
		)
		chat["stage"] = "counter_location"
		chats_updated.emit()
		return "counter_location"

func respond_counter_location(chat_id: int, accept_counter: bool) -> String:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty() or chat["status"] != "open":
		return "closed"

	if not accept_counter:
		append_chat_message(chat_id, "player", "Me queda muy lejos por la gasolina y el tiempo, paso. Gracias.")
		append_chat_message(chat_id, "client", "Ni modo, suerte con la venta.")
		chat["status"] = "rejected"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "rejected"

	var loc_id: String = String(chat.get("counter_location_id", "punto_medio"))
	var info: Dictionary = get_route_with_fuel(loc_id)
	chat["location_id"] = loc_id
	chat["location_name"] = info["name"]
	append_chat_message(chat_id, "player", "Va, sí me aviento hasta %s." % info["name"])
	append_chat_message(chat_id, "client", "¡Excelente! ¿Qué día y a qué hora nos vemos en %s?" % info["name"])
	chat["stage"] = "scheduling"
	chats_updated.emit()
	return "accepted"

func _format_hour_12(total_min: float) -> String:
	var mins_in_day: int = int(total_min) % 1440
	var h24: int = mins_in_day / 60
	var m: int = mins_in_day % 60
	var suffix: String = "AM" if h24 < 12 else "PM"
	var h12: int = h24 % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]

func get_scheduling_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var now_total: float = get_total_game_minutes()
	var mins_in_day: float = fmod(now_total, 1440.0)
	var day_start: float = now_total - mins_in_day

	# Opción 1: En 1 hora (si no pasa de las 10:00 PM)
	if mins_in_day + 60.0 <= 22.0 * 60.0:
		var t1: float = snappedf(now_total + 60.0, 30.0)
		options.append({
			"label": "Hoy en ~1 hora (%s)" % _format_hour_12(t1),
			"target_total_min": t1,
			"is_tomorrow": false
		})

	# Opción 2: Hoy más tarde (+4 horas, si no pasa de las 10:00 PM)
	if mins_in_day + 240.0 <= 22.0 * 60.0:
		var t2: float = snappedf(now_total + 240.0, 30.0)
		options.append({
			"label": "Hoy más tarde (%s)" % _format_hour_12(t2),
			"target_total_min": t2,
			"is_tomorrow": false
		})

	# Opción 3 y 4: Mañana mañana y mañana tarde
	var tomorrow_start: float = day_start + 1440.0
	options.append({
		"label": "Mañana · 10:00 AM",
		"target_total_min": tomorrow_start + 10.0 * 60.0,
		"is_tomorrow": true
	})
	options.append({
		"label": "Mañana · 4:00 PM",
		"target_total_min": tomorrow_start + 16.0 * 60.0,
		"is_tomorrow": true
	})
	return options

func schedule_delivery(chat_id: int, target_total_min: float, label_str: String, is_tomorrow: bool) -> String:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty() or chat["status"] != "open":
		return "closed"

	append_chat_message(chat_id, "player", "¿Te parece %s en %s?" % [label_str, chat["location_name"]])

	# Si es Cliente Urgido y lo mandas para mañana, busca otro vendedor
	if String(chat["archetype_id"]) == "urgido" and is_tomorrow:
		append_chat_message(chat_id, "client", "Uf, me urge para hoy mismo. Mejor busco otro, gracias.")
		chat["status"] = "lost"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "lost"

	chat["scheduled_total_min"] = target_total_min
	chat["scheduled_label"] = label_str
	chat["confirm_notified"] = false

	var minutes_until: float = target_total_min - get_total_game_minutes()
	if minutes_until <= 120.0:
		# Si es en 2 horas o menos, queda confirmada al instante
		var arch: Dictionary = _get_archetype_by_id(String(chat["archetype_id"]))
		var vars: Dictionary = chat.get("vars", {}).duplicate()
		vars["ubicacion"] = String(chat["location_name"])
		var accept_raw: String = _pick_random_str(arch.get("accept_reply", []), "Perfecto, nos vemos en ${ubicacion}.")
		append_chat_message(chat_id, "client", _fill_template(accept_raw, vars))
		chat["status"] = "accepted"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "accepted"
	else:
		# Cita a futuro: requiere confirmación 2 horas antes
		append_chat_message(chat_id, "client", "Va, quedamos %s en %s. Me mandas mensaje unas 2 horas antes para confirmar." % [label_str, chat["location_name"]])
		chat["status"] = "scheduled"
		chat["stage"] = "scheduled"
		chats_updated.emit()
		return "scheduled"

func get_confirmation_state(chat: Dictionary) -> String:
	if String(chat.get("status", "")) != "scheduled":
		return "none"
	var minutes_left: float = float(chat.get("scheduled_total_min", 0.0)) - get_total_game_minutes()
	if minutes_left < -30.0:
		return "expired"
	elif minutes_left <= 120.0:
		return "ready"
	return "too_early"

func confirm_scheduled_delivery(chat_id: int) -> String:
	var chat: Dictionary = get_chat_by_id(chat_id)
	if chat.is_empty() or chat["status"] != "scheduled":
		return "closed"

	append_chat_message(chat_id, "player", "¿Qué tal? Solo para confirmar nuestra entrega en %s (%s)." % [
		chat["location_name"], String(chat.get("scheduled_label", ""))
	])

	# Probabilidad de que confirme según el arquetipo
	var arch_id: String = String(chat["archetype_id"])
	var confirm_chance: float = 0.85
	if arch_id == "serio" or arch_id == "sospechoso":
		confirm_chance = 0.92
	elif arch_id == "regateador":
		confirm_chance = 0.75
	elif arch_id == "pregunton":
		confirm_chance = 0.60

	if randf() <= confirm_chance:
		append_chat_message(chat_id, "client", "¡Sí, confirmado! Ahí te veo en %s." % chat["location_name"])
		chat["status"] = "accepted"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "accepted"
	else:
		append_chat_message(chat_id, "client", "Perdón, me salió un imprevisto y ya no voy a poder ir. Qué pena.")
		chat["status"] = "lost"
		chat["stage"] = "closed"
		chats_updated.emit()
		return "lost"

func check_scheduled_chats() -> void:
	var changed: bool = false
	var now_total: float = get_total_game_minutes()

	for chat in active_chats:
		var status: String = String(chat.get("status", ""))
		if status == "scheduled":
			var state: String = get_confirmation_state(chat)
			if state == "ready" and not bool(chat.get("confirm_notified", false)):
				chat["confirm_notified"] = true
				chat["unread"] = true
				changed = true
			elif state == "expired":
				append_chat_message(int(chat["id"]), "client", "Como nunca me confirmaste antes de la hora, ya no fui. Gracias.")
				chat["status"] = "lost"
				chat["stage"] = "closed"
				changed = true
		elif status == "accepted":
			# No cancelar el pedido que ya está activo en ruta o entrega
			if not active_order.is_empty() and int(active_order.get("chat_id", -1)) == int(chat.get("id", -2)):
				continue
			var target_min: float = float(chat.get("scheduled_total_min", 0.0))
			if target_min > 0.0 and now_total > target_min + 45.0:
				append_chat_message(int(chat["id"]), "client", "Te estuve esperando en %s pero nunca llegaste. Ya mejor paso, gracias." % String(chat.get("location_name", "el punto")))
				chat["status"] = "lost"
				chat["stage"] = "closed"
				chat["unread"] = true
				changed = true

	if changed:
		chats_updated.emit()
		
func get_open_chats_count() -> int:
	var count: int = 0
	for c in active_chats:
		var st: String = String(c.get("status", ""))
		if st == "open" or st == "scheduled" or st == "accepted":
			count += 1
	return count
