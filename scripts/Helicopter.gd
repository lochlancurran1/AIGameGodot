extends Node3D

signal player_spotted(player_position: Vector3)

@export var speed: float = 10.0
@export var rotation_speed: float = 0.7
@export var use_random_patrol: bool = true
@export var patrol_points: Array[NodePath] = []

@export var min_x: float = -50.0
@export var max_x: float = 50.0
@export var min_z: float = -50.0
@export var max_z: float = 50.0
@export var flight_height: float = 40.0

@export var forward_offset_degrees: float = 180.0

@export var prop_spin_speed: float = 25.0   
var prop_holder: Node3D                     

@export var detector_pivot_path: NodePath
var detector_pivot: Node3D
var raycast: RayCast3D
var player: Node3D

var alert_sound: AudioStreamPlayer3D

var rng := RandomNumberGenerator.new()
var random_target := Vector3.ZERO

func _ready() -> void:
	rng.randomize()

	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("No player found in group 'player'!")

	prop_holder = get_node_or_null("prop_holder")
	if prop_holder == null:
		push_warning(" prop_holder node not found! Propeller will not spin.")

	if detector_pivot_path != NodePath(""):
		detector_pivot = get_node_or_null(detector_pivot_path)
		if detector_pivot:
			raycast = detector_pivot.get_node_or_null("RayCast3D")
			if raycast == null:
				push_warning("DetectorPivot has no RayCast3D child!")
		else:
			push_warning("DetectorPivot path assigned but node not found!")

	alert_sound = get_node_or_null("HelicopterSound")
	if alert_sound == null:
		push_warning("No HelicopterSound found!")

	if use_random_patrol:
		_pick_new_random_target()

	set_physics_process(true)

func _pick_new_random_target() -> void:
	random_target = Vector3(
		rng.randf_range(min_x, max_x),
		flight_height,
		rng.randf_range(min_z, max_z)
	)

func _move_random(delta: float) -> void:
	var dir := random_target - global_position
	var dist := dir.length()

	if dist > 0.2:
		dir = dir.normalized()
		global_position += dir * speed * delta

		var flat := Vector3(dir.x, 0, dir.z)
		if flat.length() > 0.001:
			var target_yaw := atan2(flat.x, flat.z)

			rotation.y = lerp_angle(
				rotation.y,
				target_yaw + deg_to_rad(forward_offset_degrees),
				rotation_speed * delta
			)
	else:
		_pick_new_random_target()

func _rotate_propeller(delta: float) -> void:
	if prop_holder:
		prop_holder.rotate_y(prop_spin_speed * delta)

func _physics_process(delta: float) -> void:
	if use_random_patrol:
		_move_random(delta)

	_rotate_propeller(delta)    
	_raycast_detect_player()

func _raycast_detect_player() -> void:
	if raycast == null:
		return

	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider == player:
			print("Helicopter raycast sees player at:", player.global_position)
			_play_alert_sound()
			emit_signal("player_spotted", player.global_position)

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("Helicopter spotlight detected the player!")
		_play_alert_sound()

		var bb = get_node("/root/Blackboard")
		bb.add_noise(body.global_position, 100.0, 5.0)

		emit_signal("player_spotted", body.global_position)

func _on_detection_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("Player left the helicopter spotlight.")

func _play_alert_sound():
	if alert_sound and not alert_sound.playing:
		alert_sound.play()
