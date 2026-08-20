extends Node

# 行为识别器（Step 5）
# 只观察、不干预：后台把玩家的连续移动解读成五种行为之一，只 print 埋点。
# Step 5.5：正式埋点——每种行为确认时打印一条 [seeking.*]，无调试输出。

signal state_changed(new_state: String)

# --- 空间参数（与 world.gd / player.gd 保持一致）---
const CENTER_X := 3.0           # 台阶中轴
const EDGE_INNER := 1.6         # 主道半宽
const STEP_HALF := 3.0          # 台阶半宽（花带外缘）
const ON_STAIRS_Y := 1.0        # 在台阶上的高度判定

# --- 信号计算参数 ---
const VTREND_DEADZONE := 0.3    # 竖直趋势死区（单位/秒），低于此算「平」
const SAMPLE_WINDOW := 0.4      # 竖直趋势滑动窗口（秒）

# --- 判定阈值（进/出双阈值 = 迟滞，防止边界横跳）---
const GAZE_ENTER := 2.5         # 凑近鹿进入凝视
const GAZE_EXIT := 3.2          # 拉远到此才退出凝视
const OVERTAKE_ENTER := 3.0     # 领先鹿超过此距离进入超越
const OVERTAKE_EXIT := 2.0      # 领先距离缩到此以下才退出超越
const EDGE_ENTER := 0.15        # edge_factor 超过此进入花带（放弃）
const EDGE_EXIT := 0.05         # edge_factor 回落到此以下才退出

const HOLD_TIME := 0.7          # 候选态需连续维持这么久才「确认」并埋点

# 五种行为确认时的埋点文案（供后续 Trace/后端复用）
const MESSAGES := {
	"follow": "[seeking.follow] climbing behind the deer",
	"overtake": "[seeking.overtake] ahead of the deer, into the unknown",
	"gaze": "[seeking.gaze] drawing close",
	"abandon": "[seeking.abandon] stepping into the flowers",
	"observe": "[seeking.observe] watching from afar",
}

var _player: Node3D
var _deer: Node3D

# 竖直趋势采样
var _vtrend := 0                # +1 升 / 0 平 / -1 降
var _win_start_y := 0.0
var _sample_t := 0.0

# 当前行为（单一状态）
var _state := "idle"
var _candidate := "idle"        # 待确认的候选态
var _candidate_t := 0.0         # 候选态已连续维持的时长


func _ready():

	_player = get_tree().get_first_node_in_group("player") as Node3D
	_deer = get_tree().get_first_node_in_group("deer") as Node3D

	if _player != null:
		_win_start_y = _player.global_position.y

	print("[seeking.enter] a journey begins")


func _process(delta):

	# 引用兜底
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _deer == null:
		_deer = get_tree().get_first_node_in_group("deer") as Node3D
	if _player == null or _deer == null:
		return

	_update_vtrend(delta)

	# 每帧算候选态；需连续维持 HOLD_TIME 才确认切换（防抖）
	var raw := _classify()
	if raw == _state:
		# 和当前态一致 → 没有待切换的候选
		_candidate = _state
		_candidate_t = 0.0
	else:
		if raw == _candidate:
			_candidate_t += delta
		else:
			_candidate = raw
			_candidate_t = 0.0
		if _candidate_t >= HOLD_TIME:
			_state = _candidate
			_candidate_t = 0.0
			print(MESSAGES.get(_state, "[seeking.%s]" % _state))
			state_changed.emit(_state)


# 按优先级判定单一主导态（含迟滞：依当前态选进/出阈值）
func _classify() -> String:

	var pp: Vector3 = _player.global_position
	var dp: Vector3 = _deer.global_position

	var on_stairs: bool = pp.y > ON_STAIRS_Y
	var dist: float = pp.distance_to(dp)
	var ahead: bool = pp.z < dp.z
	var edge_factor: float = clamp((abs(pp.x - CENTER_X) - EDGE_INNER) / (STEP_HALF - EDGE_INNER), 0.0, 1.0)
	var leaving: bool = _player.get("leaving")

	# 迟滞：已处于某态时用「退出阈值」，否则用「进入阈值」——让状态更黏、不抖
	var gaze_dist: float = GAZE_EXIT if _state == "gaze" else GAZE_ENTER
	var overtake_dist: float = OVERTAKE_EXIT if _state == "overtake" else OVERTAKE_ENTER
	var edge_th: float = EDGE_EXIT if _state == "abandon" else EDGE_ENTER

	# 优先级：凝视 > 放弃 > 超越 > 跟随 > 观察（兜底）
	if dist < gaze_dist:
		return "gaze"
	if leaving or edge_factor > edge_th:
		return "abandon"
	if on_stairs and ahead and dist > overtake_dist:
		return "overtake"
	if on_stairs and _vtrend == 1 and not ahead:
		return "follow"
	return "observe"


# 竖直趋势：每 SAMPLE_WINDOW 秒比较一次高度变化率，带死区归一为 +1/0/-1
func _update_vtrend(delta):

	_sample_t += delta
	if _sample_t >= SAMPLE_WINDOW:
		var rate: float = (_player.global_position.y - _win_start_y) / _sample_t
		if rate > VTREND_DEADZONE:
			_vtrend = 1
		elif rate < -VTREND_DEADZONE:
			_vtrend = -1
		else:
			_vtrend = 0
		_win_start_y = _player.global_position.y
		_sample_t = 0.0
