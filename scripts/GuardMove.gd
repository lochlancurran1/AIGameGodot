extends Node
class_name GuardMove

@export var move_speed: float = 3.0
@export var turn_speed: float = 8.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var floor_snap: float = 1.0
@export var max_slope_deg: float = 50.0

@export var chase_retarget_interval: float = 0.20
@export var chase_retarget_dist: float = 1.0
@export var target_hysteresis: float = 0.75

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var body: CharacterBody3D = get_parent() as CharacterBody3D

var _nav_ready: bool = false
var _last_target_set: Vector3 = Vector3.INF
var _last_set_time: float = 0.0
var _last_motion: Vector3 = Vector3.FORWARD


func _ready() -> void:
	body.floor_snap_length = floor_snap
	body.floor_max_angle = deg_to_rad(max_slope_deg)

	agent.path_max_distance = 2.0
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.5
	agent.avoidance_enabled = false

	# NEW: start facing where the guard is actually looking
	_last_motion = -body.global_transform.basis.z

	call_deferred("_await_nav_ready")



func _await_nav_ready() -> void:
	var rid := agent.get_navigation_map()
	while not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		await get_tree().process_frame
		rid = agent.get_navigation_map()
	_nav_ready = true


func ready_for_nav() -> bool:
	return _nav_ready


func is_navigation_finished() -> bool:
	return agent.is_navigation_finished()


func set_target(p: Vector3) -> void:
	if not _nav_ready:
		return

	if _last_target_set != Vector3.INF:
		var dt := Time.get_unix_time_from_system() - _last_set_time
		if p.distance_to(_last_target_set) < target_hysteresis and dt < 0.15:
			return

	_last_set_time = Time.get_unix_time_from_system()
	_last_target_set = _closest_point_on_nav(p)
	if _last_target_set == Vector3.INF:
		return

	if agent.target_position.distance_to(_last_target_set) > 0.1:
		agent.target_position = _last_target_set


func get_random_nav_point(radius: float = 16.0) -> Vector3:
	var rid := agent.get_navigation_map()
	if not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		return body.global_transform.origin

	var origin := body.global_transform.origin
	var candidate := origin + Vector3(
		randf_range(-1, 1),
		0,
		randf_range(-1, 1)
	).normalized() * randf_range(4.0, radius)

	var p := NavigationServer3D.map_get_closest_point(rid, candidate)
	return p if p != Vector3.INF else origin


func tick(delta: float, state: int, player: Node3D) -> void:
	if not _nav_ready:
		return

	# CHASE – re-target toward player with a cadence, like before.
	if state == 2 and player:
		var now := Time.get_unix_time_from_system()
		var need_time := (now - _last_set_time) >= chase_retarget_interval
		var need_dist := (_last_target_set == Vector3.INF) \
			or (player.global_transform.origin.distance_to(_last_target_set) >= chase_retarget_dist)

		if need_time or need_dist:
			set_target(player.global_transform.origin)

	# Movement along nav path
	if agent.is_navigation_finished():
		# Ease to stop at the end of a path (reduces "orbiting" a waypoint).
		body.velocity.x = lerpf(body.velocity.x, 0.0, 0.25)
		body.velocity.z = lerpf(body.velocity.z, 0.0, 0.25)
	else:
		var next_pos := agent.get_next_path_position()
		var to_next := next_pos - body.global_transform.origin
		to_next.y = 0.0

		var dist_to_next := to_next.length()

		if dist_to_next > 0.05:
			var dir := to_next.normalized()
			var speed := move_speed

			# Slow down a bit as we approach the corner / waypoint to kill jitter.
			if dist_to_next < 0.6:
				speed *= dist_to_next / 0.6

			body.velocity.x = dir.x * speed
			body.velocity.z = dir.z * speed
			_last_motion = dir
		else:
			body.velocity.x = lerpf(body.velocity.x, 0.0, 0.2)
			body.velocity.z = lerpf(body.velocity.z, 0.0, 0.2)

	# Gravity / floor
	if not body.is_on_floor():
		body.velocity.y -= gravity * delta
	else:
		if body.velocity.y > 0.0:
			body.velocity.y = 0.0
		body.velocity.y -= gravity * delta * 0.1

	body.move_and_slide()

	# Facing: smooth, and in CHASE bias toward the player's actual position.
		# --- Facing: just look where we are moving (simple & stable) ---
	var face := _last_motion

	# Fallback if we somehow haven't moved yet
	if face.length() < 0.001:
		face = -body.global_transform.basis.z

	face.y = 0.0

	if face.length() > 0.001:
		var target_yaw := atan2(-face.x, -face.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, turn_speed * delta)



func _closest_point_on_nav(p: Vector3) -> Vector3:
	var rid := agent.get_navigation_map()
	if not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		return Vector3.INF
	return NavigationServer3D.map_get_closest_point(rid, p)
