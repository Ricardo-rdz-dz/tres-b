extends ColorRect

var is_moving: bool = true
var speed: float = 1.8
var offset: float = 0.0
var bob_time: float = 0.0

func _process(delta: float) -> void:
	if is_moving:
		offset = fmod(offset + delta * speed, 1.0)
		bob_time += delta * 10.0
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return

	var horizon_y := h * 0.42

	# 1. Cielo y terreno (paleta limpia tipo Mini Motorways nocturno/atardecer)
	draw_rect(Rect2(0, 0, w, horizon_y), Color("#1e293b"))
	draw_rect(Rect2(0, horizon_y, w, h - horizon_y), Color("#263244"))

	# 2. Carretera en perspectiva (trapecio)
	var road_top_w := w * 0.14
	var road_bot_w := w * 0.78
	var road_poly := PackedVector2Array([
		Vector2(w * 0.5 - road_top_w * 0.5, horizon_y),
		Vector2(w * 0.5 + road_top_w * 0.5, horizon_y),
		Vector2(w * 0.5 + road_bot_w * 0.5, h),
		Vector2(w * 0.5 - road_bot_w * 0.5, h)
	])
	draw_colored_polygon(road_poly, Color("#334155"))

	# 3. Líneas centrales en movimiento con efecto de profundidad
	var dash_count := 6
	for i in range(dash_count):
		var t := fmod((float(i) / dash_count) + offset, 1.0)
		var t_next: float = clampf(t + 0.07, 0.0, 1.0)
		# Curva cuadrática para dar sensación real de velocidad al acercarse
		var y1 := lerpf(horizon_y, h, t * t)
		var y2 := lerpf(horizon_y, h, t_next * t_next)
		var width_line := lerpf(2.0, 10.0, t * t)
		draw_line(Vector2(w * 0.5, y1), Vector2(w * 0.5, y2), Color("#f59e0b"), width_line)

	# 4. Tablero minimalista y volante en la parte inferior
	var bob := sin(bob_time) * 1.5 if is_moving else 0.0
	var dash_y := h * 0.84 + bob
	draw_rect(Rect2(0, dash_y, w, h - dash_y + 10.0), Color("#0f172a"))

	# Volante (arco limpio del lado izquierdo)
	var wheel_center := Vector2(w * 0.25, h * 0.98 + bob)
	var wheel_radius: float = minf(w, h) * 0.22
	draw_arc(wheel_center, wheel_radius, PI, TAU, 32, Color("#1e293b"), 14.0, true)
	draw_arc(wheel_center, wheel_radius, PI, TAU, 32, Color("#475569"), 4.0, true)
