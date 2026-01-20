extends Node

@export var cone_path: NodePath = ^"../Facing/VisionCone3D"

signal player_seen(pos: Vector3)   # fired once when first seen
signal player_lost(pos: Vector3)   # fired once when fully lost

@onready var cone: Node3D = get_node_or_null(cone_path)

var _visible: bool = false
var _last_known: Vector3 = Vector3.ZERO


func _ready() -> void:
	if is_instance_valid(cone):
		# VisionCone3D addon – make sure it’s actually running
		cone.monitoring = true

		# These are the standard VisionCone3D signals
		if cone.has_signal("body_sighted"):
			cone.connect("body_sighted", Callable(self, "_on_cone_sighted"))
		if cone.has_signal("body_hidden"):
			cone.connect("body_hidden", Callable(self, "_on_cone_hidden"))

	print("[Perception] ready. cone =", cone)


func _on_cone_sighted(body: Node3D) -> void:
	if body.is_in_group("player"):
		_last_known = body.global_transform.origin
		if not _visible:
			_visible = true
			player_seen.emit(_last_known)
			print("[Perception] SEEN at ", _last_known)


func _on_cone_hidden(body: Node3D) -> void:
	if body.is_in_group("player"):
		if _visible:
			_visible = false
			player_lost.emit(_last_known)
			print("[Perception] LOST at ", _last_known)


func is_visible() -> bool:
	return _visible


func last_known() -> Vector3:
	return _last_known
