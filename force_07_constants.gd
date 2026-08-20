extends Node3D

# Force 07 — Constants（恒常）
# Step 1：场景布局
# Step 2：机器状态机 + 独立倒计时 + 呼吸脉动
# Step 3：校准小游戏（SubViewport 判定面板 + 玩家输入）
# Step 4：喂药交互（病人 Area3D + 随熄灭数衰减的光效反馈）
# Step 5：门 + 终局演出（单向，机器全灭与走门共用）
# Step 6：BGM 音量联动（NORMAL 机器数 → 音量）

# ── 场景布局坐标（局部，相对于本节点）────────────────────
const MACHINE_POSITIONS: Array[Vector3] = [
	Vector3(-8.0, 0.0, -10.0),   # 机器 A
	Vector3( 0.0, 0.0, -10.0),   # 机器 B
	Vector3( 8.0, 0.0, -10.0),   # 机器 C
]
const PATIENT_POS := Vector3( 0.0, 0.0,  0.0)
const DOOR_POS    := Vector3(12.0, 0.0, 10.0)   # 右下角，全程可见

# ── 音乐 ──────────────────────────────────────────────
const BGM_PATH := "res://music/constant/城南花已开.mp3"

# ── 机器状态 ───────────────────────────────────────────
const STATE_NORMAL := 0   # 正常：稳定亮度
const STATE_RESCUE := 1   # 回光返照：亮度衰减 + 呼吸脉动
const STATE_DEAD   := 2   # 彻底熄灭：亮度归零

# ── 倒计时参数 ─────────────────────────────────────────
const WINDOW_FIRST      := 15.0   # 首次回光返照窗口（秒）
const WINDOW_DECAY      := 0.75   # 每次救回后窗口缩短比例
const RESCUE_MAX        := 3      # 最大救回次数（第 4 轮静默）
const PULSE_FREQ        := 0.25   # 呼吸脉动频率（Hz）
const INITIAL_DELAY_MIN := 20.0   # 首次进入回光返照的最短延迟
const INITIAL_DELAY_MAX := 35.0   # 首次进入回光返照的最长延迟（随机）
const RECOVERY_MIN      :=  8.0   # 校准成功后黄色恢复期最短时长（秒）
const RECOVERY_MAX      := 20.0   # 校准成功后黄色恢复期最长时长（秒）

# ── 校准小游戏参数 ─────────────────────────────────────
const POINTER_SPEED     := 0.7    # 指针往返速度（次/秒）
const ZONE_START        := 0.40   # 成功区间起始（0~1）
const ZONE_END          := 0.60   # 成功区间结束（0~1）
const TRACK_W           := 200.0  # SubViewport 轨道宽度（像素）
const TRACK_H           := 56.0   # SubViewport 高度（像素）
const CALIB_RADIUS      := 2.5    # 玩家感知半径（m）

# ── 运行时节点引用 ─────────────────────────────────────
var _machines:       Array = []   # [Node3D × 3]
var _machine_lights: Array = []   # [MeshInstance3D × 3] 指示灯，供视觉驱动
var _machine_bodies: Array = []   # [MeshInstance3D × 3] 机器主体，随状态同步发光
var _patient:  Node3D
var _door:     Node3D
var _bgm:      AudioStreamPlayer

# ── 机器运行时状态 ─────────────────────────────────────
var _machine_state:      Array = [STATE_NORMAL, STATE_NORMAL, STATE_NORMAL]
var _machine_window:     Array = [0.0, 0.0, 0.0]   # 当前轮窗口时长
var _machine_elapsed:    Array = [0.0, 0.0, 0.0]   # 当前轮已过时间
var _machine_rescues:    Array = [0, 0, 0]          # 已成功救回次数
var _machine_init_timer:  Array = [0.0, 0.0, 0.0]   # NORMAL 阶段倒计时（首次延迟 or 恢复期）
var _machine_next_window: Array = [15.0, 15.0, 15.0] # 下一次 RESCUE 使用的窗口时长
var _machines_dead: int = 0

# ── Step 3 校准面板运行时 ───────────────────────────────
var _calib_panels:    Array = []              # [Node3D × 3]
var _calib_pointers:  Array = []              # [ColorRect × 3]
var _player_in_range: Array = [false, false, false]
var _hint_labels:     Array = []              # [Label3D × 3] 按空格提示
var _final_labels:    Array = []              # [Label3D × 3] 尽人事，听天命

