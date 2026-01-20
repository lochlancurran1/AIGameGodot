extends CharacterBody3D

@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
@export var floor_snap: float = 1.0
@export var max_slope_deg: float = 50.0

@export var move_speed: float = 3.0
@export var fov: float = 120.0
@export var losRange: float = 20.0
@export var susDecay: float = 0.35
@export var susRise: float = 0.8
@export var losLoseGrace: float = 1.0
@export var turn_speed: float = 8.0
@export var wander_radius: float = 20.0
@export var wander_interval: float = 3.0
@export var lookahead_m: float = 2.5
@export var chase_turn_boost: float = 1.6
@export var susp_turn_boost: float = 1.2

var _nav_ok := false

var task_route: Array[Vector3] = []
var task_idx: int = 0
var _last_task_time: float = 0.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var facing: Node3D = $Facing
@onready var label: Label3D = $Facing/Label3D
@onready var los: RayCast3D = $Facing/RayCast3D

var patrol_points: Array[Vector3] = []
var idx := 0
var suspicion := 0.1
var lastKnown: Vector3 = Vector3.ZERO
var lostLosTimer: float
var searchTtl: float
var investigateTarget: Vector3 = Vector3.ZERO
var player: Node3D

enum State { PATROL, SUSPICIOUS, CHASE, SEARCH, WANDER }
var state := State.PATROL

var wander_timer := 0.0
var wander_target: Vector3
var player_in_cone: bool = false

func _ready() -> void:
	floor_snap_length = floor_snap
	floor_max_angle = deg_to_rad(max_slope_deg)
	add_to_group("guards")
	for c in get_children():
		if c is Marker3D and c.name.begins_with("WP"):
			patrol_points.append(c.global_transform.origin)
	if not patrol_points.is_empty():
		agent.target_position = patrol_points[0]
	else:
		state = State.WANDER
		wander_timer = 0.0
	agent.max_speed = move_speed
	agent.path_max_distance = 2.5
	label.text = "PATROL"
	player = get_tree().get_first_node_in_group("player")
	call_deferred("_wait_navmap")

func _physics_process(delta: float) -> void:
	if not _nav_ok:
		return

	_perceive(delta)
	_state_logic(delta)

	if player == null:
		player = get_tree().get_first_node_in_group("player")

	agent.velocity = Vector3(velocity.x, 0.0, velocity.z)

	match state:
		State.PATROL:
			if not patrol_points.is_empty() and agent.is_navigation_finished():
				idx = (idx + 1) % patrol_points.size()
				_set_agent_target_safely(patrol_points[idx])
		State.SUSPICIOUS:
			var tgt := Vector3.ZERO
			if investigateTarget != Vector3.ZERO:
				tgt = investigateTarget
			elif player:
				tgt = player.global_transform.origin
			if tgt != Vector3.ZERO:
				_set_agent_target_safely(tgt)
		State.CHASE:
			if player:
				_set_agent_target_safely(player.global_transform.origin)
		State.SEARCH:
			pass
		State.WANDER:
			wander_timer -= delta
			if wander_timer <= 0.0 or agent.is_navigation_finished():
				wander_target = get_random_nav_point()
				_set_agent_target_safely(wander_target)
				wander_timer = wander_interval

	if task_route.size() > 0:
		var tgt2 = task_route[task_idx]
		_set_agent_target_safely(tgt2)
		if global_transform.origin.distance_to(tgt2) < 1.5:
			if Time.get_unix_time_from_system() - _last_task_time >= 2.5:
				_last_task_time = Time.get_unix_time_from_system()
				task_idx += 1
				if task_idx >= task_route.size():
					task_route.clear()

	var next_pos = agent.get_next_path_position()
	var to_next = next_pos - global_transform.origin
	to_next.y = 0.0
	if to_next.length() > 0.05:
		var dir = to_next.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = lerpf(velocity.x, 0.0, 0.2)
		velocity.z = lerpf(velocity.z, 0.0, 0.2)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y > 0.0:
			velocity.y = 0.0
		velocity.y -= gravity * delta * 0.1

	move_and_slide()

	var cand := Vector3.ZERO
	if state == State.CHASE and player:
		cand = player.global_transform.origin - global_transform.origin
	if cand.length() < 0.01:
		var vel2d = Vector3(velocity.x, 0.0, velocity.z)
		if vel2d.length() > 0.05:
			cand = vel2d
	if cand.length() < 0.01:
		var np = agent.get_next_path_position()
		var to_np = np - global_transform.origin
		if to_np.length() > 0.01:
			var step = min(lookahead_m, to_np.length())
			cand = to_np.normalized() * step
	if cand.length() < 0.01:
		cand = agent.target_position - global_transform.origin
	if cand.length() < 0.01:
		cand = -facing.global_transform.basis.z
	cand.y = 0.0
	if cand.length() > 0.001:
		cand = cand.normalized()
		var target_yaw := atan2(-cand.x, -cand.z)
		var turn_mul := 1.0
		if state == State.CHASE:
			turn_mul = chase_turn_boost
		elif state == State.SUSPICIOUS:
			turn_mul = susp_turn_boost
		facing.rotation.y = lerp_angle(facing.rotation.y, target_yaw, (turn_speed * turn_mul) * delta)

	label.text = ["PATROL","SUSPICIOUS","CHASE","SEARCH","WANDER"][state] + "  S:" + str(snappedf(suspicion, 0.01))

