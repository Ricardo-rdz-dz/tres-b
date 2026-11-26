extends Control

@onready var destination_label: Label = $MarginContainer/MainLayout/StatusBar/DestinationLabel
@onready var capital_label: Label = $MarginContainer/MainLayout/StatusBar/CapitalLabel
@onready var windshield: Control = $MarginContainer/MainLayout/Windshield
@onready var road_status_label: Label = $MarginContainer/MainLayout/Windshield/CenterContainer/RoadStatusLabel
@onready var progress_bar: ProgressBar = $MarginContainer/MainLayout/ProgressBar
@onready var notification_panel: PanelContainer = $MarginContainer/MainLayout/NotificationPanel
@onready var notif_label: Label = $MarginContainer/MainLayout/NotificationPanel/NotifLayout/NotifLabel
@onready var reply_driving_btn: Button = $MarginContainer/MainLayout/NotificationPanel/NotifLayout/NotifButtons/ReplyDrivingButton
@onready var pull_over_btn: Button = $MarginContainer/MainLayout/NotificationPanel/NotifLayout/NotifButtons/PullOverButton
@onready var arrive_btn: Button = $MarginContainer/MainLayout/ArriveButton

@onready var engine_audio: AudioStreamPlayer = get_node_or_null("EngineAudio")
@onready var notification_audio: AudioStreamPlayer = get_node_or_null("NotificationAudio")
@onready var fine_audio: AudioStreamPlayer = get_node_or_null("FineAudio")

var progress: float = 0.0
var speed: float = 12.0 # % por segundo (~8 segundos de trayecto)
var is_driving: bool = true
var message_triggered: bool = false

func _ready() -> void:
	notification_panel.visible = false
	arrive_btn.visible = false

	reply_driving_btn.pressed.connect(_on_answer_driving_pressed)
	pull_over_btn.pressed.connect(_on_pull_over_pressed)
	arrive_btn.pressed.connect(_on_arrive_pressed)

	var leg: Dictionary = GameState.active_order.get("leg", {})
	var stop_num: int = GameState.current_route_completed_stops + 1
	var total_stops: int = maxi(1, GameState.current_route_total_stops)
	var location: String = str(GameState.active_order.get("location", "el punto de entrega"))
	var km: float = float(leg.get("distance_km", 2.0))
	var est_min: int = int(leg.get("estimated_min", 5))

	if total_stops > 1:
		destination_label.text = "Parada %d/%d · %s (%.1f km · ~%d min)" % [stop_num, total_stops, location, km, est_min]
	else:
		destination_label.text = "Destino: %s (%.1f km · ~%d min)" % [location, km, est_min]

	_update_capital()
	road_status_label.text = "En camino..."
	progress_bar.value = 0.0

	_set_road_driving(true)
	if engine_audio:
		engine_audio.play()

func _process(delta: float) -> void:
	if not is_driving:
		return

	progress = minf(100.0, progress + speed * delta)
	progress_bar.value = progress

	# Al 45% del trayecto llega un mensaje del cliente
	if not message_triggered and progress >= 45.0:
		message_triggered = true
		_trigger_client_message()

	# Al llegar al 100%, nos detenemos y habilitamos el botón de bajar
	if progress >= 100.0:
		is_driving = false
		_set_road_driving(false)
		notification_panel.visible = false
		road_status_label.text = "¡Llegaste al destino!"
		if engine_audio:
			engine_audio.stop()
		arrive_btn.visible = true

func _update_capital() -> void:
	capital_label.text = "Capital: $%.0f" % GameState.capital

func _set_road_driving(driving: bool) -> void:
	if windshield and "is_driving" in windshield:
		windshield.is_driving = driving

func _trigger_client_message() -> void:
	var buyer: String = str(GameState.active_order.get("buyer_name", "El cliente"))
	notif_label.text = "Mensaje de %s: \"¿Ya vienes en camino? Aquí te espero.\"" % buyer
	notification_panel.visible = true
	if notification_audio:
		notification_audio.play()

func _on_answer_driving_pressed() -> void:
	notification_panel.visible = false
	# 30% de probabilidad de multa de $500 por usar el celular manejando
	if randf() < 0.30:
		GameState.capital = maxf(0.0, GameState.capital - 500.0)
		_update_capital()
		if fine_audio:
			fine_audio.play()
		road_status_label.text = "¡Te vio tránsito! Multa de -$500 MXN"
	else:
		road_status_label.text = "Contestaste rápido sin percances. Sigues avanzando..."

func _on_pull_over_pressed() -> void:
	notification_panel.visible = false
	is_driving = false
	_set_road_driving(false)
	if engine_audio:
		engine_audio.stream_paused = true
	road_status_label.text = "Te orillaste de forma segura para contestar..."

	await get_tree().create_timer(2.0).timeout

	road_status_label.text = "Mensaje enviado. Retomando el camino..."
	is_driving = true
	_set_road_driving(true)
	if engine_audio:
		engine_audio.stream_paused = false

func _on_arrive_pressed() -> void:
	var leg_min: float = float(GameState.active_order.get("leg", {}).get("estimated_min", 5))
	GameState.advance_time(leg_min)
	get_tree().change_scene_to_file("res://modules/delivery/DeliveryScene.tscn")