# ── Step 4 喂药运行时 ───────────────────────────────────
var _player_near_patient: bool = false
var _patient_tubes: Array = []   # [MeshInstance3D] 管线，供喂药闪光使用

# ── Step 5 终局运行时 ───────────────────────────────────
var _ending_triggered: bool = false   # 防止终局重复触发

# ── 区域感知 ─────────────────────────────────────────────
var _player_in_zone: bool = false     # 玩家未进入 Force7 范围时冻结整个状态机

# ── Step 6 BGM 音量 ─────────────────────────────────────
# 索引 = 当前处于 NORMAL 状态的机器数（0~3）
const BGM_VOLUME_DB: Array = [-80.0, -8.0, -3.0, 0.0]
const BGM_FADE_DUR  := 1.0   # 音量过渡时长（秒）
var _bgm_tween: Tween = null  # 复用，避免多个 Tween 同时驱动音量


# ═══════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════

func _ready() -> void:
	_setup_machines()
	_setup_patient()
	_setup_tubes()
	_setup_door()
	_setup_bgm()
	_setup_calib_panels()
	_setup_patient_area()
	_setup_door_area()
	_setup_zone_area()
	# 随机化各机器首次进入回光返照的延迟，使失效顺序自然错开
	for i in 3:
		_machine_init_timer[i] = randf_range(INITIAL_DELAY_MIN, INITIAL_DELAY_MAX)
	print("[constants] Step 4 ready — 喂药交互初始化完成")


# ═══════════════════════════════════════════════════════
# Step 2 — 主循环：倒计时 + 视觉驱动
# ═══════════════════════════════════════════════════════

func _process(delta: float) -> void:
	# 玩家不在 Force7 范围内时，整个状态机冻结，倒计时不推进
	if not _player_in_zone:
		return
	for i in 3:
		match _machine_state[i]:
			STATE_NORMAL:
				_machine_init_timer[i] -= delta
				if _machine_init_timer[i] <= 0.0:
					_enter_rescue(i)
			STATE_RESCUE:
				_machine_elapsed[i] += delta
				_update_machine_visual(i)
				if _machine_elapsed[i] >= _machine_window[i]:
					_on_machine_dead(i)
			STATE_DEAD:
				pass
		# 面板可见时每帧驱动指针
		if i < _calib_panels.size():
			var panel := _calib_panels[i] as Node3D
			if panel and panel.visible:
				_update_calib_pointer(i)


# 机器进入回光返照状态
func _enter_rescue(i: int) -> void:
	_machine_state[i]   = STATE_RESCUE
	_machine_window[i]  = _machine_next_window[i]   # 首次=15s；此后使用衰减后的值
	_machine_elapsed[i] = 0.0
	_update_panel_visibility(i)
	_update_bgm_volume()
	print("[constants] 机器 %s 进入回光返照  window=%.2fs  rescues=%d" % [
		"ABC"[i], _machine_window[i], _machine_rescues[i]
	])
	# 第 4 轮开始时显示"尽人事，听天命"
	if _machine_rescues[i] >= RESCUE_MAX:
		if i < _final_labels.size():
			var lbl := _final_labels[i] as Label3D
			if lbl:
				lbl.visible = true


