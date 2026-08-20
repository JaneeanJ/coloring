extends CharacterBody3D


var speed = 5.0
var gravity = 9.8

var frozen := false            # 被鹿「那一瞥」定住时为 true
var drunk_anim := false        # true 时 idle/walk 切换为醉酒动画

const CLIP_SUFFIX := "mixamo_com"
const DRUNK_IDLE := "drunk_idle/mixamo_com"
const DRUNK_WALK := "drunk_walk/mixamo_com"
var _anim: AnimationPlayer     # 由 world.gd 在 create_player() 注入
var _one_shot_active := false  # 一次性动画播放中，不切换循环动画

# 离开机制（Step 6）
const CENTER_X := 3.0          # 台阶中轴
const EDGE_INNER := 1.6        # 主道半宽；超出即踏入边缘花带
const ON_STAIRS_Y := 1.0       # 需已在台阶上（抬升），避免地面误触
const LEAVE_GAIN := 0.35       # 花带内累积速率
const LEAVE_RETURN := 0.8      # 回主道回退速率（更快，收回容易）
const BUFFER_TIME := 1.5       # 进度满后的最后缓冲（还能走回）

var leave_progress := 0.0      # 0=在路上 … 1=准备离开
var in_band := false           # 当前是否在边缘花带内
var leaving := false           # 已提交离开：原地停住，等花海向上包裹
var _buffer_t := 0.0

var disable_leave := false     # Eros 等非 Seeking 场景设为 true，关闭离开机制


func _physics_process(delta):

	if leaving:
		# 已提交离开：原地静止，交给花海生长包裹（不掉落）
		velocity = Vector3.ZERO
		return


	# 重力
	if not is_on_floor():

		velocity.y -= gravity * delta



	var direction = Vector3.ZERO


	# 冻结期间不接受移动输入（仍受重力，站在原地）
	if not frozen:

		if Input.is_action_pressed("ui_up"):

			direction.z -= 1


		if Input.is_action_pressed("ui_down"):

			direction.z += 1


		if Input.is_action_pressed("ui_left"):

			direction.x -= 1


		if Input.is_action_pressed("ui_right"):

			direction.x += 1



	velocity.x = direction.x * speed

	velocity.z = direction.z * speed



	move_and_slide()

	_update_animation()

	_update_leave(delta)


func _update_animation() -> void:
	if _anim == null or _one_shot_active:
		return

	if frozen:
		var idle := "idle/" + CLIP_SUFFIX
		if _anim.current_animation != idle:
			_anim.play(idle)
		return

	var h_speed := Vector2(velocity.x, velocity.z).length()

	var target: String
	if h_speed < 0.1:
		target = DRUNK_IDLE if drunk_anim else "idle/" + CLIP_SUFFIX
	else:
		target = DRUNK_WALK if drunk_anim else "walk/" + CLIP_SUFFIX

	if _anim.current_animation != target or not _anim.is_playing():
		var anim_res := _anim.get_animation(target)
		if anim_res:
			anim_res.loop_mode = Animation.LOOP_LINEAR
		_anim.play(target)


# 播放一次性动画（drink / raise）
# keep_pose=true：播完后冻结在最后一帧，_one_shot_active 保持 true（由调用方手动释放）
# speed：播放速度倍率，< 1.0 放慢动画
func play_one_shot(anim_name: String, keep_pose: bool = false, speed: float = 1.0) -> void:
	if _anim == null:
		return
	var full := anim_name + "/" + CLIP_SUFFIX
	if not _anim.has_animation(full):
		push_warning("[player] 找不到动画: " + full)
		return
	_one_shot_active = true
	_anim.speed_scale = speed
	_anim.play(full)
	await _anim.animation_finished
	_anim.speed_scale = 1.0   # 恢复正常速度
	if keep_pose:
		_anim.pause()   # 冻结在最后一帧
	else:
		_one_shot_active = false


# 踏入边缘花带 → 离开进度上升；回主道 → 回退（可逆）
func _update_leave(delta):

	if disable_leave:
		in_band = false
		return

	in_band = (not frozen) and position.y > ON_STAIRS_Y and abs(position.x - CENTER_X) > EDGE_INNER

	if in_band:
		leave_progress += LEAVE_GAIN * delta
	else:
		leave_progress -= LEAVE_RETURN * delta

	leave_progress = clamp(leave_progress, 0.0, 1.0)


	# 进度满 → 最后缓冲；缓冲内仍在花带 → 提交离开，原地等花海向上包裹
	if leave_progress >= 1.0 and in_band:
		_buffer_t += delta
		if _buffer_t >= BUFFER_TIME:
			leaving = true
			print("[seeking.exit] the flowers rise to hold you")
	else:
		_buffer_t = 0.0


# 由 world.gd 在淡出后调用：回到出生点，一切归零
func reset_to(spawn: Vector3):

	position = spawn
	velocity = Vector3.ZERO
	leave_progress = 0.0
	_buffer_t = 0.0
	in_band = false
	leaving = false
	frozen = false
