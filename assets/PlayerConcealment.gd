# PlayerConcealment.gd (attach to player root)
extends Node3D

var concealment_stack: int = 0
var concealment_factor: float = 0.0   # 0.0 = none, 1.0 = fully concealed
var _factors: Array[float] = []

func enter_concealment(f: float) -> void:
	_factors.append(f)
	concealment_stack += 1
	concealment_factor = _factors.max() if _factors.size() > 0 else 0.0

func exit_concealment(f: float) -> void:
	_factors.erase(f)
	concealment_stack = max(0, concealment_stack - 1)
	concealment_factor = _factors.max() if _factors.size() > 0 else 0.0
