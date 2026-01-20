extends CharacterBody3D

# --- Movement / nav params ---
@export var move_speed: float = 4.0
@export var turn_speed: float = 8.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

# --- Patrol params ---
@export var patrol_reached_radius: float = 1.5
@export var patrol_idle_time: float = 2.0

# --- Alert params ---
@export var alert_reached_radius: float = 2.0      # how close to search point counts as "arrived"
@export var alert_scan_time: float = 3.0           # how long to stand & scan at each point
@export var alert_scan_speed_deg: float = 30.0     # degrees/sec while scanning
@export var alert_max_time: float = 12.0           # total time to stay in ALERT
@export var alert_points_per_sector: int = 4       # how many extra points in that sector

# --- Local hearing params ---
@export var hear_radius_walk: float = 4.0
@export var hear_radius_sprint: float = 7.0
@export var hear_walk_speed_thresh: float = 1.5    # tweak to match your player walking speed
@export var hear_sprint_speed_thresh: float = 4.0  # tweak to match sprint speed

# --- Chase retarget params ---
@export var chase_retarget_interval: float = 0.2   # seconds
@export var chase_retarget_dist: float = 1.0       # meters

# --- State machine ---
enum State { PATROL, ALERT, CHASE }
var state: State = State.PATROL

# --- References ---
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var perception: Node = $Perception
@onready var label: Label3D = $Facing/Label3D
@onready var overhead: Node3D = $Facing/Overhead
@onready var sign_node: Label3D = $Facing/Overhead/Sign

var _last_sign_state: int = -1    # -1 = none, 1 = ALERT, 2 = CHASE


var player: Node3D
var last_known: Vector3 = Vector3.ZERO

# Patrol state
var patrol_target: Vector3 = Vector3.ZERO
var patrol_has_target: bool = false
var patrol_idle_timer: float = 0.0

# Alert search
var _alert_search_points: Array[Vector3] = []
var _alert_search_idx: int = 0
var _alert_total_timer: float = 0.0
var _alert_scanning: bool = false
var _alert_scan_timer: float = 0.0
var _high_priority_alert: bool = false  # true = “hard” alert (closer / radio from nearby)

# Nav bookkeeping
var _nav_ready: bool = false
var _last_target_set: Vector3 = Vector3.INF
var _last_set_time: float = 0.0


func _ready() -> void:
	add_to_group("guards")

	_hide_sign()
	player = get_tree().get_first_node_in_group("player")

	# Perception signals
	perception.player_seen.connect(_on_player_seen)
	perception.player_lost.connect(_on_player_lost)

	# Nav agent tuning
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.5
	agent.path_max_distance = 2.0
	agent.avoidance_enabled = false

	call_deferred("_await_nav_ready")


func _await_nav_ready() -> void:
	var rid: RID = agent.get_navigation_map()
	while not (rid.is_valid() and NavigationServer3D.map_get_iteration_id(rid) > 0):
		await get_tree().process_frame
		rid = agent.get_navigation_map()

	_nav_ready = true
	agent.target_position = global_transform.origin


func _physics_process(delta: float) -> void:
	if not _nav_ready:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		
	_update_signs()

	if label:
		label.text = ["PATROL", "ALERT", "CHASE"][state]


	# Local hearing: close-range “I hear you behind me”
	_local_hearing_check()

	_update_state(delta)
	_update_targets(delta)
	_move_along_path(delta)

	if label:
		label.text = ["PATROL", "ALERT", "CHASE"][state]


# --- Perception callbacks ----------------------------------------------------

func _on_player_seen(pos: Vector3) -> void:
	last_known = pos
	state = State.CHASE
	_alert_scanning = false
	_high_priority_alert = true
	# This sighting drives heat + alerts other guards
	Director.push_event("sighting", pos, 1.0)


func _on_player_lost(pos: Vector3) -> void:
	last_known = pos
	Director.push_event("lkp", pos, 0.7)


# Called by Director when another guard sights the player nearby
func on_external_player_sighted(pos: Vector3, immediate: bool) -> void:
	# If we see the player ourselves, ignore
	if perception.is_visible():
		return
	# Already chasing, ignore
	if state == State.CHASE:
		return

	_enter_alert_from(pos, immediate)



# --- Local hearing -----------------------------------------------------------

func _local_hearing_check() -> void:
	if player == null:
		return
	if perception.is_visible():
		return # vision already handles CHASE

	var pbody := player as CharacterBody3D
	if pbody == null:
		return

	var to_player: Vector3 = player.global_transform.origin - global_transform.origin
	to_player.y = 0.0
	var dist: float = to_player.length()
	var speed: float = pbody.velocity.length()

	# Sprinting: larger radius, higher speed threshold → hard alert
	if dist <= hear_radius_sprint and speed >= hear_sprint_speed_thresh:
		_enter_alert_from(player.global_transform.origin, true)
		return

	# Walking: smaller radius, lower speed threshold → soft alert (only from PATROL)
	if dist <= hear_radius_walk and speed >= hear_walk_speed_thresh and state == State.PATROL:
		_enter_alert_from(player.global_transform.origin, false)


