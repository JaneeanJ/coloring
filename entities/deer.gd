extends CharacterBody3D

signal glance_finished   # 那一瞥动画结束时发出

# 鹿的规则：不加速、只沿台阶中轴一直向前
# 唯一的例外是「一生一次的那一瞥」——那一刻它会停下、看你，之后永远向前
const SPEED := 2.3              # 恒定水平速度，锁死不外露
const CLIMB_RATE := 0.6667      # 与台阶斜率一致：0.60 / 0.90
const PATH_X := 3.0             # 固定在台阶中轴

# 一生一次的一瞥：凑到很近触发，鹿停下、冻结玩家，久一点
const GLANCE_ENTER_DIST := 1.4          # 玩家凑到很近才触发
const GLANCE_DURATION := 3.5            # 那一刻更长，郑重
const GLANCE_NOD := deg_to_rad(16.0)    # 低头幅度（占位）
const GLANCE_TURN := deg_to_rad(150.0)  # 回头幅度：大幅转身看向身后

const STAIR_Y_THRESHOLD := 1.0   # 玩家 Y 超过此值视为踏上楼梯，鹿才开始移动

var _player: Node3D
var _has_glanced := false      # 一生只看一次
var _glance_t := 0.0           # >0 表示正在瞥视
var paused := false            # 字幕播放期间暂停移动
var _started := false          # 玩家踏上楼梯前保持静止


func _ready():

	add_to_group("deer")            # 供行为识别器（behavior.gd）定位

	_player = get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta):

	if paused:
		return

	# 等待玩家踏上楼梯（Y 超过阈值）后才开始移动
	if not _started:
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null or _player.position.y <= STAIR_Y_THRESHOLD:
			return
		_started = true
		print("[deer] 玩家踏上楼梯，鹿开始移动")

	_update_glance(delta)

	# 那一瞥期间停下；其余时刻永远向前
	if _glance_t > 0.0:
		position.x = PATH_X
	else:
		var move = SPEED * delta
		position.x = PATH_X
		position.z -= move
		position.y += move * CLIMB_RATE


# 检测触发、驱动旋转动画、结束后解冻玩家
func _update_glance(delta: float):

	# 引用兜底
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return

	# 首次凑近触发
	if not _has_glanced:
		var dist := global_position.distance_to(_player.global_position)
		if dist < GLANCE_ENTER_DIST:
			_has_glanced = true
			_glance_t = GLANCE_DURATION
			_player.set("frozen", true)
			print("[seeking.gaze] the one glance")

	# 播放瞥视：0→1→0 平滑包络，仅改旋转
	if _glance_t > 0.0:

		_glance_t -= delta

		var progress: float = 1.0 - clamp(_glance_t / GLANCE_DURATION, 0.0, 1.0)
		var env: float = sin(progress * PI)

		var to_player: Vector3 = _player.global_position - global_position
		# GLB 沿 Y 轴翻转 180°，旋转方向镜像，需取反补偿
		var target_yaw: float = clamp(-atan2(to_player.x, to_player.z), -GLANCE_TURN, GLANCE_TURN)

		rotation = Vector3(GLANCE_NOD * env, target_yaw * env, 0.0)

		# 那一瞥结束：复位并解冻玩家，发出信号
		if _glance_t <= 0.0:
			rotation = Vector3.ZERO
			_player.set("frozen", false)
			glance_finished.emit()

	else:
		rotation = Vector3.ZERO