# 每帧更新机器指示灯亮度
func _update_machine_visual(i: int) -> void:
	var mi := _machine_lights[i] as MeshInstance3D
	if mi == null:
		return
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		return

	# 主体材质（可能为 null，容错处理）
	var body_mi  := _machine_bodies[i] as MeshInstance3D
	var body_mat := body_mi.material_override as StandardMaterial3D if body_mi else null

	match _machine_state[i]:
		STATE_NORMAL:
			mat.emission_energy_multiplier = 1.2
			if body_mat:
				body_mat.albedo_color               = Color(0.90, 0.52, 0.62)   # 粉色
				body_mat.emission                   = Color(1.0, 0.58, 0.70)
				body_mat.emission_energy_multiplier = 0.45
		STATE_RESCUE:
			var t_norm := clampf(_machine_elapsed[i] / _machine_window[i], 0.0, 1.0)
			if _machine_rescues[i] >= RESCUE_MAX:
				# 第 4 轮静默：无脉动提示，仅轻微线性衰减至熄灭
				mat.emission_energy_multiplier = lerp(0.30, 0.0, t_norm)
				if body_mat:
					body_mat.albedo_color               = Color(0.52, 0.22, 0.72)   # 紫色
					body_mat.emission                   = Color(0.65, 0.28, 0.88)
					body_mat.emission_energy_multiplier = lerp(0.10, 0.0, t_norm)
			else:
				# 正常回光返照：线性衰减 × 呼吸脉动（从远处可见的求救信号）
				var decay := 1.0 - t_norm
				var t     := Time.get_ticks_msec() * 0.001
				var pulse := (sin(t * PULSE_FREQ * TAU) + 1.0) * 0.5
				# 指示灯：峰值 4.0，谷值 0.1，随窗口衰减
				mat.emission_energy_multiplier = lerp(0.1, 4.0, decay) * lerp(0.5, 1.0, pulse)
				if body_mat:
					body_mat.albedo_color               = Color(0.52, 0.22, 0.72)   # 紫色
					body_mat.emission                   = Color(0.65, 0.28, 0.88)
					body_mat.emission_energy_multiplier = lerp(0.0, 0.8, decay) * lerp(0.5, 1.0, pulse)
		STATE_DEAD:
			mat.emission_energy_multiplier = 0.0
			if body_mat:
				body_mat.albedo_color               = Color(0.72, 0.73, 0.76)   # 银灰
				body_mat.emission                   = Color(0.72, 0.73, 0.76)
				body_mat.emission_energy_multiplier = 0.0


# 倒计时耗尽 → 机器永久熄灭
func _on_machine_dead(i: int) -> void:
	if _machine_state[i] == STATE_DEAD:
		return   # 防重入
	_machine_state[i] = STATE_DEAD
	_machines_dead   += 1
	_update_machine_visual(i)
	_update_panel_visibility(i)   # 强制隐藏校准面板
	_update_bgm_volume()
	print("[constants] 机器 %s 永久熄灭  dead=%d/3" % ["ABC"[i], _machines_dead])
	if _machines_dead >= 3:
		_on_all_machines_dead()


# 校准成功（由 Step 3 调用）
# 机器回亮，重置倒计时为 window×0.7，救回次数 +1
func on_rescue_success(i: int) -> void:
	if _machine_state[i] != STATE_RESCUE:
		return
	if _machine_rescues[i] >= RESCUE_MAX:
		return   # 第 4 轮静默，不响应校准

	_machine_rescues[i]      += 1
	_machine_next_window[i]   = _machine_window[i] * WINDOW_DECAY   # 保存衰减后窗口供下轮用
	_machine_elapsed[i]       = 0.0

	# 回到点亮状态（黄色），随机 8~20s 后再触发下一次回光返照
	_machine_state[i]         = STATE_NORMAL
	_machine_init_timer[i]    = randf_range(RECOVERY_MIN, RECOVERY_MAX)
	_update_machine_visual(i)   # 立即切换回粉色
	_update_panel_visibility(i) # 面板随 STATE_NORMAL 自动隐藏
	_update_bgm_volume()

	_flash_machine(i)
	print("[constants] 机器 %s 校准成功  rescues=%d/%d  next_window=%.2fs  recovery=%.1fs" % [
		"ABC"[i], _machine_rescues[i], RESCUE_MAX,
		_machine_next_window[i], _machine_init_timer[i]
	])


# 校准成功的短暂提亮反馈（覆盖呼吸脉动，明确告知玩家"输入生效"）
func _flash_machine(i: int) -> void:
	var mi := _machine_lights[i] as MeshInstance3D
	if mi == null:
		return
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		return

	# 指示灯：急速提亮后缓降
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v,
		mat.emission_energy_multiplier, 8.0, 0.08)
	tw.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v,
		8.0, 1.2, 0.45).set_ease(Tween.EASE_OUT)

	# 主体：校准成功瞬间复原冷灰（0.15s 内），提示"已救回"
	var body_mi  := _machine_bodies[i] as MeshInstance3D
	var body_mat := body_mi.material_override as StandardMaterial3D if body_mi else null
	if body_mat:
		var tw2 := create_tween()
		tw2.tween_method(
			func(c: Color) -> void: body_mat.emission = c,
			Color(1.0, 0.45, 0.08), Color(0.72, 0.73, 0.76), 0.15
		)
		# 0.6s 后重新变回琥珀橙（进入下一轮 RESCUE）
		tw2.tween_interval(0.60)
		tw2.tween_method(
			func(c: Color) -> void: body_mat.emission = c,
			Color(0.72, 0.73, 0.76), Color(1.0, 0.45, 0.08), 0.30
		)


