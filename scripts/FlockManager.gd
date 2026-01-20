extends Node

var flocks: Array = []
var reserved_positions: Array[Vector3] = []
var min_distance_between_targets: float = 30.0
var max_attempts := 20    # prevent infinite loops


func register_flock(flock):
	flocks.append(flock)


func request_valid_target(desired: Vector3) -> Vector3:
	var result := desired

	for i in range(max_attempts):
		var ok := true

		for other in reserved_positions:
			if result.distance_to(other) < min_distance_between_targets:
				ok = false
				break

		if ok:
			reserve_target(result)
			return result

		result.x += randf_range(-40, 40)
		result.z += randf_range(-40, 40)

	push_warning("⚠ Could not find fully unique target, using fallback.")
	reserve_target(result)
	return result


func reserve_target(pos: Vector3):
	reserved_positions.append(pos)


func release_target(pos: Vector3):
	reserved_positions.erase(pos)
