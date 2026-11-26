extends Control

@onready var title_label: Label = $MarginContainer/MainLayout/Header/TitleLabel
@onready var capital_label: Label = $MarginContainer/MainLayout/Header/CapitalLabel
@onready var order_info_label: Label = $MarginContainer/MainLayout/OrderCard/OrderInfoLabel
@onready var dialogue_label: Label = $MarginContainer/MainLayout/DialogueCard/DialogueLabel
@onready var action_buttons: VBoxContainer = $MarginContainer/MainLayout/ActionButtons

var order: Dictionary = {}
var item: Dictionary = {}
var final_price: float = 0.0
var buyer_name: String = "Cliente"

func _ready() -> void:
	order = GameState.active_order
	if order.is_empty():
		dialogue_label.text = "No hay ninguna entrega activa."
		_add_button("Volver", _go_next_scene)
		return

	buyer_name = str(order.get("buyer_name", "Cliente"))
	item = order.get("item", {})
	final_price = float(order.get("agreed_price", item.get("sell_price", 0.0)))
	var location: String = str(order.get("location", "Punto de entrega"))

	var stop_num: int = GameState.current_route_completed_stops + 1
	var total_stops: int = maxi(1, GameState.current_route_total_stops)

	_update_header()
	if total_stops > 1:
		title_label.text = "Parada %d/%d · %s" % [stop_num, total_stops, location]
	else:
		title_label.text = "Entrega en: %s" % location

	order_info_label.text = "Cliente: %s\nProducto: %s\nPrecio acordado: $%.0f MXN" % [
		buyer_name,
		str(item.get("name", "Equipo")),
		final_price
	]

	_evaluate_package()

func _update_header() -> void:
	capital_label.text = "Capital: $%.0f MXN | Meta: $%.0f / $%.0f" % [
		GameState.capital,
		GameState.goal_progress,
		GameState.active_goal_target
	]

func _clear_buttons() -> void:
	for child in action_buttons.get_children():
		child.queue_free()

func _add_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.pressed.connect(callback)
	action_buttons.add_child(btn)

func _get_checklist_flag(key: String) -> bool:
	if order.has(key):
		return bool(order[key])
	if order.has("checklist") and typeof(order["checklist"]) == TYPE_DICTIONARY:
		var checklist: Dictionary = order["checklist"]
		if checklist.has(key):
			return bool(checklist[key])
	return true

func _evaluate_package() -> void:
	var has_device: bool = _get_checklist_flag("has_device")
	var has_charger: bool = _get_checklist_flag("has_charger")

	# 1. Si falta el dispositivo, la venta se cancela automáticamente
	if not has_device:
		dialogue_label.text = "%s: \"¿En serio olvidaste traer el equipo? Así no podemos cerrar el trato. Mejor lo cancelamos.\"" % buyer_name
		_clear_buttons()
		_add_button("Disculparse y continuar", _cancel_sale)
		return

	# 2. Si falta el cargador: 25% cancela, 50% pide descuento de $150, 25% paga completo
	if not has_charger:
		var roll: float = randf()
		if roll < 0.25:
			dialogue_label.text = "%s: \"No trae cargador... La verdad así no me sirve, mejor cancelamos la compra.\"" % buyer_name
			_clear_buttons()
			_add_button("Entendido, continuar", _cancel_sale)
		elif roll < 0.75:
			var discounted_price: float = maxf(0.0, final_price - 150.0)
			dialogue_label.text = "%s: \"Oye, le falta el cargador. Si me haces $150 de descuento (me lo dejas en $%.0f) sí me lo llevo.\"" % [
				buyer_name,
				discounted_price
			]
			_clear_buttons()
			_add_button("Aceptar descuento ($%.0f)" % discounted_price, func():
				final_price = discounted_price
				_show_payment_options()
			)
			_add_button("Rechazar y cancelar venta", _cancel_sale)
		else:
			dialogue_label.text = "%s: \"Veo que faltó el cargador, pero no te preocupes, tengo uno en casa. Te pago los $%.0f completos.\"" % [
				buyer_name,
				final_price
			]
			_show_payment_options()
		return

	# 3. Paquete completo
	dialogue_label.text = "%s: \"Todo se ve excelente y completo. ¿Cómo prefieres que te pague los $%.0f MXN?\"" % [
		buyer_name,
		final_price
	]
	_show_payment_options()

func _show_payment_options() -> void:
	_clear_buttons()
	_add_button("Cobrar en efectivo ($%.0f)" % final_price, func(): _complete_sale("Efectivo"))
	_add_button("Cobrar por transferencia ($%.0f)" % final_price, func(): _complete_sale("Transferencia"))

func _complete_sale(method: String) -> void:
	var cost: float = float(item.get("cost", 0.0))
	var profit: float = maxf(0.0, final_price - cost)

	# Actualizar capital y progreso de meta
	GameState.capital += final_price
	GameState.goal_progress += profit
	GameState.contribute_to_goals(profit)

	# Descontar del inventario
	var item_id: String = str(item.get("id", ""))
	for i in range(GameState.inventory.size() - 1, -1, -1):
		if str(GameState.inventory[i].get("id", "")) == item_id:
			GameState.inventory[i]["stock"] = int(GameState.inventory[i].get("stock", 1)) - 1
			if GameState.inventory[i]["stock"] <= 0:
				GameState.inventory.remove_at(i)
			break
	GameState.mark_chat_completed(int(order.get("chat_id", -1)))

	GameState.save_game()
	_update_header()

	dialogue_label.text = "¡Venta completada por %s!\nRecibiste: $%.0f MXN\nGanancia sumada a tu meta: +$%.0f MXN" % [
		method,
		final_price,
		profit
	]
	_clear_buttons()

	if GameState.has_next_delivery_stop():
		var next_stop: Dictionary = GameState.delivery_queue[0]
		var next_num: int = GameState.current_route_completed_stops + 2
		_add_button("Siguiente parada (%d/%d: %s) ->" % [
			next_num,
			GameState.current_route_total_stops,
			String(next_stop.get("location", "Destino"))
		], _go_next_scene)
	elif GameState.inventory.is_empty():
		_add_button("Sin stock — Ir a surtir inventario", _go_next_scene)
	else:
		_add_button("Volver a casa (PhoneHub)", _go_next_scene)

func _cancel_sale() -> void:
	_go_next_scene()

func _go_next_scene() -> void:
	if GameState.complete_current_stop_and_advance():
		get_tree().change_scene_to_file("res://modules/driving/CarDashboard.tscn")
	else:
		var return_leg: Dictionary = GameState.get_leg_summary(GameState.current_route_origin_id, "base")
		GameState.advance_time(float(return_leg.get("estimated_min", 5)))
		GameState.finish_delivery_route()
		GameState.active_order = {}
		GameState.save_game()

		if GameState.inventory.is_empty():
			get_tree().change_scene_to_file("res://ui/InventoryApp.tscn")
		else:
			get_tree().change_scene_to_file("res://ui/PhoneHub.tscn")
