extends Control

@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var device_check: CheckBox = $CenterContainer/VBoxContainer/DeviceCheck
@onready var charger_check: CheckBox = $CenterContainer/VBoxContainer/ChargerCheck
@onready var warranty_check: CheckBox = $CenterContainer/VBoxContainer/WarrantyCheck
@onready var drive_button: Button = $CenterContainer/VBoxContainer/DriveButton

func _ready() -> void:
	drive_button.pressed.connect(_on_drive_pressed)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var total_stops: int = GameState.current_route_total_stops
	if total_stops > 1:
		var lines: Array[String] = []
		lines.append("Ruta de %d paradas — Empaca todo:" % total_stops)
		lines.append("1° %s · %s (%s)" % [
			String(GameState.active_order.get("location", "")),
			String(GameState.active_order.get("item", {}).get("name", "Equipo")),
			String(GameState.active_order.get("buyer_name", "Cliente"))
		])
		for i in range(GameState.delivery_queue.size()):
			var s: Dictionary = GameState.delivery_queue[i]
			lines.append("%d° %s · %s (%s)" % [
				i + 2,
				String(s.get("location", "")),
				String(s.get("item", {}).get("name", "Equipo")),
				String(s.get("buyer_name", "Cliente"))
			])
		title_label.text = "\n".join(lines)
		device_check.text = "Empacar todos los equipos (%d)" % total_stops
	elif GameState.active_order.has("item"):
		var item_name: String = String(GameState.active_order["item"]["name"])
		var location: String = String(GameState.active_order["location"])
		title_label.text = "Entrega en %s" % location
		device_check.text = "Empacar: %s" % item_name

func _on_drive_pressed() -> void:
	var has_dev: bool = device_check.button_pressed
	var has_chg: bool = charger_check.button_pressed
	var has_war: bool = warranty_check.button_pressed

	# Guardamos en la parada actual
	GameState.active_order["has_device"] = has_dev
	GameState.active_order["has_charger"] = has_chg
	GameState.active_order["has_warranty"] = has_war

	# También lo guardamos en las paradas restantes de la ruta
	for stop in GameState.delivery_queue:
		stop["has_device"] = has_dev
		stop["has_charger"] = has_chg
		stop["has_warranty"] = has_war

	print("Checklist guardado: ", GameState.active_order)
	get_tree().change_scene_to_file("res://modules/driving/CarDashboard.tscn")