# 三台机器全部熄灭
func _on_all_machines_dead() -> void:
	print("[constants] 三台机器全部熄灭 → 终局")
	_trigger_ending()


# ═══════════════════════════════════════════════════════
# Step 3 — 校准小游戏
# ═══════════════════════════════════════════════════════

func _setup_calib_panels() -> void:
	for i in 3:
		_make_calib_panel(i)


func _make_calib_panel(i: int) -> void:
	var panel := Node3D.new()
	panel.name    = "CalibrationPanel_%s" % "ABC"[i]
	panel.visible = false

	# ── SubViewport（200×56 px 轨道）──────────────────
	var vp := SubViewport.new()
	vp.name                      = "VP"
	vp.size                      = Vector2i(int(TRACK_W), int(TRACK_H))
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED   # 隐藏时停渲染
	vp.transparent_bg            = true
	panel.add_child(vp)

	# 根 Control
	var ctrl := Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(ctrl)

	# 轨道背景（深色半透明）
	var track := ColorRect.new()
	track.color = Color(0.08, 0.08, 0.12, 0.88)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(track)

	# 成功区间（40%~60%，绿色高亮）
	var zone := ColorRect.new()
	zone.color    = Color(1.0, 0.75, 0.80, 0.75)
	zone.size     = Vector2((ZONE_END - ZONE_START) * TRACK_W, TRACK_H)
	zone.position = Vector2(ZONE_START * TRACK_W, 0.0)
	ctrl.add_child(zone)

	# 指针（白色 3px 细条）
	var pointer := ColorRect.new()
	pointer.color = Color(1.0, 1.0, 1.0, 0.95)
	pointer.size  = Vector2(3.0, TRACK_H)
	ctrl.add_child(pointer)
	_calib_pointers.append(pointer)

	# ── Sprite3D（贴 SubViewport 纹理，始终朝向相机）──
	var sprite := Sprite3D.new()
	sprite.name       = "Sprite"
	sprite.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.01          # 200px = 2.0 units 宽
	sprite.position   = Vector3(0.0, 3.2, 0.0)   # 悬浮于机器顶部
	panel.add_child(sprite)

	# ── Area3D（检测玩家靠近）────────────────────────
	var area   := Area3D.new()
	var cshape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius  = CALIB_RADIUS
	cshape.shape   = sphere
	area.add_child(cshape)
	var idx := i   # 闭包捕获
	area.body_entered.connect(func(body: Node3D) -> void: _on_calib_entered(idx, body))
	area.body_exited.connect( func(body: Node3D) -> void: _on_calib_exited( idx, body))
	panel.add_child(area)

	# 挂载到对应机器（此时机器已在树中）
	_machines[i].add_child(panel)

	# 设置纹理（需在节点进树后才有效）
	sprite.texture = vp.get_texture()

	_calib_panels.append(panel)

	# ── 按空格提示（Label3D，面板下方，与面板同步显隐）────
	var hint := Label3D.new()
	hint.name        = "HintLabel"
	hint.text        = "[ Space ] 校准"
	hint.font_size   = 36
	hint.modulate    = Color(1.0, 1.0, 1.0, 0.80)
	hint.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	hint.pixel_size  = 0.004
	hint.position    = Vector3(0.0, 2.7, 0.0)
	hint.visible     = false
	_machines[i].add_child(hint)
	_hint_labels.append(hint)

	# ── 最终文字（Label3D，第 4 轮起显示，不可交互）────────
	var final_lbl := Label3D.new()
	final_lbl.name       = "FinalLabel"
	final_lbl.text       = "尽人事，听天命"
	final_lbl.font_size  = 40
	final_lbl.modulate   = Color(0.95, 0.88, 0.75, 0.88)
	final_lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	final_lbl.pixel_size = 0.004
	final_lbl.position   = Vector3(0.0, 1.5, 0.45)   # 机器正面中部
	final_lbl.visible    = false
	_machines[i].add_child(final_lbl)
	_final_labels.append(final_lbl)


