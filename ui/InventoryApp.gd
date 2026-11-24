extends Control

@onready var capital_label: Label = $MarginContainer/MainLayout/Header/CapitalLabel
@onready var product_list: VBoxContainer = $MarginContainer/MainLayout/ProductList
@onready var continue_button: Button = $MarginContainer/MainLayout/ContinueButton

# Catálogo inicial de electrónica
var catalog: Array[Dictionary] = [
	{"id": "earbuds", "name": "Wireless Earbuds", "cost": 400.0, "sell_price": 700.0, "stock": 0},
	{"id": "smartwatch", "name": "Smartwatch", "cost": 1000.0, "sell_price": 1500.0, "stock": 0},
	{"id": "phone", "name": "Budget Smartphone", "cost": 2200.0, "sell_price": 3000.0, "stock": 0},
	{"id": "laptop", "name": "Used Laptop", "cost": 3500.0, "sell_price": 4800.0, "stock": 0}
]

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	product_list.add_theme_constant_override("separation", 12)
	_build_product_rows()
	_update_ui()

func _build_product_rows() -> void:
	for item in catalog:
		var card_panel := PanelContainer.new()
		card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var card_layout := VBoxContainer.new()
		card_layout.add_theme_constant_override("separation", 8)

		# Línea 1: Nombre y costo
		var name_lbl := Label.new()
		name_lbl.text = "%s (Cost: $%.0f)" % [item["name"], item["cost"]]
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		# Línea 2: Precio de venta y botones de stock
		var controls_row := HBoxContainer.new()
		controls_row.add_theme_constant_override("separation", 8)

		var price_lbl := Label.new()
		price_lbl.text = "Sell $"

		var price_spin := SpinBox.new()
		price_spin.min_value = item["cost"]
		price_spin.max_value = 20000.0
		price_spin.step = 50.0
		price_spin.value = item["sell_price"]
		price_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price_spin.value_changed.connect(func(val): item["sell_price"] = val)

		var stock_lbl := Label.new()
		stock_lbl.name = "StockLabel"
		stock_lbl.text = "Qty: 0"
		stock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stock_lbl.custom_minimum_size = Vector2(56, 0)

		var minus_btn := Button.new()
		minus_btn.text = "-"
		minus_btn.custom_minimum_size = Vector2(40, 0)
		minus_btn.pressed.connect(func(): _change_stock(item, -1, stock_lbl))

		var plus_btn := Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(40, 0)
		plus_btn.pressed.connect(func(): _change_stock(item, 1, stock_lbl))

		controls_row.add_child(price_lbl)
		controls_row.add_child(price_spin)
		controls_row.add_child(minus_btn)
		controls_row.add_child(stock_lbl)
		controls_row.add_child(plus_btn)

		card_layout.add_child(name_lbl)
		card_layout.add_child(controls_row)
		card_panel.add_child(card_layout)
		product_list.add_child(card_panel)

func _change_stock(item: Dictionary, delta: int, stock_lbl: Label) -> void:
	if delta > 0 and GameState.capital >= item["cost"]:
		GameState.capital -= item["cost"]
		item["stock"] += 1
	elif delta < 0 and item["stock"] > 0:
		GameState.capital += item["cost"]
		item["stock"] -= 1

	stock_lbl.text = "Qty: %d" % item["stock"]
	_update_ui()

func _update_ui() -> void:
	capital_label.text = "Capital: $%.0f MXN" % GameState.capital
	var total_items := 0
	for item in catalog:
		total_items += item["stock"]
	continue_button.disabled = (total_items == 0)

func _on_continue_pressed() -> void:
	GameState.inventory.clear()
	for item in catalog:
		if item["stock"] > 0:
			GameState.inventory.append(item.duplicate())

	print("Inventory saved: ", GameState.inventory)
	print("Remaining Capital: $", GameState.capital)
	get_tree().change_scene_to_file("res://ui/PhoneHub.tscn")
	
