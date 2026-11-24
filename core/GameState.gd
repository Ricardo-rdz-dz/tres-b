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

var _last_emitted_minute: int = -1
var _current_phase: DayPhase = DayPhase.MORNING

func _process(delta: float) -> void:
	if not is_clock_running or clock_speed <= 0.0:
		return
	advance_time(delta * base_minutes_per_second * clock_speed)

func advance_time(minutes: float) -> void:
	if minutes <= 0.0:
		return

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

var current_level: int = 1
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