func _perceive(delta):
	var seen := false
	if player:
		var to_p = player.global_transform.origin - global_transform.origin
		if to_p.length() <= losRange:
			var forward = -facing.global_transform.basis.z
			var to_dir = to_p.normalized()
			var ang_deg = rad_to_deg(acos(clampf(forward.dot(to_dir), -1.0, 1.0)))
			if ang_deg <= fov * 0.5:
				los.target_position = Vector3(0, 0, -losRange)
				los.force_raycast_update()
				seen = los.is_colliding() and los.get_collider() == player
	if seen:
		suspicion = clampf(suspicion + susRise * delta, 0.0, 1.0)
		lastKnown = player.global_transform.origin
		lostLosTimer = 0.0
	else:
		suspicion = clampf(suspicion - susDecay * delta, 0.0, 1.0)
		lostLosTimer += delta
	player_in_cone = seen
	for n in Blackboard.alerts:
		var d = global_transform.origin.distance_to(n["pos"])
		if d <= float(n["radius"]):
			var proximity = 1.0 - clampf(d / float(n["radius"]), 0.0, 1.0)
			suspicion = clampf(suspicion + 0.35 * proximity * delta, 0.0, 1.0)
			investigateTarget = n["pos"]
			if state == State.PATROL or state == State.WANDER:
				state = State.SUSPICIOUS
				_set_agent_target_safely(n["pos"])

func _state_logic(delta: float) -> void:
	match state:
		State.PATROL:
			if player_in_cone:
				state = State.CHASE
				suspicion = 1.0
			elif suspicion > 0.35:
				state = State.SUSPICIOUS
		State.SUSPICIOUS:
			if player_in_cone:
				state = State.CHASE; suspicion = 1.0
			elif suspicion > 0.8:
				state = State.CHASE; suspicion = 1.0
			elif suspicion > 0.7 and lostLosTimer < 0.5:
				state = State.CHASE
			elif suspicion <= 0.0:
				state = State.WANDER
		State.CHASE:
			if not player_in_cone and lostLosTimer > losLoseGrace:
				state = State.SEARCH
				searchTtl = 8.0
		State.SEARCH:
			searchTtl -= delta
			if player_in_cone:
				state = State.CHASE; suspicion = 1.0
			elif lostLosTimer < 0.2 and suspicion > 0.35:
				state = State.CHASE
			elif searchTtl <= 0.0:
				state = State.WANDER
		State.WANDER:
			if player_in_cone:
				state = State.CHASE; suspicion = 1.0
			elif suspicion > 0.35:
				state = State.SUSPICIOUS

func _wait_navmap() -> void:
	var rid := agent.get_navigation_map()
	while not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		await get_tree().process_frame
		rid = agent.get_navigation_map()
	_nav_ok = true

func _set_agent_target_safely(p: Vector3) -> void:
	var rid := agent.get_navigation_map()
	if not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		return
	p = NavigationServer3D.map_get_closest_point(rid, p)
	if agent.target_position.distance_to(p) > 0.75:
		agent.target_position = p

func get_random_nav_point() -> Vector3:
	var rid := agent.get_navigation_map()
	if not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		return global_transform.origin
	var origin := global_transform.origin
	var rand_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(5.0, wander_radius)
	var candidate := origin + rand_dir
	var p := NavigationServer3D.map_get_closest_point(rid, candidate)
	return p if p != Vector3.INF else origin

func _on_vision_cone_3d_body_sighted(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_cone = true

func _on_vision_cone_3d_body_hidden(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_cone = false

func is_busy() -> bool:
	return state == State.CHASE or state == State.SEARCH or task_route.size() > 0

func get_last_task_time() -> float:
	return _last_task_time

func set_task_investigate_sector(sid: int) -> void:
	task_route.clear()
	for k in range(5):
		var p = Sector.random_point_in(sid)
		if task_route.is_empty() or task_route.back().distance_to(p) > 5.0:
			task_route.append(p)
	task_idx = 0
	_last_task_time = Time.get_unix_time_from_system()
	if state == State.PATROL or state == State.WANDER:
		state = State.SUSPICIOUS

func set_task_investigate_point(pos: Vector3, dwell_sec: float = 3.0) -> void:
	task_route = [pos]
	task_idx = 0
	_last_task_time = Time.get_unix_time_from_system()
	if state == State.PATROL or state == State.WANDER:
		state = State.SUSPICIOUS

func clear_task_and_return_to_beat() -> void:
	task_route.clear()