# 面板显隐 + SubViewport 渲染开关
func _update_panel_visibility(i: int) -> void:
	if i >= _calib_panels.size():
		return
	var panel := _calib_panels[i] as Node3D
	if panel == null:
		return
	# 只在可校准轮次（rescues < RESCUE_MAX）显示面板和按键提示
	var can_interact: bool = _machine_rescues[i] < RESCUE_MAX
	var show: bool = bool(_player_in_range[i]) and _machine_state[i] == STATE_RESCUE and can_interact
	panel.visible = show
	var vp := panel.get_node_or_null("VP") as SubViewport
	if vp:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show else SubViewport.UPDATE_DISABLED
	# 按键提示与面板同步
	if i < _hint_labels.size():
		var hint := _hint_labels[i] as Label3D
		if hint:
			hint.visible = show


# 每帧更新指针位置（仅面板可见时调用）
func _update_calib_pointer(i: int) -> void:
	var pointer := _calib_pointers[i] as ColorRect
	if pointer == null:
		return
	var t := pingpong(Time.get_ticks_msec() / 1000.0 * POINTER_SPEED, 1.0)
	pointer.position.x = t * TRACK_W - 1.5   # 1.5 = 指针宽度的一半，居中对齐


# 玩家进入感知范围
func _on_calib_entered(i: int, body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range[i] = true
	_update_panel_visibility(i)


# 玩家离开感知范围
func _on_calib_exited(i: int, body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range[i] = false
	_update_panel_visibility(i)


# 玩家按交互键 → 优先校准机器，其次喂药
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	# 校准：优先级最高
	for i in 3:
		if _player_in_range[i] and _machine_state[i] == STATE_RESCUE:
			_try_calibrate(i)
			return
	# 喂药：玩家在病人旁
	if _player_near_patient:
		_do_feed()
		return
	# 离开：玩家在门口
	var lbl := _door.get_node_or_null("DoorHint") as Label3D if _door else null
	if lbl and lbl.visible:
		_try_door_leave()


# 判定：指针是否落在成功区间
func _try_calibrate(i: int) -> void:
	var t := pingpong(Time.get_ticks_msec() / 1000.0 * POINTER_SPEED, 1.0)
	if t >= ZONE_START and t <= ZONE_END:
		on_rescue_success(i)
		print("[constants] 机器 %s 校准命中  t=%.3f" % ["ABC"[i], t])
	else:
		print("[constants] 机器 %s 校准失败  t=%.3f" % ["ABC"[i], t])


# ═══════════════════════════════════════════════════════
# 机器 A / B / C（复用同一函数）
# ═══════════════════════════════════════════════════════

func _setup_machines() -> void:
	for i in MACHINE_POSITIONS.size():
		var m := _make_machine(i, MACHINE_POSITIONS[i])
		add_child(m)
		_machines.append(m)
		_machine_lights.append(m.get_node("IndicatorLight"))
		_machine_bodies.append(m.get_node("Body"))


func _make_machine(idx: int, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Machine_%s" % "ABC"[idx]
	root.position = pos

	# 主体箱（初始黄色点亮；状态机运行时驱动颜色切换）
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color               = Color(0.90, 0.52, 0.62)   # 粉色
	body_mat.roughness                  = 0.75
	body_mat.metallic                   = 0.10
	body_mat.emission_enabled           = true
	body_mat.emission                   = Color(1.0, 0.58, 0.70)   # 粉色
	body_mat.emission_energy_multiplier = 0.45

	var body := MeshInstance3D.new()
	body.name = "Body"
	var box  := BoxMesh.new()
	box.size = Vector3(1.2, 2.0, 0.8)
	body.mesh              = box
	body.material_override = body_mat
	body.position          = Vector3(0.0, 1.0, 0.0)   # 底部贴地
	root.add_child(body)

	# 顶部指示灯（黄色点亮，Step 2 驱动亮度变化）
	var light_mat := StandardMaterial3D.new()
	light_mat.albedo_color               = Color(1.0, 0.60, 0.72)   # 粉色
	light_mat.emission_enabled           = true
	light_mat.emission                   = Color(1.0, 0.60, 0.72)
	light_mat.emission_energy_multiplier = 1.2

	var light := MeshInstance3D.new()
	light.name = "IndicatorLight"
	var sph   := SphereMesh.new()
	sph.radius = 0.35
	sph.height = 0.70
	light.mesh              = sph
	light.material_override = light_mat
	light.position          = Vector3(0.0, 2.18, 0.0)
	root.add_child(light)

	return root


# ═══════════════════════════════════════════════════════
# 病人（抽象体，无明确人形）
# ═══════════════════════════════════════════════════════

func _setup_patient() -> void:
	_patient = Node3D.new()
	_patient.name = "Patient"
	_patient.position = PATIENT_POS
	add_child(_patient)

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.98, 0.82, 0.86)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.98, 0.82, 0.86)
	mat.emission_energy_multiplier = 0.35
	mat.roughness                  = 0.90

	# 横置胶囊，模拟躺卧的抽象轮廓
	var mi  := MeshInstance3D.new()
	mi.name  = "Body"
	var cap  := CapsuleMesh.new()
	cap.radius = 0.40
	cap.height = 1.40
	mi.mesh              = cap
	mi.material_override = mat
	mi.rotation_degrees.z = 90.0   # 横置
	mi.position           = Vector3(0.0, 0.45, 0.0)
	_patient.add_child(mi)


# ═══════════════════════════════════════════════════════
# 抽象管线（机器 → 病人）
# ═══════════════════════════════════════════════════════

func _setup_tubes() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.60, 0.62, 0.68, 0.80)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness                  = 0.75
	mat.emission_enabled           = true
	mat.emission                   = Color(0.60, 0.62, 0.68)
	mat.emission_energy_multiplier = 0.12

	for i in MACHINE_POSITIONS.size():
		# 从机器底部前方出发，连到病人侧面
		var p_from := MACHINE_POSITIONS[i] + Vector3(0.0, 0.5, 0.4)
		var p_to   := PATIENT_POS + Vector3(float(i - 1) * 0.30, 0.45, -0.4)
		var tube   := _make_tube(p_from, p_to, mat)
		add_child(tube)
		_patient_tubes.append(tube)   # Step 4 喂药闪光引用


