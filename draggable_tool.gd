extends Control

# 步骤 7-1：可拖拽工具
# 挂在 ToolFrame / ToolWater / ToolScissors 三个 Control 上。
# connection.gd 在 _create_ending_ui() 中通过 set_script() 附加，
# 并在 STILL 阶段工具淡入完成后将 mouse_filter 改为 STOP 启用交互。

@export var tool_id: String = ""   # "frame" / "water" / "scissors"

var _origin_pos: Vector2 = Vector2.ZERO
var _confirmed:  bool    = false   # 步骤 7-2 由 connection 置 true，阻止归位


func _ready() -> void:
	# 记录初始位置作为归位基准（add_child 前 position 已设置）
	_origin_pos  = position
	# WALKING 阶段禁止交互；STILL 工具淡入完成后由 connection 改为 STOP
	mouse_filter = MOUSE_FILTER_IGNORE


func _get_drag_data(_at_position: Vector2) -> Variant:
	if tool_id.is_empty():
		return null
	set_drag_preview(_make_preview())
	return tool_id


# 复制自身作为跟手预览，去除脚本避免 _ready 重复触发
func _make_preview() -> Control:
	var copy := duplicate() as Control
	copy.set_script(null)
	copy.modulate.a   = 0.75
	copy.mouse_filter = MOUSE_FILTER_IGNORE
	return copy


# 步骤 7-2 调用：标记已确认，阻止松手归位
func confirm() -> void:
	_confirmed = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _confirmed:
		_return_to_origin()


func _return_to_origin() -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "position", _origin_pos, 0.4)
