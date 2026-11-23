extends Control

@onready var name_input: LineEdit = $CenterContainer/VBoxContainer/NameInput
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var business_option: OptionButton = $CenterContainer/VBoxContainer/BusinessOption

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	

func _on_start_pressed() -> void:
	var entered_name := name_input.text.strip_edges()
	if entered_name.is_empty():
		entered_name = "Entrepreneur"
	# Si no ha seleccionado nada (o está en el placeholder 0), no avanza
	if business_option.selected < 0 or business_option.is_item_disabled(business_option.selected):
		print("Selecciona un emprendimiento para continuar.")
		return

	GameState.player_name = entered_name
	GameState.business_type = "electronics"
	GameState.capital = 5000.0
	get_tree().change_scene_to_file("res://ui/InventoryApp.tscn")

	print("Profile created! Player: ", GameState.player_name, " | Capital: $", GameState.capital)