# 通用圆柱管线：将默认 Y 轴对齐到两端点连线方向
func _make_tube(p_from: Vector3, p_to: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var diff   := p_to - p_from
	var length := diff.length()
	if length < 0.01:
		return MeshInstance3D.new()

	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.04
	cyl.bottom_radius = 0.04
	cyl.height        = length

	var mi := MeshInstance3D.new()
	mi.name              = "Tube"
	mi.mesh              = cyl
	mi.material_override = mat
	# 将 Y 轴旋转至 diff 方向，用 Transform3D 一次性赋值（避免 .basis 赋值触发遮蔽警告）
	var up   := diff.normalized()
	var arb  := Vector3.RIGHT if abs(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x_ax := up.cross(arb).normalized()
	var z_ax := x_ax.cross(up).normalized()
	mi.transform = Transform3D(Basis(x_ax, up, z_ax), (p_from + p_to) * 0.5)

	return mi


# ═══════════════════════════════════════════════════════
# 门（右下角，全程可见，Step 5 补充 Area3D 交互）
# ═══════════════════════════════════════════════════════

func _setup_door() -> void:
	_door = Node3D.new()
	_door.name = "Door"
	_door.position = DOOR_POS
	add_child(_door)

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.90, 0.88, 0.84)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.90, 0.88, 0.84)
	mat.emission_energy_multiplier = 0.28
	mat.roughness                  = 0.80

	var mi  := MeshInstance3D.new()
	mi.name  = "DoorFrame"
	var box  := BoxMesh.new()
	box.size = Vector3(0.15, 2.6, 1.6)
	mi.mesh              = box
	mi.material_override = mat
	mi.position          = Vector3(0.0, 1.3, 0.0)
	_door.add_child(mi)

	# 门口提示文字
	var lbl := Label3D.new()
	lbl.name       = "DoorHint"
	lbl.text       = "[ Space ] 离开"
	lbl.font_size  = 36
	lbl.modulate   = Color(1.0, 1.0, 1.0, 0.75)
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.004
	lbl.position   = Vector3(0.0, 3.0, 0.0)
	lbl.visible    = false
	_door.add_child(lbl)


