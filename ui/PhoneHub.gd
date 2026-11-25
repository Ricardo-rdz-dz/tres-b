extends Control

@onready var goal_label: Label = $MarginContainer/MainLayout/TopBar/GoalLabel
@onready var capital_label: Label = $MarginContainer/MainLayout/TopBar/CapitalLabel
@onready var views_label: Label = $MarginContainer/MainLayout/ViewsLabel
@onready var chat_box: VBoxContainer = $MarginContainer/MainLayout/ChatBox
@onready var reply_buttons: VBoxContainer = $MarginContainer/MainLayout/ReplyButtons
@onready var clock_label: Label = $MarginContainer/MainLayout/TopBar/ClockRow/ClockLabel
@onready var speed_button: Button = $MarginContainer/MainLayout/TopBar/ClockRow/SpeedButton

var current_buyer: String = "Carlos M."
var selected_item: Dictionary = {}
var chat_step: int = 0

func _ready() -> void:
	GameState.start_clock()
	GameState.time_updated.connect(_on_time_updated)	# Dentro de _ready():
	speed_button.pressed.connect(_on_speed_button_pressed)	
	GameState.goals_updated.connect(func(_lvl, _goals): _update_header())	
	_on_time_updated(GameState.current_day, GameState.get_current_hour(), GameState.get_current_minute(), GameState.get_formatted_time())
	_update_header()
	if GameState.inventory.is_empty():
		views_label.text = "No items in stock."
		return
		
				


	# Elegimos un producto de tu inventario para que un cliente pregunte por él
	selected_item = GameState.inventory.pick_random()
	var views := randi_range(12, 48)
	views_label.text = "Marketplace: %d views | New message about %s ($%.0f)" % [
		views, selected_item["name"], selected_item["sell_price"]
	]
	_start_chat()
	

func _update_header() -> void:
	goal_label.text = GameState.get_goals_summary_text()
	capital_label.text = "Capital: $%.0f" % GameState.capital

func _add_message(sender: String, text: String) -> void:
	var lbl := Label.new()
	lbl.text = "%s: %s" % [sender, text]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	chat_box.add_child(lbl)

func _clear_replies() -> void:
	for child in reply_buttons.get_children():
		child.queue_free()

func _add_reply_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	reply_buttons.add_child(btn)

func _start_chat() -> void:
	_add_message(current_buyer, "Hola, ¿todavía tienes disponible el %s?" % selected_item["name"])
	_clear_replies()
	_add_reply_button("Sí, disponible. Precio $%.0f" % selected_item["sell_price"], _on_confirm_available)

func _on_confirm_available() -> void:
	_add_message("Tú", "Sí, disponible en $%.0f." % selected_item["sell_price"])
	_add_message(current_buyer, "Perfecto, me interesa. ¿Dónde entregas?")
	_clear_replies()
	_add_reply_button("Punto medio", func(): _on_choose_location("Punto medio"))
	_add_reply_button("Plaza central", func(): _on_choose_location("Plaza central"))
	_add_reply_button("A domicilio", func(): _on_choose_location("Domicilio del cliente"))

func _on_choose_location(location: String) -> void:
	_add_message("Tú", "Entrego en %s." % location)
	_add_message(current_buyer, "Trato hecho, te mando mi ubicación. ¡Aquí te espero!")

	# Guardamos la orden activa para el Checklist y el viaje
	GameState.active_order = {
		"buyer_name": current_buyer,
		"item": selected_item,
		"location": location,
		"agreed_price": selected_item["sell_price"]
	}

	_clear_replies()
	_add_reply_button("Navegar hacia el destino ->", _on_start_delivery)

func _on_start_delivery() -> void:
	print("Order scheduled: ", GameState.active_order)
	get_tree().change_scene_to_file("res://ui/Checklist.tscn")

func _on_time_updated(day: int, _hour: int, _minute: int, formatted_time: String) -> void:
	clock_label.text = "Día %d | %s (%s)" % [day, formatted_time, GameState.get_day_phase_name()]

# Al final del archivo:
func _on_speed_button_pressed() -> void:
	var new_speed: float = GameState.toggle_fast_forward()
	speed_button.text = "1x" if new_speed < 2.0 else "2.5x"
