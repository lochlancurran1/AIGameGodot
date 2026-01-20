# player_move.gd — Simple, stable FP controller for terrain (Godot 4.x)
extends CharacterBody3D

# --- Look ---
@export var mouse_sens: float = 0.12
@export_range(-89.0, 89.0) var pitch_min: float = -85.0
@export_range(-89.0, 89.0) var pitch_max: float = 85.0
@export var eye_height: float = 1.65

@onready var yaw: Node3D = $Yaw
@onready var pitch: Node3D = $Yaw/Pitch
@onready var cam: Camera3D = $Yaw/Pitch/Camera3D

# --- Movement (simple, consistent) ---
@export var walk_speed: float = 6.5
@export var sprint_speed: float = 10.0           # walk speed
@export var accel: float = 30.0            # how fast we reach target speed
@export var decel: float = 40.0 

@export var crouch_speed: float = 3.0
@export var crouch_eye_height: float = 1.0
@export var crouch_lerp: float = 10.0           # how fast we slow when no input

# --- Jump / gravity ---
@export var gravity: float = 24.0
@export var jump_speed: float = 7.8
@export var jump_snap_block_time: float = 0.08   # briefly disable snap after jump

# --- Terrain handling ---
@export var ground_snap_distance: float = 0.35   # stick to ground on slopes/steps
@export var step_max_height: float = 0.4
@export var floor_max_angle_deg: float = 46.0    # max walkable slope

@export var max_health: int = 100
var health: int = max_health

var _snap_block: float = 0.0  # timer to prevent snap immediately after jump
var _is_crouching: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# CharacterBody3D built-ins for stable terrain walking
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(floor_max_angle_deg)
	floor_snap_length = ground_snap_distance
	max_slides = 6
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	set_safe_margin(step_max_height * 0.25)

	# Camera rig
	pitch.position = Vector3(0.0, eye_height, 0.0)  # pivot at eye height
	cam.near = 0.1
	cam.fov = 74.0

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw.rotate_y(deg_to_rad(-e.relative.x * mouse_sens))
		pitch.rotate_x(deg_to_rad(-e.relative.y * mouse_sens))
		var rot := pitch.rotation_degrees
		rot.x = clamp(rot.x, pitch_min, pitch_max)
		pitch.rotation_degrees = rot
	if e.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	_snap_block = max(0.0, _snap_block - delta)

	if Input.is_action_just_pressed("crouch"):
		_is_crouching = not _is_crouching

	# ---- Input (W forward) ----
	var input_vec := Input.get_vector("move_left","move_right","move_back","move_forward")
	var forward: Vector3 = -yaw.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = yaw.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var desired_dir: Vector3 = (right * input_vec.x + forward * input_vec.y)
	if desired_dir.length() > 0.001:
		desired_dir = desired_dir.normalized()
		
	var crouching := _is_crouching
	var target_eye := crouch_eye_height if crouching else eye_height
	var p := pitch.position
	p.y = lerp(p.y, target_eye, crouch_lerp * delta)
	pitch.position = p

	# ---- Planar velocity (simple accel/decel toward desired) ----
	var v: Vector3 = velocity
	var v_planar: Vector3 = Vector3(v.x, 0.0, v.z)
	
	var sprinting := Input.is_action_pressed("sprint") and input_vec.y > 0.0 and not crouching
	if sprinting:
		#print("SPRINTING")
		pass
		
	var current_speed: float
	if crouching:
		current_speed = crouch_speed
	elif sprinting:
		current_speed = sprint_speed 
	else:
		current_speed = walk_speed
	
	var target_planar: Vector3 = desired_dir * current_speed

	var gain: float = accel if desired_dir != Vector3.ZERO else decel
	if sprinting and desired_dir != Vector3.ZERO:
		gain *= 1.2
	
	v_planar = v_planar.move_toward(target_planar, gain * delta)

	# Slide along floor normal to avoid pushing into ground on slopes
	if is_on_floor():
		v_planar = v_planar.slide(get_floor_normal())

	# Kill tiny residual drift
	if v_planar.length() < 0.01 and desired_dir == Vector3.ZERO:
		v_planar = Vector3.ZERO

	# ---- Vertical: gravity + jump ----
	if not is_on_floor():
		v.y -= gravity * delta
	else:
		# optional small damping when stepping down to reduce triangle bumps
		if v.y < 0.0:
			v.y = 0.0

	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouching:
		v.y = jump_speed
		_snap_block = jump_snap_block_time

	# ---- Apply & move ----
	velocity.x = v_planar.x
	velocity.z = v_planar.z
	velocity.y = v.y

	# Snap stronger on steeper slopes for smoother downhill
	if is_on_floor() and _snap_block <= 0.0:
		var n := get_floor_normal()
		var slope := acos(clamp(n.y, -1.0, 1.0))
		floor_snap_length = lerp(
			ground_snap_distance,
			ground_snap_distance * 1.6,
			clamp(slope / deg_to_rad(35.0), 0.0, 1.0)
		)
	else:
		# briefly disable snap right after jumping
		floor_snap_length = 0.0 if _snap_block > 0.0 else ground_snap_distance

	set_safe_margin(step_max_height * 0.4)
	move_and_slide()

	# ---- Blackboard tick: update & expire alerts ----
	if Engine.has_singleton("Blackboard"):
		Blackboard.tick(delta)
		
var _acc := 0.0
func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 1.0:
		#Director.tick_dispatch(_acc)
		_acc = 0.0
		
func apply_damage(amount: int) -> void:
	if health <= 0:
		get_tree().quit()
		return # already dead
		
	health = max(health - amount, 0)
	print("Player health:", health, "/", max_health)
	
	if health == 0:
		print("PLAYER DIED")
		get_tree().quit()
