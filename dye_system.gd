extends Node

# DyeSystem — 全身整体变色系统（兜底方案：整个角色作为单一对象处理）
# 供四个 Eros 结局统一调用，外部通过 init(character) 注入角色节点

var base_color   := Color.WHITE
var target_color := Color(0.55, 0.1, 0.15)   # 绛红，Drift / Awake 共用
var is_frozen    := false

var _character: Node3D
var _tween: Tween
var _current_color := Color.WHITE


func init(character: Node3D) -> void:
	_character = character


# 按 t（0~1）插值到绛红，0.4s 过渡，用于饮酒逐步染色
func set_dye(t: float) -> void:
	if is_frozen:
		return
	t = clamp(t, 0.0, 1.0)
	_animate_to(base_color.lerp(target_color, t), 0.4)


# 直接指定目标色，1.5s 过渡，用于停泊（暖白）/ 远航（雾青灰）结局
func set_dye_instant(color: Color) -> void:
	if is_frozen:
		return
	_animate_to(color, 1.5)


# Awake 结局：冻结当前染色，之后所有调用无效
func freeze() -> void:
	is_frozen = true
	if _tween:
		_tween.kill()


func _animate_to(color: Color, duration: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(
		func(c: Color): _apply_color(c),
		_current_color, color, duration
	)


func _apply_color(c: Color) -> void:
	_current_color = c
	if _character == null:
		return
	for mesh in _character.find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh.set_surface_override_material(0, mat)
		mat.albedo_color = c