# ═══════════════════════════════════════════════════════
# BGM（Step 6 补充音量联动）
# ═══════════════════════════════════════════════════════

func _setup_bgm() -> void:
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "BGM"
	var stream := load(BGM_PATH) as AudioStream
	if stream:
		_bgm.stream    = stream
		_bgm.volume_db = 0.0
		_bgm.autoplay  = true
	else:
		push_warning("[constants] BGM 未找到: %s" % BGM_PATH)
	add_child(_bgm)


# ═══════════════════════════════════════════════════════
# Step 4 — 喂药交互
# ═══════════════════════════════════════════════════════

func _setup_patient_area() -> void:
	var area   := Area3D.new()
	area.name  = "PatientArea"
	var cshape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	cshape.shape  = sphere
	area.add_child(cshape)
	area.body_entered.connect(_on_patient_entered)
	area.body_exited.connect(_on_patient_exited)
	_patient.add_child(area)


func _on_patient_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near_patient = true


func _on_patient_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near_patient = false


# 喂药：反馈强度随熄灭机器数衰减
func _do_feed() -> void:
	var alive := 3 - _machines_dead   # 0~3

	# 三台全灭 → 零反馈，动作可执行但什么都不发生
	if alive == 0:
		print("[constants] 喂药（零反馈，三台已全灭）")
		return

	print("[constants] 喂药  alive=%d  dead=%d" % [alive, _machines_dead])

	# 病人自身：轻微闪亮（强度随存活数缩放）
	var patient_mi  := _patient.get_node_or_null("Body") as MeshInstance3D
	var patient_mat := patient_mi.material_override as StandardMaterial3D if patient_mi else null
	if patient_mat:
		var peak: float = lerp(0.0, 1.2, float(alive) / 3.0)
		var tw   := create_tween()
		tw.tween_method(func(v: float) -> void: patient_mat.emission_energy_multiplier = v,
			patient_mat.emission_energy_multiplier, 0.35 + peak, 0.15)
		tw.tween_method(func(v: float) -> void: patient_mat.emission_energy_multiplier = v,
			0.35 + peak, 0.35, 0.60).set_ease(Tween.EASE_OUT)

	# 管线闪光（仅 alive >= 2 时）
	if alive >= 2:
		var tube_peak: float = lerp(0.0, 0.8, float(alive - 1) / 2.0)
		for tube in _patient_tubes:
			var tmi := tube as MeshInstance3D
			if tmi == null:
				continue
			var tmat := tmi.material_override as StandardMaterial3D
			if tmat == null:
				continue
			var tw2 := create_tween()
			tw2.tween_method(func(v: float) -> void: tmat.emission_energy_multiplier = v,
				tmat.emission_energy_multiplier, 0.12 + tube_peak, 0.12)
			tw2.tween_method(func(v: float) -> void: tmat.emission_energy_multiplier = v,
				0.12 + tube_peak, 0.12, 0.50).set_ease(Tween.EASE_OUT)


# ═══════════════════════════════════════════════════════
# Step 6 — BGM 音量联动
# ═══════════════════════════════════════════════════════

func _update_bgm_volume() -> void:
	if _bgm == null or _ending_triggered:
		return
	# 统计当前处于 NORMAL 的机器数
	var normal_count := 0
	for i in 3:
		if _machine_state[i] == STATE_NORMAL:
			normal_count += 1
	var target_db: float = BGM_VOLUME_DB[normal_count]
	print("[constants] BGM 音量更新  normal=%d  target=%.1f dB" % [normal_count, target_db])
	# 中断旧 Tween，平滑过渡到新音量
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_method(
		func(v: float) -> void: _bgm.volume_db = v,
		_bgm.volume_db, target_db, BGM_FADE_DUR
	)


# ═══════════════════════════════════════════════════════
# Step 5 — 门 + 终局演出
# ═══════════════════════════════════════════════════════

