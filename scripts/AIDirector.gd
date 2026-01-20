extends Node
class_name AIDirector

@export var heat_decay_per_sec: float = 0.2   # how fast heat cools per second
@export var hot_threshold: float = 0.5        # min heat to be “interesting”

# Radii for spreading alerts from a sighting
@export var hard_alert_radius: float = 25.0
@export var soft_alert_radius: float = 60.0

# Noise broadcast settings
@export var noise_radius: float = 45.0              # how far a whistle/landing can pull guards
@export var noise_broadcast_min_weight: float = 0.5 # min noise weight to broadcast (0.5 = whistle/land, not footsteps)

# Optional global alert level (0..1)
var global_alert: float = 0.0
@export var alert_decay_per_sec: float = 0.1


func _ready() -> void:
	print("Director ready, Sector count at start: ", Sector.sector_count())


func _process(delta: float) -> void:
	# Cool all sectors each frame
	Sector.cool_all(heat_decay_per_sec, delta)
	# Decay global alert
	global_alert = max(0.0, global_alert - alert_decay_per_sec * delta)


# Global events: sighting, last-known, activity, noise, etc.
func push_event(kind: String, pos: Vector3, weight: float = 1.0) -> void:
	print("Director.push_event kind=", kind, " weight=", weight, " pos=", pos)

	var sid: int = Sector.id_at(pos)
	if sid == -1:
		print("Director: no sector for pos, ignoring.")
		return

	var base: float = 0.3
	match kind:
		"sighting":
			base = 1.0
		"lkp":
			base = 0.7
		"activity":
			base = 0.2
		"noise":
			base = 0.3
		_:
			base = 0.3

	Sector.bump_heat(sid, base * weight)

	if kind == "sighting":
		global_alert = min(1.0, global_alert + 0.5 * weight)
		_alert_nearby_guards_sighting(pos)
	elif kind == "noise":
		# Only broadcast sufficiently loud noises (e.g. whistle, heavy landing)
		if weight >= noise_broadcast_min_weight:
			_alert_nearby_guards_noise(pos, weight)
		else:
			print("Director: noise too quiet for broadcast (weight=", weight, ")")
	# activity / lkp just contribute to heat for patrol, no broadcast right now


# --- Sighting: drives hard/soft alert around the seeing guard ----------------

func _alert_nearby_guards_sighting(pos: Vector3) -> void:
	var guards: Array = get_tree().get_nodes_in_group("guards")
	print("Director: sighting broadcast, guards in group=", guards.size())

	for g in guards:
		if not (g is CharacterBody3D):
			continue

		var guard_body := g as CharacterBody3D
		var d: float = guard_body.global_transform.origin.distance_to(pos)

		if d <= hard_alert_radius:
			print("  -> hard alert to guard ", guard_body.name, " at distance ", d)
			if guard_body.has_method("on_external_player_sighted"):
				guard_body.on_external_player_sighted(pos, true)
		elif d <= soft_alert_radius:
			print("  -> soft alert to guard ", guard_body.name, " at distance ", d)
			if guard_body.has_method("on_external_player_sighted"):
				guard_body.on_external_player_sighted(pos, false)


# --- Noise: whistle / heavy landing etc. ------------------------------------

func _alert_nearby_guards_noise(pos: Vector3, weight: float) -> void:
	var guards: Array = get_tree().get_nodes_in_group("guards")
	print("Director: noise broadcast, guards in group=", guards.size(), " radius=", noise_radius)

	var loud: bool = weight >= 0.8   # 1.0 whistle / 0.8 landing considered “loud”

	for g in guards:
		if not (g is CharacterBody3D):
			continue

		var guard_body := g as CharacterBody3D
		var d: float = guard_body.global_transform.origin.distance_to(pos)
		if d <= noise_radius:
			print("  -> noise heard by guard ", guard_body.name, " at distance ", d, " loud=", loud)
			if guard_body.has_method("on_external_noise_heard"):
				guard_body.on_external_noise_heard(pos, loud)


func init_for_current_map() -> void:
	print("Director: map initialized with ", Sector.sector_count(), " sectors")


func _get_hottest_sector() -> int:
	var best_sid: int = -1
	var best_heat: float = 0.0
	var count: int = Sector.sector_count()

	for sid in range(count):
		var h: float = Sector.heat_of(sid)
		if h >= hot_threshold and h > best_heat:
			best_heat = h
			best_sid = sid

	return best_sid  # -1 if nothing hot


func get_patrol_point() -> Vector3:
	var sid: int = _get_hottest_sector()
	var count: int = Sector.sector_count()

	# No hot sector? pick a random walkable one.
	if sid == -1:
		if count <= 0:
			return Vector3.ZERO
		sid = randi() % count

	var p: Vector3 = Sector.random_point_in(sid)
	return p


func get_alert_search_route(last_known: Vector3, points_per_sector: int) -> Array[Vector3]:
	var route: Array[Vector3] = []

	var sid: int = Sector.id_at(last_known)
	if sid == -1:
		route.append(last_known)
		return route

	route.append(last_known)
	for i in range(points_per_sector):
		route.append(Sector.random_point_in(sid))

	return route
