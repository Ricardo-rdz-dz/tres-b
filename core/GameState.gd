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
