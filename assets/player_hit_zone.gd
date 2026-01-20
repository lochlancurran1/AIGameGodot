extends Area3D

@export var damage_amount: int = 10
@export var damage_interval: float = 0.5

var _player: Node3D = null
@onready var damage_timer: Timer = $DamageTimer

func _ready() -> void:
	damage_timer.wait_time = damage_interval
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		damage_timer.start()
		print("Player entered guard arms")
		
	
func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		damage_timer.stop()
		print("Player left guard arms")
		
func _on_damage_timer_timeout() -> void:
	if _player and _player.has_method("apply_damage"):
		_player.apply_damage(damage_amount)
