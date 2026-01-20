extends Node

@export var sector_bounds_path: NodePath
@export var nav_region_path: NodePath
@export var debug_mmi_path: NodePath

func _ready() -> void:
	# Make sure paths are set in the Inspector
	if sector_bounds_path == NodePath("") or nav_region_path == NodePath(""):
		push_warning("Main: sector_bounds_path or nav_region_path not set")
		return

	# Defer so the scene tree is fully ready
	call_deferred("_init_ai")


func _init_ai() -> void:
	var bounds := get_node(sector_bounds_path) as Area3D
	var navreg := get_node(nav_region_path) as NavigationRegion3D

	if bounds == null or navreg == null:
		push_error("Main: Failed to get SectorBounds or NavigationRegion3D")
		return

	# Give NavigationRegion a frame to register its nav map
	await get_tree().process_frame

	# Build grid
	Sector.build_from_bounds(bounds, navreg, 20.0)

	# Notify Director (currently just logs, but hook is there)
	Director.init_for_current_map()

	# Optional debug visualization
	if debug_mmi_path != NodePath(""):
		var mmi := get_node(debug_mmi_path) as MultiMeshInstance3D
		if mmi:
			Sector.debug_fill_multimesh(mmi)