func _setup_door_area() -> void:
	var area   := Area3D.new()
	area.name  = "DoorArea"
	var cshape := CollisionShape3D.new()
	var box    := BoxShape3D.new()
	box.size   = Vector3(2.0, 3.0, 2.0)   # 门口感知区域
	cshape.shape = box
	area.add_child(cshape)
	area.body_entered.connect(_on_door_entered)
	area.body_exited.connect(_on_door_exited)
	_door.add_child(area)


func _on_door_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# 显示离开提示
	var lbl := _door.get_node_or_null("DoorHint") as Label3D
	if lbl:
		lbl.visible = true


func _on_door_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var lbl := _door.get_node_or_null("DoorHint") as Label3D
	if lbl:
		lbl.visible = false


# ═══════════════════════════════════════════════════════
# 区域感知 — 玩家未靠近时冻结整个 Force7 状态机
# ═══════════════════════════════════════════════════════

func _setup_zone_area() -> void:
	# 覆盖范围：机器 X(-8~+8)、门 X(+12)、Z(-10~+10)，四周各留 5u 余量
	var area   := Area3D.new()
	area.name  = "ZoneArea"
	var cshape := CollisionShape3D.new()
	var box    := BoxShape3D.new()
	box.size   = Vector3(30.0, 6.0, 28.0)   # 横跨整个场景
	cshape.shape    = box
	cshape.position = Vector3(2.0, 1.5, 0.0) # 微偏右以对齐门侧非对称布局
	area.add_child(cshape)
	area.body_entered.connect(_on_zone_entered)
	area.body_exited.connect(_on_zone_exited)
	add_child(area)


func _on_zone_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = true
		print("[constants] 玩家进入 Force7 范围 → 状态机启动")


func _on_zone_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = false
		print("[constants] 玩家离开 Force7 范围 → 状态机冻结")


# 玩家在门口按 Space → 触发终局（_unhandled_input 中已处理门优先级最低）
func _try_door_leave() -> void:
	if not _ending_triggered:
		print("[constants] 玩家走出门 → 终局")
		_trigger_ending()


# 终局序列（机器全灭 / 玩家走门，共用）
func _trigger_ending() -> void:
	if _ending_triggered:
		return
	_ending_triggered = true
	print("[constants] 终局序列启动")

	# 关闭所有校准面板和提示
	for i in 3:
		_player_in_range[i] = false
		_update_panel_visibility(i)
	_player_near_patient = false

	# BGM 淡出（0.5s）
	if _bgm and _bgm.playing:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: _bgm.volume_db = v,
			_bgm.volume_db, -80.0, 0.5)
		await tw.finished
		_bgm.stop()

	# 场景淡出（黑屏，1.5s）—— 通过 CanvasLayer + ColorRect 实现
	var cl  := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	var fade := ColorRect.new()
	fade.color                                  = Color(0.0, 0.0, 0.0, 0.0)
	fade.anchor_right                           = 1.0
	fade.anchor_bottom                          = 1.0
	fade.mouse_filter                           = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade)

	var tw2 := create_tween()
	tw2.tween_method(func(a: float) -> void: fade.color.a = a, 0.0, 1.0, 1.5)
	await tw2.finished

	# 触发服装配饰
	var cm := get_tree().root.find_child("CostumeManager", true, false)
	if cm and cm.has_method("on_constants_ending"):
		cm.on_constants_ending()

	# 等待片刻，黑屏稳定后显示结尾短句
	await get_tree().create_timer(1.0).timeout

	var quote := Label.new()
	quote.text                    = "我们曾竭力挽留，而时间仍从指间经过。"
	quote.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	quote.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	quote.set_anchors_preset(Control.PRESET_FULL_RECT)
	quote.add_theme_font_size_override("font_size", 28)
	quote.modulate                = Color(1.0, 1.0, 1.0, 0.0)
	cl.add_child(quote)

	var tw3 := create_tween()
	tw3.tween_property(quote, "modulate:a", 1.0, 1.5)
	tw3.tween_interval(3.5)
	tw3.tween_property(quote, "modulate:a", 0.0, 1.5)

	# 静默：玩家仍有控制权；机器/病人不再响应
	print("[constants] 终局静默 — 玩家保留控制权")
