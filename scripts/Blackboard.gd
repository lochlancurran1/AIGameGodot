extends Node

var alerts : Array = []

func add_noise(pos: Vector3, radius: float, ttl: float) -> void:
	alerts.append({"pos": pos, "radius": radius, "ttl": ttl})

func add_bird_alert(pos: Vector3) -> void:
	add_noise(pos, 30, 5.0)   # radius 15, lasts 5 seconds
	print(".. Blackboard: Bird alert added at ", pos)

func tick(delta: float) -> void:
	for n in alerts:
		n["ttl"] -= delta
	alerts = alerts.filter(func(item): return item["ttl"] > 0.0)
