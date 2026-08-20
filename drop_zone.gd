extends Control

# 步骤 7-1/7-2：DropZone
# 挂在 EndingUI/DropZone Control 上，z_index 低于工具层。
# connection.gd 通过 set_connection() 绑定回调目标。

var _connection:    Node3D = null   # connection.gd 节点引用
var _confirmed:     bool   = false  # 防止重复触发
var _hovering_tool: String = ""     # 步骤 7-3：当前悬停的 tool_id


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP   # 必须能接收拖放事件


func set_connection(node: Node3D) -> void:
	_connection = node


# ── Godot 拖放三件套 ─────────────────────────────────────────────

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _confirmed:
		return false
	if not (data is String and data in ["frame", "water", "scissors"]):
		return false
	# 步骤 7-3：悬停工具变化时通知 connection 切换预览
	if data != _hovering_tool:
		_hovering_tool = data
		if _connection != null:
			_connection.start_preview(data)
	return true


func _notification(what: int) -> void:
	# 拖拽操作结束（松手或取消）时清除预览
	if what == NOTIFICATION_DRAG_END:
		if _hovering_tool != "":
			_hovering_tool = ""
			if _connection != null:
				_connection.clear_preview()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _confirmed:
		return
	_confirmed    = true
	mouse_filter  = MOUSE_FILTER_IGNORE   # 立即禁止后续拖放
	print("[dropzone] confirmed: ", data)
	if _connection != null:
		_connection.on_ending_confirmed(data)
