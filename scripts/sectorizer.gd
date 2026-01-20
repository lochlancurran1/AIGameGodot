# res://Systems/Sectorizer.gd
extends Node

# Tunables
@export var cell_size: float = 20.0          # meters between sector centers
@export var accept_dist: float = 20.0        # max distance to nav to accept a sector

# Grid state
var _origin: Vector3 = Vector3.ZERO
var _nx: int = 0
var _nz: int = 0
var _sectors: Array = []        # each: {id, center, heat, cooldown_until, walkable, is_connector, i, j}
var _nav_map: RID

func _cell_index(ii: int, jj: int) -> int:
	if ii < 0 or jj < 0 or ii >= _nx or jj >= _nz:
		return -1
	return jj * _nx + ii


# Build from an axis-aligned Box 'SectorBounds' and a NavigationRegion3D in the scene
func build_from_bounds(bounds: Area3D, nav_region: NavigationRegion3D, new_cell_size: float = -1.0) -> void:
	if is_instance_valid(bounds) == false or is_instance_valid(nav_region) == false:
		push_error("Sectorizer.build_from_bounds: missing nodes")
		return
	if new_cell_size > 0.0:
		cell_size = new_cell_size

	_nav_map = nav_region.get_navigation_map()
	if not _nav_map.is_valid():
		push_error("Sectorizer: Navigation map invalid")
		return

	# Axis-aligned AABB from the BoxShape (keep bounds unrotated)
	var shape := bounds.get_node_or_null("CollisionShape3D")
	if shape == null or shape.shape == null or not (shape.shape is BoxShape3D):
		push_error("Sectorizer: SectorBounds must have a BoxShape3D")
		return
	var ext: Vector3 = (shape.shape as BoxShape3D).size * 0.5
	var c: Vector3 = bounds.global_transform.origin
	var minx = c.x - ext.x
	var maxx = c.x + ext.x
	var minz = c.z - ext.z
	var maxz = c.z + ext.z

	# Snap origin to grid
	_origin = Vector3(minx, c.y, minz)
	_nx = int(ceil((maxx - minx) / cell_size))
	_nz = int(ceil((maxz - minz) / cell_size))

	_sectors.clear()
	var id := 0
	for j in range(_nz):
		for i in range(_nx):
			var px = _origin.x + (i + 0.5) * cell_size
			var pz = _origin.z + (j + 0.5) * cell_size
			var probe := Vector3(px, c.y, pz)

			var nav_pt := NavigationServer3D.map_get_closest_point(_nav_map, probe)
			var walkable := nav_pt != Vector3.INF and nav_pt.distance_to(probe) <= accept_dist
			if walkable:
				probe.y = nav_pt.y

			var center_point := nav_pt if walkable else probe

			_sectors.append({
				"id": id,
				"center": center_point,
				"heat": 0.0,
				"cooldown_until": 0.0,
				"walkable": walkable,
				"is_connector": false,
				"i": i,
				"j": j,
			})
			id += 1

	print("Sectorizer: built %d cells (%d x %d)" % [_sectors.size(), _nx, _nz])


func sector_count() -> int:
	return _sectors.size()

func sector_id_at(pos: Vector3) -> int:
	var best := -1
	var best_d2 := INF
	for s in _sectors:
		if not s["walkable"]:
			continue
		var d2 = (s["center"] as Vector3).distance_squared_to(pos)
		if d2 < best_d2:
			best_d2 = d2
			best = int(s["id"])
	return best

func center(id: int) -> Vector3:
	return _sectors[id]["center"] as Vector3

func neighbors(id: int) -> PackedInt32Array:
	var s = _sectors[id]
	var i: int = int(s["i"])
	var j: int = int(s["j"])

	var ids := PackedInt32Array()

	var n = _cell_index(i + 1, j)
	if n != -1 and _sectors[n]["walkable"]:
		ids.append(n)

	n = _cell_index(i - 1, j)
	if n != -1 and _sectors[n]["walkable"]:
		ids.append(n)

	n = _cell_index(i, j + 1)
	if n != -1 and _sectors[n]["walkable"]:
		ids.append(n)

	n = _cell_index(i, j - 1)
	if n != -1 and _sectors[n]["walkable"]:
		ids.append(n)

	return ids

