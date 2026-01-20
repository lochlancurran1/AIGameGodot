extends Node3D

@export var player_body: CharacterBody3D
@export var grass_audio: AudioStreamPlayer
@export var whistle_audio: AudioStreamPlayer
@export var sprint_audio: AudioStreamPlayer
@export var heartbeat_audio: AudioStreamPlayer

var _grass_step_timer: float = 0.0
var grass_sounds: Array[AudioStream] = []
var _was_on_floor: bool = false
var _sprint_heartbeat: float = 0.0
var whistle_sound: AudioStream
var sprint_sound: AudioStream
var heartbeat_sound: AudioStream

# For activity heat
var _activity_timer: float = 0.0
@export var activity_interval: float = 1.0  # seconds between heat pings


func _ready() -> void:
	grass_sounds = [
		load("res://assets/sounds/walking-on-grass-363353.mp3") as AudioStream
	]

	whistle_sound = load("res://assets/sounds/black-ops-prop-hunt-whistle.mp3") as AudioStream
	sprint_sound = load("res://assets/sounds/running-in-wet-grass-235969.mp3") as AudioStream
	heartbeat_sound = load("res://assets/sounds/heartbeat-297400.mp3") as AudioStream


func _physics_process(delta: float) -> void:
	if player_body == null:
		return

	var pos: Vector3 = player_body.global_transform.origin

	# --- Landing thump noise ---
	var on_floor: bool = player_body.is_on_floor()
	if (not _was_on_floor) and on_floor:
		_push_noise(0.8)
	_was_on_floor = on_floor

	var sprinting: bool = Input.is_action_pressed("sprint")

	# --- Sprinting noise + audio ---
	if sprinting:
		_sprint_heartbeat -= delta
		if _sprint_heartbeat <= 0.0:
			_push_noise(0.25)
			_sprint_heartbeat = 0.4
			print("Player sprinting")

		if sprint_audio and sprint_sound and not sprint_audio.playing:
			sprint_audio.stream = sprint_sound
			sprint_audio.play()

		if heartbeat_audio and heartbeat_sound and not heartbeat_audio.playing:
			heartbeat_audio.stream = heartbeat_sound
			heartbeat_audio.play()
	else:
		if sprint_audio and sprint_audio.playing:
			sprint_audio.stop()
		if heartbeat_audio and heartbeat_audio.playing:
			heartbeat_audio.stop()

	# --- Whistle: big, discrete noise + one-shot audio ---
	if Input.is_action_just_pressed("whistle"):
		_push_noise(1.0)
		print("Player whistled")
		if whistle_audio and whistle_sound:
			whistle_audio.stream = whistle_sound
			whistle_audio.play()

	# --- Footstep noise + grass sounds ---
	_grass_step_timer -= delta

	var vel: Vector3 = player_body.velocity
	vel.y = 0.0
	var speed: float = vel.length()

	if speed > 0.1 and _grass_step_timer <= 0.0:
		var step_interval: float = 0.30 if sprinting else 0.45
		_grass_step_timer = step_interval

		_push_noise(0.15)

		if grass_sounds.size() > 0 and grass_audio:
			grass_audio.stream = grass_sounds[randi() % grass_sounds.size()]
			grass_audio.play()

	# --- Natural activity heat (no tasks, just heat) ---
	_activity_timer -= delta
	if _activity_timer <= 0.0:
		if speed > 0.2:
			# Scale activity heat with speed, but clamp
			var w: float = clamp(speed * 0.02, 0.1, 0.6)
			Director.push_event("activity", pos, w)
		_activity_timer = activity_interval


func _push_noise(weight: float) -> void:
	if Engine.is_editor_hint():
		return

	Director.push_event("noise", player_body.global_transform.origin, weight)
	print("Noise event pushed at ", player_body.global_transform.origin, " weight=", weight)
