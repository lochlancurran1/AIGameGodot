extends Node

var route: Array[Vector3] = []
var idx := 0
var dwell := 2.5
var _last_task_time := 0.0

func is_busy() -> bool:
	return route.size() > 0 and idx < route.size()

func current_target():
	if is_busy():
		return route[idx]
	return null

func tick(delta: float, my_pos: Vector3) -> void:
	if not is_busy():
		return
	if my_pos.distance_to(route[idx]) < 1.5:
		if Time.get_unix_time_from_system() - _last_task_time >= dwell:
			_last_task_time = Time.get_unix_time_from_system()
			idx += 1
			if idx >= route.size():
				clear()

func set_sector_route(points: Array[Vector3]) -> void:
	route = points.duplicate()
	idx = 0
	_last_task_time = Time.get_unix_time_from_system()

func set_point_task(pos: Vector3, dwell_sec: float = 3.0) -> void:
	route = [pos]
	idx = 0
	dwell = dwell_sec
	_last_task_time = Time.get_unix_time_from_system()

func clear() -> void:
	route.clear()
	idx = 0

func get_last_task_time() -> float:
	return _last_task_time
