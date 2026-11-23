extends Control

@onready var destination_label: Label = $MarginContainer/MainLayout/StatusBar/DestinationLabel
@onready var capital_label: Label = $MarginContainer/MainLayout/StatusBar/CapitalLabel
@onready var road_status_label: Label = $MarginContainer/MainLayout/Windshield/CenterContainer/RoadStatusLabel
@onready var progress_bar: ProgressBar = $MarginContainer/MainLayout/ProgressBar
@onready var notification_panel: PanelContainer = $MarginContainer/MainLayout/NotificationPanel
@onready var notif_label: Label = $MarginContainer/MainLayout/NotificationPanel/NotifLayout/NotifLabel
@onready var reply_driving_btn: Button = $MarginContainer/MainLayout/NotificationPanel/NotifLayout/NotifButtons/ReplyDrivingButton
@onready var pull_over_btn: Button = $MarginContainer/MainLayout/NotificationPanel/NotifLayout/NotifButtons/PullOverButton
@onready var arrive_btn: Button = $MarginContainer/MainLayout/ArriveButton

var trip_duration: float = 12.0 # Segundos que dura el trayecto
var elapsed_time: float = 0.0
var is_driving: bool = true
var message_triggered: bool = false
var fine_amount: float = 500.0

func _ready() -> void:
	notification_panel.visible = false
	arrive_btn.visible = false

	reply_driving_btn.pressed.connect(_on_reply_driving)
	pull_over_btn.pressed.connect(_on_pull_over)
	arrive_btn.pressed.connect(_on_arrive_pressed)

	var location: String = GameState.active_order.get("location", "Destino")
	destination_label.text = "En camino a: %s" % location
	_update_capital()
	road_status_label.text = "Manejando..."

func _process(delta: float) -> void:
	if not is_driving:
		return

	elapsed_time += delta
	var progress: float = clamp((elapsed_time / trip_duration) * 100.0, 0.0, 100.0)
	progress_bar.value = progress

	# A mitad del camino llega un mensaje del cliente
	if progress >= 45.0 and not message_triggered:
		_trigger_message()

	# Al llegar al 100%, nos detenemos y habilitamos el botón de bajar
	if progress >= 100.0:
		is_driving = false
		notification_panel.visible = false
		road_status_label.text = "¡Llegaste al destino!"
		arrive_btn.visible = true

func _update_capital() -> void:
	capital_label.text = "Capital: $%.0f" % GameState.capital

func _trigger_message() -> void:
	message_triggered = true
	var buyer: String = GameState.active_order.get("buyer_name", "Cliente")
	notif_label.text = "Nuevo mensaje de %s: '¿Ya vienes cerca?'" % buyer
	notification_panel.visible = true

func _on_reply_driving() -> void:
	notification_panel.visible = false
	# 30% de probabilidad de multa por usar el celular manejando
	if randf() < 0.30:
		GameState.apply_fine(fine_amount)
		_update_capital()
		road_status_label.text = "¡MULTA! Te vio tránsito usando el celular (-$%.0f)" % fine_amount
	else:
		road_status_label.text = "Contestaste rápido: 'Ya casi llego'. (Sin multa)"

func _on_pull_over() -> void:
	notification_panel.visible = false
	is_driving = false
	road_status_label.text = "Orillado... Contestando mensaje de forma segura."
	await get_tree().create_timer(2.5).timeout
	road_status_label.text = "Mensaje enviado. Retomando el camino..."
	is_driving = true

func _on_arrive_pressed() -> void:
	print("Llegaste a la entrega. Siguiente: DeliveryScene.tscn")
	# Siguiente paso: cambiar a modules/delivery/DeliveryScene.tscn
