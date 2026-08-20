extends Node

# 服装触发管理器
# 纯逻辑层：监听状态信号 → 计时 → 条件满足时发出 costume_triggered
# 不涉及任何视觉，每个事件只触发一次

signal costume_triggered(event_name: String)

const FOLLOW_DURATION    := 4.0
const OVERTAKE_DURATION  := 6.0
const OBSESSION_DURATION := 20.0

# 防重复标记
var _triggered := {
	"follow":    false,
	"gaze":      false,
	"overtake":  false,
	"abandon":   false,
	"obsession": false,
	# Connection 结局
	"connection_frame":    false,
	"connection_water":    false,
	"connection_scissors": false,
	# Eros 结局
	"eros_island": false,
	"eros_ship":   false,
	"eros_drift":  false,
	"eros_awake":  false,
	# Order 结局
	"order_path1": false,
	"order_path2": false,
	"order_path3": false,
	# Creation 配饰
	"creation_0": false,   # Promise
	"creation_1": false,   # Lemon
	"creation_2": false,   # 我心翱翔
	"creation_3": false,   # 大教堂时代
	# Constants 配饰
	"constants":  false,
}

var _current_state := ""
var _follow_t      := 0.0
var _overtake_t    := 0.0


func _process(delta: float) -> void:

	# Follow 计时
	if _current_state == "follow" and not _triggered["follow"]:
		_follow_t += delta
		if _follow_t >= FOLLOW_DURATION:
			_fire("follow")

	# Overtake / Obsession 共用计时器
	if _current_state == "overtake":
		if not _triggered["overtake"] or not _triggered["obsession"]:
			_overtake_t += delta
		if not _triggered["overtake"] and _overtake_t >= OVERTAKE_DURATION:
			_fire("overtake")
		if not _triggered["obsession"] and _overtake_t >= OBSESSION_DURATION:
			_fire("obsession")


# 由 world.gd 连接到 behavior.gd 的 state_changed 信号
func on_state_changed(new_state: String) -> void:

	_current_state = new_state

	# 离开 follow → 重置计时器
	if new_state != "follow":
		_follow_t = 0.0

	# 离开 overtake → 重置计时器
	if new_state != "overtake":
		_overtake_t = 0.0

	# gaze 由 glance_finished 信号触发，此处不处理


# 由 world.gd 连接到 deer.gd 的 glance_finished 信号
func on_glance_finished() -> void:
	if not _triggered["gaze"]:
		_fire("gaze")


# 由 world.gd 连接到自身的 player_fell 信号
func on_player_fell() -> void:

	if not _triggered["abandon"]:
		_fire("abandon")


func _fire(event_name: String) -> void:

	_triggered[event_name] = true
	print("[costume] triggered: ", event_name)
	costume_triggered.emit(event_name)


# 由 world.gd 连接到 connection.gd 的 ending_done 信号
func on_connection_ending(tool_id: String) -> void:
	var event := "connection_" + tool_id
	if not _triggered.get(event, false):
		_fire(event)


# 由 eros.gd 直接调用
func on_eros_ending(event_name: String) -> void:
	if not _triggered.get(event_name, false):
		_fire(event_name)


# 由 force_05_order.gd 直接调用
func on_order_ending(event_name: String) -> void:
	if not _triggered.get(event_name, false):
		_fire(event_name)


# 由 force_06_creation.gd 直接调用（song_idx = 0~3）
# costume_ui 中无对应 TEXTS，不触发白屏；仅让 wardrobe 显示配饰
func on_creation_ending(song_idx: int) -> void:
	var event := "creation_%d" % song_idx
	if not _triggered.get(event, false):
		_fire(event)


# 由 force_07_constants.gd 直接调用
func on_constants_ending() -> void:
	if not _triggered.get("constants", false):
		_fire("constants")