# --- State machine -----------------------------------------------------------

func _update_state(delta: float) -> void:
	if perception.is_visible():
		state = State.CHASE
		return

	match state:
		State.CHASE:
			# Lost LOS → enter ALERT around last_known (high priority)
			_enter_alert_from(last_known, true)

		State.ALERT:
			# Transitions handled in _update_alert_target
			pass

		State.PATROL:
			pass


# --- Target selection per state ---------------------------------------------

func _update_targets(delta: float) -> void:
	match state:
		State.PATROL:
			_update_patrol_target(delta)

		State.ALERT:
			_update_alert_target(delta)

		State.CHASE:
			_update_chase_target(delta)


func _update_patrol_target(delta: float) -> void:
	if patrol_has_target and not agent.is_navigation_finished():
		return
		
	if patrol_has_target and agent.is_navigation_finished():
		patrol_idle_timer -= delta
		if patrol_idle_timer > 0.0:
			return
		patrol_has_target = false
	
	var p: Vector3 = Director.get_patrol_point()
	
	if p == Vector3.ZERO:
		var origin := global_transform.origin
		p = origin + Vector3(
			randf_range(-6.0, 6.0),
			0.0,
			randf_range(-6.0, 6.0)
		)
	var rid: RID = agent.get_navigation_map()
	if not rid.is_valid():
		return
	
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(rid, p)
	if closest == Vector3.INF:
		return
	
	patrol_target = closest
	patrol_has_target = true
	patrol_idle_timer = patrol_idle_time
	_set_agent_target(patrol_target)
	# If we already have a target and path, keep going
	#if patrol_has_target and not agent.is_navigation_finished():
		#return

	# Reached patrol target → idle a bit before new one
	#if patrol_has_target and agent.is_navigation_finished():
		#patrol_idle_timer -= delta
		#if patrol_idle_timer > 0.0:
			#return
		#patrol_has_target = false

	# Ask Director for a new patrol point on the sector grid
	#var p: Vector3 = Director.get_patrol_point()
	#if p == Vector3.ZERO:
		#var origin := global_transform.origin
		#p = origin + Vector3(
			#randf_range(-6.0, 6.0),
			#0.0,
			#randf_range(-6.0, 6.0)
	#	)
	#var rid: RID = agent.get_navigation_map()
	#if not rid.is_valid():
	#	return
	
	#var closest: Vector3 = NavigationServer3D.map_get_closest_point(rid, p)
	#if closest == Vector3.INF:
		#return
			
		

	#patrol_target = closest
	#patrol_has_target = true
	#patrol_idle_timer = patrol_idle_time
	#_set_agent_target(patrol_target)


func _enter_alert_from(pos: Vector3, immediate: bool) -> void:
	last_known = pos
	state = State.ALERT
	_high_priority_alert = immediate
	_start_alert_search_from(pos)


func _start_alert_search_from(pos: Vector3) -> void:
	var points_per_sector: int = alert_points_per_sector
	if _high_priority_alert:
		points_per_sector = int(round(alert_points_per_sector * 1.5))

	_alert_search_points = Director.get_alert_search_route(pos, points_per_sector)
	_alert_search_idx = 0
	_alert_total_timer = alert_max_time
	_alert_scanning = false
	_alert_scan_timer = 0.0


func _update_alert_target(delta: float) -> void:
	# If we see the player again, CHASE will take over
	if perception.is_visible():
		return

	_alert_total_timer -= delta
	if _alert_total_timer <= 0.0:
		_alert_scanning = false
		state = State.PATROL
		patrol_has_target = false
		return

	if _alert_search_points.is_empty():
		state = State.PATROL
		patrol_has_target = false
		return

	# Currently scanning this point
	if _alert_scanning:
		_alert_scan_timer -= delta
		if _alert_scan_timer <= 0.0:
			_alert_scanning = false
			_alert_search_idx += 1
			if _alert_search_idx >= _alert_search_points.size():
				state = State.PATROL
				patrol_has_target = false
		return

	# Move toward current search point
	var target: Vector3 = _alert_search_points[_alert_search_idx]
	var to_target: Vector3 = target - global_transform.origin
	to_target.y = 0.0

	if to_target.length() > alert_reached_radius:
		_set_agent_target(target)
	else:
		# Arrived → scan here
		_alert_scanning = true
		_alert_scan_timer = alert_scan_time
		_set_agent_target(global_transform.origin)