func random_point_in(id: int) -> Vector3:
	var c = _sectors[id]["center"] as Vector3
	var jx = randf_range(-0.45, 0.45) * cell_size
	var jz = randf_range(-0.45, 0.45) * cell_size
	var candidate = c + Vector3(jx, 0.0, jz)
	if _nav_map.is_valid():
		var p = NavigationServer3D.map_get_closest_point(_nav_map, candidate)
		if p != Vector3.INF:
			return p
	return candidate


# ------------------------------
# Heat API expected by Director
# ------------------------------

func id_at(p: Vector3) -> int:
	# Convenience alias used by Director
	return sector_id_at(p)

func center_of(sid: int) -> Vector3:
	return center(sid)

func heat_of(sid: int) -> float:
	if sid < 0 or sid >= _sectors.size():
		return 0.0
	return float(_sectors[sid]["heat"])

func set_cooldown(sid: int, seconds: float) -> void:
	if sid < 0 or sid >= _sectors.size():
		return
	_sectors[sid]["cooldown_until"] = Time.get_unix_time_from_system() + seconds

func bump_heat(sid: int, amount: float) -> void:
	if sid < 0 or sid >= _sectors.size():
		return
	var now := Time.get_unix_time_from_system()
	# ignore bumps during cooldown
	if now < float(_sectors[sid]["cooldown_until"]):
		return
	var h := float(_sectors[sid]["heat"])
	h = clampf(h + amount, 0.0, 10.0)
	_sectors[sid]["heat"] = h

func cool_all(rate_per_sec: float, dt: float) -> void:
	if rate_per_sec <= 0.0 or dt <= 0.0:
		return
	var dec := rate_per_sec * dt
	for k in _sectors.size():
		var h := float(_sectors[k]["heat"])
		if h > 0.0:
			h = max(0.0, h - dec)
			_sectors[k]["heat"] = h

func neighbors_of(sid: int) -> Array[int]:
	# Array form (sometimes nicer for loops)
	var out: Array[int] = []
	var packed := neighbors(sid)
	for idx in packed.size():
		out.append(packed[idx])
	return out
	
func debug_fill_multimesh(mmi: MultiMeshInstance3D) -> void:
	if mmi == null:
		return

	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mmi.multimesh = mm

	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true

	var count: int = _sectors.size()
	mm.instance_count = count

	for i in range(count):
		var s: Dictionary = _sectors[i]
		var center: Vector3 = s["center"] as Vector3
		var walkable: bool = bool(s["walkable"])

		var t: Transform3D = Transform3D.IDENTITY
		# Slightly above ground so it doesn't z-fight with terrain
		t.origin = center + Vector3(0.0, 0.2, 0.0)

		# Tile size relative to cell_size – tweak if too big/small
		var scale: float = cell_size * 0.45
		t.basis = Basis.IDENTITY.scaled(Vector3(scale, 0.3, scale))

		mm.set_instance_transform(i, t)

		var h: float = float(s["heat"])
		var col: Color = _heat_to_color(h, walkable)
		mm.set_instance_color(i, col)


func debug_update_multimesh(mmi: MultiMeshInstance3D) -> void:
	if mmi == null:
		return

	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		return

	var count: int = _sectors.size()
	if mm.instance_count != count:
		return

	for i in range(count):
		var s: Dictionary = _sectors[i]
		var h: float = float(s["heat"])
		var walkable: bool = bool(s["walkable"])
		var col: Color = _heat_to_color(h, walkable)
		mm.set_instance_color(i, col)


func _heat_to_color(heat: float, walkable: bool) -> Color:
	# heat is clamped in bump_heat to [0, 10], normalise to 0..1-ish
	var t: float = clamp(heat / 3.0, 0.0, 1.0)  # 0..~3 is your "interesting" range

	var cold: Color = Color(0.1, 0.1, 1, 0.5)   # dark blue-ish, transparent
	var hot: Color  = Color(1.0, 0.2, 0.2, 0.8)   # bright red, more opaque

	var base: Color = cold.lerp(hot, t)

	if not walkable:
		base = Color(0.2, 0.2, 0.2, 0.15)

	return base
