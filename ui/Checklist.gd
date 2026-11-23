extends Control

@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var device_check: CheckBox = $CenterContainer/VBoxContainer/DeviceCheck
@onready var charger_check: CheckBox = $CenterContainer/VBoxContainer/ChargerCheck
@onready var warranty_check: CheckBox = $CenterContainer/VBoxContainer/WarrantyCheck
@onready var drive_button: Button = $CenterContainer/VBoxContainer/DriveButton

func _ready() -> void:
	drive_button.pressed.connect(_on_drive_pressed)

	# Mostrar el producto específico de la orden actual
	if GameState.active_order.has("item"):
		var item_name: String = GameState.active_order["item"]["name"]
		var location: String = GameState.active_order["location"]
		title_label.text = "Entrega en %s" % location
		device_check.text = "Empacar: %s" % item_name

func _on_drive_pressed() -> void:
	# Guardamos qué empacó el jugador para evaluarlo al entregar
	GameState.active_order["has_device"] = device_check.button_pressed
	GameState.active_order["has_charger"] = charger_check.button_pressed
	GameState.active_order["has_warranty"] = warranty_check.button_pressed

	print("Checklist guardado: ", GameState.active_order)
	get_tree().change_scene_to_file("res://modules/driving/CarDashboard.tscn")