func _update_chase_target(delta: float) -> void:
	if player == null:
		return

	var p: Vector3 = player.global_transform.origin
	var now: float = Time.get_unix_time_from_system()

	var need_time: bool = (now - _last_set_time) >= chase_retarget_interval
	var need_dist: bool = (_last_target_set == Vector3.INF) or (p.distance_to(_last_target_set) >= chase_retarget_dist)

	if need_time or need_dist:
		_set_agent_target(p)


func _set_agent_target(p: Vector3) -> void:
	_last_set_time = Time.get_unix_time_from_system()
	_last_target_set = p

	var rid: RID = agent.get_navigation_map()
	if not rid.is_valid():
		return

	var closest: Vector3 = NavigationServer3D.map_get_closest_point(rid, p)
	if closest == Vector3.INF:
		return

	if agent.target_position.distance_to(closest) > 0.1:
		agent.target_position = closest
		

func on_external_noise_heard(pos: Vector3, loud: bool) -> void:
	# If we see the player, ignore noise
	if perception.is_visible():
		return
	# If currently chasing, stick to that
	if state == State.CHASE:
		return

	# Treat loud noises (whistle, big landing) as high-priority alert,
	# quieter ones as softer alert
	_enter_alert_from(pos, loud)





# --- Movement along nav path + alert scanning --------------------------------

func _move_along_path(delta: float) -> void:
	var vel: Vector3 = velocity

	if agent.is_navigation_finished():
		if state == State.ALERT and _alert_scanning:
			rotation.y += deg_to_rad(alert_scan_speed_deg) * delta
			vel.x = lerp(vel.x, 0.0, 0.2)
			vel.z = lerp(vel.z, 0.0, 0.2)
		else:
			vel.x = lerp(vel.x, 0.0, 0.2)
			vel.z = lerp(vel.z, 0.0, 0.2)
	else:
		var next_pos: Vector3 = agent.get_next_path_position()
		var to_next: Vector3 = next_pos - global_transform.origin
		to_next.y = 0.0
		var dist2: float = to_next.length_squared()

		if dist2 > 0.04: # ~0.2m
			var dist: float = sqrt(dist2)
			var dir: Vector3 = to_next / dist

			var speed_mul: float = 1.0
			if state == State.ALERT and _high_priority_alert:
				speed_mul = 1.15  # slightly more aggressive alert

			vel.x = dir.x * move_speed * speed_mul
			vel.z = dir.z * move_speed * speed_mul

			var target_yaw: float = atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
		else:
			vel.x = lerp(vel.x, 0.0, 0.2)
			vel.z = lerp(vel.z, 0.0, 0.2)

	# Gravity
	if not is_on_floor():
		vel.y -= gravity * delta
	else:
		if vel.y > 0.0:
			vel.y = 0.0
		vel.y -= gravity * delta * 0.1

	velocity = vel
	move_and_slide()



func _ensure_patrol_target(delta: float) -> void:
	# Already have a target and not there yet -> keep it
	if patrol_has_target and global_transform.origin.distance_to(patrol_target) > patrol_reached_radius:
		return

	# Reached target: idle a bit, then pick a new sector
	if patrol_has_target:
		patrol_idle_timer -= delta
		if patrol_idle_timer > 0.0:
			return
		patrol_has_target = false

	# Ask the Director singleton (autoload) for a new patrol point
	if not Engine.has_singleton("Director"):
	
		return

	var p: Vector3 = Director.get_patrol_point()
	if p == Vector3.ZERO:
		print("Guard: Director.get_patrol_point() returned ZERO - no patrol sectors/points?")
		return

	patrol_target = p
	patrol_has_target = true
	patrol_idle_timer = patrol_idle_time
	print("Guard: new patrol target from Director = ", p)
	
func _update_signs() -> void:
	if sign_node == null:
		return

	match state:
		State.PATROL:
			_hide_sign()

		State.ALERT:
			if _last_sign_state != State.ALERT:
				_show_sign("?", Color(1.0, 0.9, 0.2)) # soft yellow
				_last_sign_state = State.ALERT

		State.CHASE:
			if _last_sign_state != State.CHASE:
				_show_sign("!", Color(1.0, 0.25, 0.25)) # red
				_last_sign_state = State.CHASE


func _show_sign(txt: String, col: Color) -> void:
	sign_node.text = txt
	sign_node.modulate = col
	sign_node.visible = true

	# Optional tiny “pop” so it feels snappy:
	if overhead:
		overhead.scale = Vector3.ONE * 0.7
		var tw := create_tween()
		tw.tween_property(overhead, "scale", Vector3.ONE, 0.15)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_sign() -> void:
	if sign_node == null:
		return
	sign_node.visible = false
	sign_node.modulate.a = 1.0
	if overhead:
		overhead.scale = Vector3.ONE
	_last_sign_state = -1


func _on_vision_cone_3d_body_hidden(body: Node3D) -> void:
	pass # Replace with function body.


func _on_vision_cone_3d_body_sighted(body: Node3D) -> void:
	pass # Replace with function body.
