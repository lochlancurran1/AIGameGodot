# ConcealmentArea.gd (attach to each Area3D)
extends Area3D
@export_range(0.0, 1.0) var factor: float = 0.6  # how strong the concealment is

func _ready() -> void:
	monitoring = true
	monitorable = true

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if "enter_concealment" in body:
			body.enter_concealment(factor)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		if "exit_concealment" in body:
			body.exit_concealment(factor)


func _on_area_entered(area: Area3D) -> void:
	pass # Replace with function body.


func _on_area_exited(area: Area3D) -> void:
	pass # Replace with function body.
