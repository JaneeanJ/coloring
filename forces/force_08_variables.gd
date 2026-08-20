extends Node3D

# Force 08 — Variables（变数）
# Step 1：场景基础（空气墙、区域感知、起点红球标记）
# Step 2：薄片系统（Mesh + 颜色 + 蚀刻文字 + Tween 移动）
# Step 3：薄片交互流程（冻结 → 白屏 → 一句话 → 回世界 → 请继续生活 → W 解冻）×4
# Step 4：第四片后着色 + 桌子电脑（道路材质 + 桌椅 + SubViewport + BGM）
# Step 5：NPC 群像 + 第五 / 六片薄片（逐渐出现 + 画卷 + 不冻结薄片）
# Step 6：终局演出（旁边椅子 + 镜头拉远 + 群像构图 + 结束）

# ── 场景参数（局部坐标，相对于本节点）─────────────────
const ROAD_LENGTH   := 350.0
const WALL_HEIGHT   := 6.0
const WALL_OFFSET_X := 30.0
const ZONE_BOX      := Vector3(68.0, 8.0, 370.0)

# ── Step 2 薄片参数 ──────────────────────────────────────
const SLICE_SIZE    := Vector3(62.0, 8.0, 0.08)
const SLICE_SPEED   := 1.8
const SLICE_AHEAD   := 50.0   # 薄片生成在玩家前方多远（-Z 方向）
const SLICE_BEHIND  := 20.0   # 薄片移动终点在玩家后方多远（+Z 方向）

const SLICE_TEXTS: Array[String] = [
	"考研第一次失败",
	"姥爷去世",
	"考研第二次失败",
	"辞职",
]
const SLICE_COLORS: Array[Color] = [
	Color(0.72, 0.76, 0.82),
	Color(0.88, 0.88, 0.89),
	Color(0.55, 0.60, 0.68),
	Color(0.76, 0.74, 0.71),
]
const SLICE_ALPHAS: Array[float] = [0.18, 0.15, 0.20, 0.16]

# ── Step 3 交互参数 ──────────────────────────────────────
const HIT_PRE_WAIT  := 2.5   # 薄片穿过后到白屏开始前的停顿（秒）
const FADE_IN_DUR   := 1.2   # 白屏淡出时长
const FADE_WAIT     := 0.3   # 白屏后等待时长
const TEXT_IN_DUR   := 1.5   # 中央文字淡入时长
const TEXT_HOLD     := 3.5   # 中央文字停留时长
const TEXT_OUT_DUR  := 1.2   # 中央文字淡出时长
const FADE_OUT_DUR  := 1.0   # 白屏淡回世界时长
const OVERHEAD_OUT  := 1.0   # "请继续生活"淡出时长
const NEXT_DELAY    := 8.0   # 玩家解冻后下一片出现前的沉默间隔（秒）

const SLICE_SENTENCES: Array[String] = [
	"有些远方，走了很久，也未必抵达。",
	"有些告别，没有下一次重逢。",
	"有些路，再走一次，也不会通往不同的结局。",
	"有些路，走着走着，便不再想走了。",
]

# ── Step 5 NPC 参数 ──────────────────────────────────────
const NPC_MAX                := 10
const NPC_SPAWN_INTERVAL_MIN := 3.0
const NPC_SPAWN_INTERVAL_MAX := 6.0
const AMBIENT_ALPHA_5        := 0.18
const AMBIENT_ALPHA_6        := 0.12
const AMBIENT_SPEED          := 1.8    # 较快移动速度
const AMBIENT_AHEAD          := 30.0   # 玩家就座后，仅需 30u 前方生成
const AMBIENT_BEHIND         := 15.0   # 经过玩家后 15u 消失
# NPC 相对于 _table_root 的散布偏移（Force08 本地坐标，-Z 为玩家前行方向）
const NPC_POSITIONS: Array = [
	Vector3(-6.0,  0.0, -2.0),   # 左近
	Vector3( 5.5,  0.0, -4.0),   # 右近
	Vector3(-10.0, 0.0, -6.0),   # 远左
	Vector3( 3.0,  0.0, -10.0),  # 右中
	Vector3(-4.5,  0.0, -14.0),  # 左远
	Vector3( 8.0,  0.0, -2.5),   # 右近2
	Vector3(-12.0, 0.0, -3.0),   # 极左
	Vector3( 9.5,  0.0, -8.0),   # 右中2
	Vector3(-7.0,  0.0, -16.0),  # 左极远
	Vector3( 2.5,  0.0, -12.0),  # 右远
]
# 10 个 NPC 各自不同的画卷主色（鲜亮、互相区分）
const NPC_CANVAS_COLORS: Array[Color] = [
	Color(0.92, 0.28, 0.26),   # 正红
	Color(0.22, 0.58, 0.92),   # 蓝
	Color(0.28, 0.80, 0.42),   # 绿
	Color(0.96, 0.76, 0.12),   # 黄
	Color(0.82, 0.38, 0.88),   # 紫
	Color(0.96, 0.50, 0.15),   # 橙
	Color(0.15, 0.85, 0.80),   # 青
	Color(0.92, 0.25, 0.58),   # 粉红
	Color(0.60, 0.88, 0.20),   # 黄绿
	Color(0.42, 0.25, 0.88),   # 蓝紫
]

# ── 运行时节点引用 ─────────────────────────────────────
var _slice_nodes:    Array = []
var _player:         Node3D
var _canvas_layer:   CanvasLayer
var _fade_rect:      ColorRect
var _center_label:   Label
var _overhead_label: Label3D

# ── Step 4 节点引用 ──────────────────────────────────
var _table_root:   Node3D
var _desk_camera:  Camera3D
var _screen_vp:    SubViewport
var _bgm:          AudioStreamPlayer
var _player_near_table: bool = false
var _seated:            bool = false

# ── Step 6 节点引用 ──────────────────────────────────────
var _chair_extra: Node3D = null   # 旁边椅子，Step 6 时才显示

# ── Step 5 节点引用 ──────────────────────────────────────
var _npcs:              Array = []
var _ambient_slices:    Array = []
var _ambient_hit_flags: Array = [false, false]

# ── 状态变量 ──────────────────────────────────────────
var _player_in_zone:   bool = false
var _current_slice:    int  = 0
var _slice_active:     bool = false
var _slice_hit_flags:  Array = [false, false, false, false]
var _waiting_for_w:    bool = false


# ═══════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════

func _ready() -> void:
	_setup_marker()
	_setup_walls()
	_setup_wall_markers()
	_setup_zone_area()
	_setup_slices()
	_setup_ui()
	print("[variables] Step 1-3 ready — 初始化完成")


func _process(_delta: float) -> void:
	if not _player_in_zone:
		return
	# 头顶文字跟随玩家
	if _overhead_label and _overhead_label.visible and _player:
		_overhead_label.global_position = _player.global_position + Vector3(0.0, 2.6, 0.0)


# ═══════════════════════════════════════════════════════
# Step 1 — 场景基础
# ═══════════════════════════════════════════════════════

func _setup_marker() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.15, 0.15)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.15, 0.15)
	mat.emission_energy_multiplier = 1.5
	var mi  := MeshInstance3D.new()
	mi.name  = "Marker"
	var sph := SphereMesh.new()
	sph.radius = 0.3
	sph.height = 0.6
	mi.mesh              = sph
	mi.material_override = mat
	mi.position          = Vector3(0.0, 1.8, 0.0)
	add_child(mi)


func _setup_wall_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.85, 0.1)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.85, 0.1)
	mat.emission_energy_multiplier = 1.2
	for side in [-1, 1]:
		var mi  := MeshInstance3D.new()
		mi.name  = "WallMarker_%s" % ("L" if side == -1 else "R")
		var sph := SphereMesh.new()
		sph.radius = 0.25
		sph.height = 0.5
		mi.mesh              = sph
		mi.material_override = mat
		mi.position          = Vector3(side * WALL_OFFSET_X, 1.2, 0.0)
		add_child(mi)


func _setup_walls() -> void:
	for side in [-1, 1]:
		var body   := StaticBody3D.new()
		body.name   = "Wall_%s" % ("L" if side == -1 else "R")
		var cshape := CollisionShape3D.new()
		var box    := BoxShape3D.new()
		box.size   = Vector3(0.2, WALL_HEIGHT, ROAD_LENGTH)
		cshape.shape = box
		body.add_child(cshape)
		body.position = Vector3(side * WALL_OFFSET_X, WALL_HEIGHT * 0.5, -ROAD_LENGTH * 0.5)
		add_child(body)


func _setup_zone_area() -> void:
	var area   := Area3D.new()
	area.name  = "ZoneArea"
	var cshape := CollisionShape3D.new()
	var box    := BoxShape3D.new()
	box.size   = ZONE_BOX
	cshape.shape    = box
	cshape.position = Vector3(0.0, ZONE_BOX.y * 0.5, -ZONE_BOX.z * 0.5)
	area.add_child(cshape)
	area.body_entered.connect(_on_zone_entered)
	area.body_exited.connect(_on_zone_exited)
	add_child(area)


func _on_zone_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player         = body
		_player_in_zone = true
		print("[variables] 玩家进入 Force8 范围")
		_activate_slice(0)


func _on_zone_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = false
		print("[variables] 玩家离开 Force8 范围")


# ═══════════════════════════════════════════════════════
# Step 2 — 薄片系统
# ═══════════════════════════════════════════════════════

func _setup_slices() -> void:
	for i in 4:
		var node := _make_slice(i)
		node.visible = false
		add_child(node)
		_slice_nodes.append(node)


func _make_slice(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Slice_%d" % i

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = SLICE_COLORS[i]
	mat.albedo_color.a             = SLICE_ALPHAS[i]
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness                  = 0.85
	mat.emission_enabled           = true
	mat.emission                   = SLICE_COLORS[i]
	mat.emission_energy_multiplier = 0.02

	var mi  := MeshInstance3D.new()
	mi.name  = "Mesh"
	var box  := BoxMesh.new()
	box.size = SLICE_SIZE
	mi.mesh              = box
	mi.material_override = mat
	mi.position          = Vector3(0.0, SLICE_SIZE.y * 0.5, 0.0)
	root.add_child(mi)

	var lbl := Label3D.new()
	lbl.name             = "Label"
	lbl.text             = SLICE_TEXTS[i]
	lbl.font_size        = 120          # 加大字号，清晰可见
	lbl.pixel_size       = 0.007
	lbl.billboard        = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.modulate         = Color(1.0, 0.98, 0.96, 0.95)   # 近白，高对比
	lbl.outline_size     = 8
	lbl.outline_modulate = Color(0.10, 0.08, 0.06, 1.0)   # 深色描边防背景融合
	lbl.position         = Vector3(0.0, SLICE_SIZE.y * 0.5, 0.06)
	root.add_child(lbl)

	var area    := Area3D.new()
	area.name   = "HitArea"
	var cshape  := CollisionShape3D.new()
	var hit_box := BoxShape3D.new()
	hit_box.size    = Vector3(SLICE_SIZE.x, SLICE_SIZE.y, 0.5)
	cshape.shape    = hit_box
	cshape.position = Vector3(0.0, SLICE_SIZE.y * 0.5, 0.0)
	area.add_child(cshape)
	area.monitoring = false   # 默认关闭，_activate_slice 时才开启
	var idx := i
	area.body_exited.connect(func(body: Node3D) -> void: _on_slice_body_exited(idx, body))
	root.add_child(area)

	return root


func _activate_slice(i: int) -> void:
	if i >= _slice_nodes.size():
		return
	_current_slice       = i
	_slice_active        = true
	_slice_hit_flags[i]  = false

	# 以玩家当前本地 Z 为基准动态计算生成点和终点
	var player_local_z := to_local(_player.global_position).z
	var spawn_z        := player_local_z - SLICE_AHEAD    # 玩家前方
	var end_z          := player_local_z + SLICE_BEHIND   # 玩家后方

	var node := _slice_nodes[i] as Node3D
	node.position.z = spawn_z
	node.visible    = true
	# 激活时才开启 Area3D 检测，防止未激活的薄片误触发
	var area := node.get_node("HitArea") as Area3D
	if area:
		area.monitoring = true

	var duration := (end_z - spawn_z) / SLICE_SPEED
	var tw := create_tween()
	tw.tween_property(node, "position:z", end_z, duration).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: _on_slice_passed(i))

	print("[variables] 薄片 %d 激活  dur=%.1fs" % [i, duration])


func _on_slice_passed(i: int) -> void:
	(_slice_nodes[i] as Node3D).visible = false
	_slice_active = false
	print("[variables] 薄片 %d 移出画面" % i)


func _on_slice_body_exited(i: int, body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if _slice_hit_flags[i]:
		return
	_slice_hit_flags[i] = true
	print("[variables] 薄片 %d 穿过玩家" % i)
	_on_slice_hit(i)


# ═══════════════════════════════════════════════════════
# Step 3 — 薄片交互流程
# ═══════════════════════════════════════════════════════

func _setup_ui() -> void:
	# CanvasLayer：白屏 + 中央文字，layer=20 确保覆盖所有 3D 内容
	_canvas_layer       = CanvasLayer.new()
	_canvas_layer.layer = 20
	add_child(_canvas_layer)

	# 白屏（白色，初始完全透明）
	_fade_rect             = ColorRect.new()
	_fade_rect.color       = Color(1.0, 1.0, 1.0, 0.0)
	_fade_rect.anchor_right  = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_fade_rect)

	# 中央文字
	_center_label = Label.new()
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.add_theme_font_size_override("font_size", 28)
	_center_label.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08))
	_center_label.modulate.a = 0.0
	_center_label.visible    = false
	_canvas_layer.add_child(_center_label)

	# 头顶"请继续生活"（Label3D，跟随玩家位置）
	_overhead_label               = Label3D.new()
	_overhead_label.name          = "OverheadLabel"
	_overhead_label.text          = "请继续生活。"
	_overhead_label.font_size     = 48
	_overhead_label.pixel_size    = 0.005
	_overhead_label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.modulate      = Color(1.0, 0.98, 0.95, 1.0)   # 暖白，清晰可读
	_overhead_label.outline_size  = 6                               # 描边防止背景干扰
	_overhead_label.outline_modulate = Color(0.08, 0.06, 0.05, 1.0)  # 深棕描边
	_overhead_label.visible       = false
	add_child(_overhead_label)


func _on_slice_hit(i: int) -> void:
	# 薄片穿过后先停顿一拍，给玩家留下余韵
	await get_tree().create_timer(HIT_PRE_WAIT).timeout

	# 冻结玩家（仍受重力，站在原地；按 W 前不可移动）
	if _player:
		_player.set("frozen", true)

	# 白屏淡出
	var tw1 := create_tween()
	tw1.tween_method(func(a: float) -> void: _fade_rect.color.a = a, 0.0, 1.0, FADE_IN_DUR)
	await tw1.finished

	await get_tree().create_timer(FADE_WAIT).timeout

	# 中央文字淡入
	_center_label.text       = SLICE_SENTENCES[i]
	_center_label.modulate.a = 0.0
	_center_label.visible    = true
	var tw2 := create_tween()
	tw2.tween_property(_center_label, "modulate:a", 1.0, TEXT_IN_DUR)
	await tw2.finished

	await get_tree().create_timer(TEXT_HOLD).timeout

	# 中央文字淡出
	var tw3 := create_tween()
	tw3.tween_property(_center_label, "modulate:a", 0.0, TEXT_OUT_DUR)
	await tw3.finished
	_center_label.visible = false

	# 白屏淡回世界
	var tw4 := create_tween()
	tw4.tween_method(func(a: float) -> void: _fade_rect.color.a = a, 1.0, 0.0, FADE_OUT_DUR)
	await tw4.finished

	# 头顶文字出现，等待玩家按 W
	_overhead_label.modulate.a = 1.0
	_overhead_label.visible    = true
	_waiting_for_w             = true
	print("[variables] 等待玩家按 W — 薄片 %d" % i)


func _unhandled_input(event: InputEvent) -> void:
	# W 键：解冻继续生活
	if _waiting_for_w and event.is_action_pressed("ui_up"):
		_waiting_for_w = false
		_do_resume(_current_slice)
		return
	# Space：坐下
	if event.is_action_pressed("ui_accept") and _player_near_table:
		_try_sit_down()


func _do_resume(i: int) -> void:
	# 解冻玩家
	if _player:
		_player.set("frozen", false)

	# "请继续生活"淡出
	var tw := create_tween()
	tw.tween_property(_overhead_label, "modulate:a", 0.0, OVERHEAD_OUT)
	await tw.finished
	_overhead_label.visible = false

	# 沉默间隔：让玩家自由行走一段后下一片再出现
	await get_tree().create_timer(NEXT_DELAY).timeout

	# 激活下一片，或进入 Step 4
	var next := i + 1
	if next < 4:
		_activate_slice(next)
	else:
		_on_all_slices_done()


# ═══════════════════════════════════════════════════════
# Step 4 — 道路着色 + 桌子电脑
# ═══════════════════════════════════════════════════════

func _on_all_slices_done() -> void:
	print("[variables] 四片薄片全部完成 → Step 4 启动")
	_colorize_road()
	await get_tree().create_timer(1.0).timeout
	_spawn_table()
	_start_bgm()


# 道路着色：找到 world.gd 里的 PathSurface，tween albedo_color
func _colorize_road() -> void:
	var road := get_tree().root.find_child("PathSurface", true, false) as MeshInstance3D
	if road == null:
		push_warning("[variables] PathSurface 未找到，跳过着色")
		return
	var mat := road.material_override as StandardMaterial3D
	if mat == null:
		return
	# 目标色：呼应前七章色谱的暖混色
	var target := Color(0.72, 0.55, 0.58)
	var tw := create_tween()
	tw.tween_method(
		func(c: Color) -> void: mat.albedo_color = c,
		mat.albedo_color, target, 4.0
	)
	print("[variables] 道路着色启动")


# 桌子、椅子、屏幕：全部相对玩家当前位置生成
func _spawn_table() -> void:
	# 桌子在玩家前方 15u，与玩家同 X
	var base := to_local(_player.global_position) + Vector3(0.0, 0.0, -15.0)

	_table_root          = Node3D.new()
	_table_root.name     = "TableRoot"
	_table_root.position = base
	add_child(_table_root)

	# ── 桌面 ────────────────────────────────────────
	var table_mat := StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.82, 0.78, 0.72)
	table_mat.roughness    = 0.80

	var table_mi  := MeshInstance3D.new()
	table_mi.name  = "TableTop"
	var table_box  := BoxMesh.new()
	table_box.size = Vector3(1.6, 0.06, 0.9)
	table_mi.mesh              = table_box
	table_mi.material_override = table_mat
	table_mi.position          = Vector3(0.0, 0.82, 0.0)
	_table_root.add_child(table_mi)

	# ── 桌腿（四根细柱）────────────────────────────
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.70, 0.65, 0.58)
	leg_mat.roughness    = 0.85
	for lx in [-0.72, 0.72]:
		for lz in [-0.38, 0.38]:
			var leg_mi  := MeshInstance3D.new()
			var leg_box  := BoxMesh.new()
			leg_box.size = Vector3(0.06, 0.82, 0.06)
			leg_mi.mesh              = leg_box
			leg_mi.material_override = leg_mat
			leg_mi.position          = Vector3(lx, 0.41, lz)
			_table_root.add_child(leg_mi)

	# ── 椅子 ────────────────────────────────────────
	var chair_mat := StandardMaterial3D.new()
	chair_mat.albedo_color = Color(0.78, 0.74, 0.68)
	chair_mat.roughness    = 0.85

	var seat_mi  := MeshInstance3D.new()
	seat_mi.name  = "Chair"
	var seat_box  := BoxMesh.new()
	seat_box.size = Vector3(0.50, 0.05, 0.50)
	seat_mi.mesh              = seat_box
	seat_mi.material_override = chair_mat
	seat_mi.position          = Vector3(0.0, 0.48, 0.55)
	_table_root.add_child(seat_mi)

	var back_mi  := MeshInstance3D.new()
	var back_box  := BoxMesh.new()
	back_box.size = Vector3(0.50, 0.50, 0.04)
	back_mi.mesh              = back_box
	back_mi.material_override = chair_mat
	back_mi.position          = Vector3(0.0, 0.73, 0.78)
	_table_root.add_child(back_mi)

	# ── 旁边椅子（Step 6 时才 visible=true）────────
	_chair_extra         = Node3D.new()
	_chair_extra.name    = "ChairExtra"
	_chair_extra.visible = false
	_table_root.add_child(_chair_extra)

	var ex_seat_mi  := MeshInstance3D.new()
	var ex_seat_box  := BoxMesh.new()
	ex_seat_box.size = Vector3(0.50, 0.05, 0.50)
	ex_seat_mi.mesh              = ex_seat_box
	ex_seat_mi.material_override = chair_mat
	ex_seat_mi.position          = Vector3(0.90, 0.48, 0.55)   # 玩家椅右侧
	_chair_extra.add_child(ex_seat_mi)

	var ex_back_mi  := MeshInstance3D.new()
	var ex_back_box  := BoxMesh.new()
	ex_back_box.size = Vector3(0.50, 0.50, 0.04)
	ex_back_mi.mesh              = ex_back_box
	ex_back_mi.material_override = chair_mat
	ex_back_mi.position          = Vector3(0.90, 0.73, 0.78)
	_chair_extra.add_child(ex_back_mi)

	# ── 屏幕面板 ────────────────────────────────────
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color               = Color(0.05, 0.05, 0.08)
	screen_mat.roughness                  = 0.30
	screen_mat.emission_enabled           = true
	screen_mat.emission                   = Color(0.05, 0.05, 0.08)
	screen_mat.emission_energy_multiplier = 0.0   # 坐下后点亮

	var screen_mi  := MeshInstance3D.new()
	screen_mi.name  = "Screen"
	var screen_box  := BoxMesh.new()
	screen_box.size = Vector3(1.0, 0.62, 0.04)
	screen_mi.mesh              = screen_box
	screen_mi.material_override = screen_mat
	screen_mi.position          = Vector3(0.0, 1.28, -0.28)
	_table_root.add_child(screen_mi)

	# ── SubViewport（Force01 小鹿预览）──────────────
	_screen_vp                       = SubViewport.new()
	_screen_vp.name                  = "ScreenVP"
	_screen_vp.size                  = Vector2i(640, 400)
	_screen_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_table_root.add_child(_screen_vp)
	_setup_viewport_scene()

	# Sprite3D 把 SubViewport 纹理贴到屏幕正面
	var sprite        := Sprite3D.new()
	sprite.name        = "ScreenSprite"
	sprite.texture     = _screen_vp.get_texture()
	sprite.billboard   = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.pixel_size  = 0.00155   # 640px × 0.00155 ≈ 0.99 u，与屏幕面板宽度匹配
	sprite.position    = Vector3(0.0, 1.28, -0.255)
	_table_root.add_child(sprite)

	# ── 桌面摄像机（坐下后激活）────────────────────
	_desk_camera          = Camera3D.new()
	_desk_camera.name     = "DeskCamera"
	_desk_camera.position = Vector3(0.0, 2.8, 2.2)   # 玩家头顶后方，避免卡进模型
	_table_root.add_child(_desk_camera)
	# 俯视屏幕中心
	_desk_camera.look_at(_table_root.to_global(Vector3(0.0, 1.28, -0.28)))

	# ── 靠近提示 Label3D ────────────────────────────
	var hint        := Label3D.new()
	hint.name        = "TableHint"
	hint.text        = "[ Space ] 坐下"
	hint.font_size   = 36
	hint.pixel_size  = 0.004
	hint.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	hint.modulate    = Color(1.0, 0.98, 0.95, 0.0)   # 初始透明
	hint.outline_size = 4
	hint.outline_modulate = Color(0.08, 0.06, 0.05)
	hint.position    = Vector3(0.0, 1.8, 0.0)
	_table_root.add_child(hint)

	# ── Area3D 检测玩家靠近 ─────────────────────────
	var area   := Area3D.new()
	area.name  = "TableArea"
	var cshape := CollisionShape3D.new()
	var sph    := SphereShape3D.new()
	sph.radius  = 2.2
	cshape.shape = sph
	area.add_child(cshape)
	area.body_entered.connect(_on_table_entered)
	area.body_exited.connect(_on_table_exited)
	_table_root.add_child(area)

	print("[variables] 桌子生成完成  local_pos=", base)


# SubViewport 内部场景：小鹿 + 台阶（Force01 预览）
func _setup_viewport_scene() -> void:
	# 环境光
	var world_env  := WorldEnvironment.new()
	var env        := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.9, 0.88, 0.85)
	env.ambient_light_energy = 1.2
	world_env.environment    = env
	_screen_vp.add_child(world_env)

	# 平行光
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	_screen_vp.add_child(light)

	# 摄像机（SubViewport 内部）
	var cam      := Camera3D.new()
	cam.position  = Vector3(2.5, 2.0, 4.0)
	_screen_vp.add_child(cam)   # 先入树
	cam.look_at(Vector3(0.0, 0.5, 0.0))   # 再 look_at

	# 台阶（3 级简单 BoxMesh）
	for s in 3:
		var stair_mat := StandardMaterial3D.new()
		stair_mat.albedo_color = Color(0.74, 0.72, 0.70)
		stair_mat.roughness    = 0.90
		var stair_mi  := MeshInstance3D.new()
		var stair_box  := BoxMesh.new()
		stair_box.size = Vector3(1.4, 0.18, 0.55)
		stair_mi.mesh              = stair_box
		stair_mi.material_override = stair_mat
		stair_mi.position          = Vector3(0.0, s * 0.18, -s * 0.55)
		_screen_vp.add_child(stair_mi)

	# 小鹿模型
	var deer_scene := load("res://models/deer/deer.glb")
	if deer_scene:
		var deer      := deer_scene.instantiate() as Node3D
		deer.name      = "VPDeer"
		deer.scale     = Vector3(0.4, 0.4, 0.4)
		deer.position  = Vector3(0.0, 0.0, 0.0)
		_screen_vp.add_child(deer)
		# 播放鹿动画
		var anim := deer.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim:
			anim.play("Animation")
		# 小鹿缓慢向前移动（循环 Tween）
		_animate_vp_deer(deer)


func _animate_vp_deer(deer: Node3D) -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(deer, "position:z", -1.2, 4.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(deer, "position:z",  0.0, 0.1)   # 瞬移回起点，制造循环感


# BGM 淡入
func _start_bgm() -> void:
	var stream := load("res://music/重生/入海.mp3") as AudioStream
	if stream == null:
		print("[variables] BGM 未加载到，请确认编辑器已导入该文件")
		return
	_bgm            = AudioStreamPlayer.new()
	_bgm.stream     = stream
	_bgm.volume_db  = -80.0
	_bgm.autoplay   = false
	add_child(_bgm)
	_bgm.play()
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: _bgm.volume_db = v,
		-80.0, 0.0, 2.0
	)
	print("[variables] BGM 淡入启动")


# ── 坐下交互 ────────────────────────────────────────

func _on_table_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or _seated:
		return
	_player_near_table = true
	# 提示文字淡入
	var hint := _table_root.get_node_or_null("TableHint") as Label3D
	if hint:
		var tw := create_tween()
		tw.tween_property(hint, "modulate:a", 1.0, 0.4)


func _on_table_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_near_table = false
	var hint := _table_root.get_node_or_null("TableHint") as Label3D
	if hint:
		var tw := create_tween()
		tw.tween_property(hint, "modulate:a", 0.0, 0.4)


func _try_sit_down() -> void:
	if not _player_near_table or _seated:
		return
	_seated = true

	# 隐藏提示
	var hint := _table_root.get_node_or_null("TableHint") as Label3D
	if hint:
		hint.visible = false

	# 冻结玩家 + 播放坐下动作（定格在最后一帧）
	if _player:
		_player.set("frozen", true)
		# play_one_shot keep_pose=true：播完后冻结在坐姿末帧
		_player.call("play_one_shot", "sitting", true)

	# 激活 SubViewport 渲染 + 屏幕发光
	_screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var screen_mi := _table_root.get_node_or_null("Screen") as MeshInstance3D
	var screen_mat := screen_mi.material_override as StandardMaterial3D if screen_mi else null
	if screen_mat:
		var tw_s := create_tween()
		tw_s.tween_method(
			func(v: float) -> void: screen_mat.emission_energy_multiplier = v,
			0.0, 0.6, 0.8
		)

	# 激活桌面摄像机
	if _desk_camera:
		_desk_camera.current = true

	print("[variables] 玩家坐下 → 桌面摄像机激活")
	_begin_step5()   # 作为独立协程启动，不 await


# ═══════════════════════════════════════════════════════
# Step 5 — NPC 群像 + 第五 / 六片环境薄片
# ═══════════════════════════════════════════════════════

func _begin_step5() -> void:
	await get_tree().create_timer(2.0).timeout
	print("[variables] Step 5 开始 — NPC 群像生成中")
	_setup_ambient_slices()
	await _start_npc_spawning()
	# 全部 NPC 出现 → 进入 Step 6，第六片薄片由 Step 6 在合适时机触发
	_begin_step6()


# 预创建第五、六片环境薄片（无文字、不冻结玩家）
func _setup_ambient_slices() -> void:
	var configs := [
		{"color": Color(0.88, 0.91, 0.96), "alpha": AMBIENT_ALPHA_5},
		{"color": Color(0.92, 0.94, 0.98), "alpha": AMBIENT_ALPHA_6},
	]
	for i in 2:
		var node := _make_ambient_slice(i, configs[i])
		node.visible = false
		add_child(node)
		_ambient_slices.append(node)


func _make_ambient_slice(i: int, cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "AmbientSlice_%d" % i

	var mat := StandardMaterial3D.new()
	mat.albedo_color               = cfg["color"]
	mat.albedo_color.a             = cfg["alpha"]
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness                  = 0.85
	mat.emission_enabled           = true
	mat.emission                   = cfg["color"]
	mat.emission_energy_multiplier = 0.01

	var mi  := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size = SLICE_SIZE   # 沿用正片尺寸，填满整个通道宽度
	mi.mesh              = box
	mi.material_override = mat
	mi.position          = Vector3(0.0, SLICE_SIZE.y * 0.5, 0.0)
	root.add_child(mi)

	# Area3D：只检测玩家 body_exited；NPCs 是纯视觉网格，无碰撞体，靠视觉穿透感知
	var area    := Area3D.new()
	area.name   = "AmbientHitArea"
	var cshape  := CollisionShape3D.new()
	var hit_box := BoxShape3D.new()
	hit_box.size    = Vector3(SLICE_SIZE.x, SLICE_SIZE.y, 0.5)
	cshape.shape    = hit_box
	cshape.position = Vector3(0.0, SLICE_SIZE.y * 0.5, 0.0)
	area.add_child(cshape)
	area.monitoring = false   # 激活时再开启
	var idx := i
	area.body_exited.connect(func(body: Node3D) -> void: _on_ambient_exited(idx, body))
	root.add_child(area)

	return root


func _activate_ambient_slice(i: int) -> void:
	if i >= _ambient_slices.size():
		return
	var player_local_z := to_local(_player.global_position).z
	var spawn_z        := player_local_z - AMBIENT_AHEAD
	var end_z          := player_local_z + AMBIENT_BEHIND

	var node := _ambient_slices[i] as Node3D
	node.position.z = spawn_z
	node.visible    = true
	var area := node.get_node_or_null("AmbientHitArea") as Area3D
	if area:
		area.monitoring = true

	var duration := (end_z - spawn_z) / AMBIENT_SPEED
	var tw := create_tween()
	tw.tween_property(node, "position:z", end_z, duration).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: node.visible = false)
	print("[variables] 环境薄片 %d 激活  dur=%.1fs" % [i, duration])


func _on_ambient_exited(i: int, body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if _ambient_hit_flags[i]:
		return
	_ambient_hit_flags[i] = true
	print("[variables] 环境薄片 %d 穿过完成" % i)
	if i == 1:
		# 第六片穿过 → 等待片刻 → 终局演出
		await get_tree().create_timer(3.0).timeout
		_on_step6_done()


# NPC 逐个生成协程（3~6 秒间隔，共 NPC_MAX 个）
func _start_npc_spawning() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in NPC_MAX:
		var wait := rng.randf_range(NPC_SPAWN_INTERVAL_MIN, NPC_SPAWN_INTERVAL_MAX)
		await get_tree().create_timer(wait).timeout
		_spawn_npc(i, rng)
		# 第五个 NPC（索引 4）出现后，激活第五片环境薄片
		if i == 4:
			await get_tree().create_timer(1.5).timeout
			_activate_ambient_slice(0)
	print("[variables] 全部 NPC（%d 个）出现完毕" % NPC_MAX)


func _spawn_npc(i: int, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "NPC_%d" % i

	# 在 Force08 本地坐标系中，相对桌子的偏移
	var npc_offset := NPC_POSITIONS[i] as Vector3
	root.position   = _table_root.position + npc_offset
	add_child(root)

	# 面朝桌子
	var table_global := to_global(_table_root.position)
	if root.global_position.distance_to(table_global) > 0.01:
		root.look_at(table_global)

	# ── 抽象人形：躯干 + 头（共用材质，一起淡入）──
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.16, 0.15, 0.18, 0.0)   # 初始全透明
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.roughness    = 0.90

	var body_mi  := MeshInstance3D.new()
	var body_box  := BoxMesh.new()
	body_box.size = Vector3(0.35, 0.85, 0.20)
	body_mi.mesh              = body_box
	body_mi.material_override = body_mat
	body_mi.position          = Vector3(0.0, 0.95, 0.0)
	root.add_child(body_mi)

	var head_mi  := MeshInstance3D.new()
	var head_sph  := SphereMesh.new()
	head_sph.radius = 0.16
	head_sph.height = 0.32
	head_mi.mesh              = head_sph
	head_mi.material_override = body_mat   # 共用材质，alpha 同步
	head_mi.position          = Vector3(0.0, 1.53, 0.0)
	root.add_child(head_mi)

	# ── 四种画卷类型，按索引循环分配 ──────────────
	var canvas_type := i % 4   # 0=画布  1=屏幕  2=乐谱  3=发光结构
	_add_canvas_to_npc(root, canvas_type, rng, NPC_CANVAS_COLORS[i])

	# 淡入 alpha 0 → 0.80
	var tw := create_tween()
	tw.tween_method(
		func(a: float) -> void: body_mat.albedo_color.a = a,
		0.0, 0.80, 1.5
	)
	_npcs.append(root)
	print("[variables] NPC %d 出现  类型=%d" % [i, canvas_type])


func _add_canvas_to_npc(npc_root: Node3D, type: int, rng: RandomNumberGenerator, canvas_color: Color) -> void:
	# 画卷放在 NPC 正前方（NPC 本地 -Z = 朝向桌子方向）略偏侧
	# canvas_color 为该 NPC 专属颜色，各不相同
	match type:

		0:  # 画布（画架 + 彩色画板）
			var canvas_mat := StandardMaterial3D.new()
			canvas_mat.albedo_color = canvas_color.lightened(0.15)
			canvas_mat.roughness    = 0.85
			canvas_mat.emission_enabled           = true
			canvas_mat.emission                   = canvas_color
			canvas_mat.emission_energy_multiplier = 0.08
			var mi  := MeshInstance3D.new()
			var box  := BoxMesh.new()
			box.size = Vector3(0.52, 0.62, 0.025)
			mi.mesh              = box
			mi.material_override = canvas_mat
			mi.position          = Vector3(0.28, 1.10, -0.30)
			npc_root.add_child(mi)
			# 画架竖杆（中性木色）
			var stand_mat := StandardMaterial3D.new()
			stand_mat.albedo_color = Color(0.60, 0.55, 0.46)
			stand_mat.roughness    = 0.90
			var stand_mi  := MeshInstance3D.new()
			var stand_box  := BoxMesh.new()
			stand_box.size = Vector3(0.025, 0.88, 0.025)
			stand_mi.mesh              = stand_box
			stand_mi.material_override = stand_mat
			stand_mi.position          = Vector3(0.28, 0.48, -0.30)
			npc_root.add_child(stand_mi)

		1:  # 屏幕（彩色发光面板）
			var mat := StandardMaterial3D.new()
			mat.albedo_color               = canvas_color.darkened(0.80)   # 暗底
			mat.emission_enabled           = true
			mat.emission                   = canvas_color
			mat.emission_energy_multiplier = 0.65
			mat.roughness                  = 0.15
			var mi  := MeshInstance3D.new()
			var box  := BoxMesh.new()
			box.size = Vector3(0.60, 0.38, 0.030)
			mi.mesh              = box
			mi.material_override = mat
			mi.position          = Vector3(-0.32, 1.08, -0.30)
			npc_root.add_child(mi)

		2:  # 乐谱（彩色线条纸，轻微旋转）
			var mat := StandardMaterial3D.new()
			# 白底 + 彩色淡染
			mat.albedo_color = canvas_color.lightened(0.72)
			mat.roughness    = 0.95
			mat.emission_enabled           = true
			mat.emission                   = canvas_color
			mat.emission_energy_multiplier = 0.04
			var mi  := MeshInstance3D.new()
			var box  := BoxMesh.new()
			box.size = Vector3(0.36, 0.50, 0.005)
			mi.mesh              = box
			mi.material_override = mat
			mi.position          = Vector3(0.22, 1.05, -0.30)
			mi.rotation_degrees.z = rng.randf_range(-10.0, 10.0)
			npc_root.add_child(mi)

		3:  # 发光结构（三根同色系彩光柱，明度递变）
			for j in 3:
				var shift := j * 0.08 - 0.08   # -0.08 / 0 / +0.08
				var col   := canvas_color.lightened(shift) if shift >= 0 else canvas_color.darkened(-shift)
				var mat := StandardMaterial3D.new()
				mat.albedo_color               = col
				mat.emission_enabled           = true
				mat.emission                   = col
				mat.emission_energy_multiplier = 0.32 + j * 0.10
				var mi  := MeshInstance3D.new()
				var box  := BoxMesh.new()
				box.size = Vector3(0.055, 0.42 - j * 0.06, 0.055)
				mi.mesh              = box
				mi.material_override = mat
				mi.position          = Vector3(0.18 + j * 0.10, 0.90 + j * 0.12, -0.30)
				mi.rotation_degrees.x = rng.randf_range(-20.0, 20.0)
				npc_root.add_child(mi)


# ═══════════════════════════════════════════════════════
# Step 6 — 终局演出
# ═══════════════════════════════════════════════════════

func _begin_step6() -> void:
	print("[variables] Step 6 开始 → 第六片薄片即将出现")
	# 稍等片刻，让玩家感知到「大家都到了」的静默
	await get_tree().create_timer(4.0).timeout
	_activate_ambient_slice(1)   # 第六片：最轻薄，穿透所有人与 NPC


func _on_step6_done() -> void:
	print("[variables] Step 6 终局演出开始")

	# 旁边椅子无声出现（镜头拉远后才被看见）
	if _chair_extra:
		_chair_extra.visible = true

	# 极远处静态薄片（装饰性轮廓，alpha=0.06，不移动）
	_spawn_distant_slice()

	# 等片刻 → 同伴 NPC 无声落座
	await get_tree().create_timer(1.5).timeout
	_spawn_companion_npc()

	# 再等片刻 → 镜头开始缓缓拉远
	await get_tree().create_timer(1.5).timeout
	_start_camera_pullback()


# ── 极远处静止薄片（终局装饰，仿佛下一个时刻尚未抵达）──────
func _spawn_distant_slice() -> void:
	var root := Node3D.new()
	root.name = "DistantSlice"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.96, 0.97, 0.06)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness    = 0.85

	var mi  := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size = SLICE_SIZE
	mi.mesh              = box
	mi.material_override = mat
	mi.position          = Vector3(0.0, SLICE_SIZE.y * 0.5, 0.0)
	root.add_child(mi)

	# 桌子前方 160 u，固定不动
	root.position = _table_root.position + Vector3(0.0, 0.0, -160.0)
	add_child(root)
	print("[variables] 远方薄片已放置")


# ── 同伴 NPC：无画卷，面朝屏幕，坐在旁边椅子旁 ─────────────
func _spawn_companion_npc() -> void:
	var root := Node3D.new()
	root.name = "CompanionNPC"

	# 旁边椅子在 table_root 本地 (0.90, 0, 0.55)
	root.position = _table_root.position + Vector3(0.90, 0.0, 0.55)
	add_child(root)
	# 不做 look_at，直立放置即可（Force08 -Z 方向正好朝向桌子/屏幕）

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.16, 0.20, 0.0)   # 初始全透明
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.roughness    = 0.90

	var body_mi  := MeshInstance3D.new()
	var body_box  := BoxMesh.new()
	body_box.size = Vector3(0.35, 0.85, 0.20)
	body_mi.mesh              = body_box
	body_mi.material_override = body_mat
	body_mi.position          = Vector3(0.0, 0.95, 0.0)
	root.add_child(body_mi)

	var head_mi  := MeshInstance3D.new()
	var head_sph  := SphereMesh.new()
	head_sph.radius = 0.16
	head_sph.height = 0.32
	head_mi.mesh              = head_sph
	head_mi.material_override = body_mat
	head_mi.position          = Vector3(0.0, 1.53, 0.0)
	root.add_child(head_mi)

	# 淡入 0 → 0.85，2.5s
	var tw := create_tween()
	tw.tween_method(
		func(a: float) -> void: body_mat.albedo_color.a = a,
		0.0, 0.85, 2.5
	)
	print("[variables] 同伴 NPC 落座")


# ── 镜头缓缓拉远：俯视整个群像构图（12~15s）────────────────
func _start_camera_pullback() -> void:
	if _desk_camera == null:
		return

	var pull_start := _desk_camera.global_position
	# 终点：桌子正上方偏后，俯视全场
	var pull_end   := _table_root.to_global(Vector3(0.0, 18.0, 35.0))
	# look_at 目标：从屏幕中心线性插值到群像中心
	var look_start := _table_root.to_global(Vector3(0.0, 1.28, -0.28))
	var look_end   := _table_root.to_global(Vector3(0.0, 1.0, -4.0))

	var pull_fn := func(t: float) -> void:
		_desk_camera.global_position = pull_start.lerp(pull_end, t)
		var tgt := look_start.lerp(look_end, t)
		if _desk_camera.global_position.distance_to(tgt) > 0.01:
			_desk_camera.look_at(tgt)

	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_method(pull_fn, 0.0, 1.0, 14.0)
	print("[variables] 终局镜头拉远启动  14s")

	# 等镜头到位，静止几秒，再刷新玩家到 Force1 起点
	await tw.finished
	await get_tree().create_timer(4.0).timeout
	_respawn_at_force1()


func _respawn_at_force1() -> void:
	print("[variables] 终局结束 → 刷新至 Force1 起点")
	if _desk_camera:
		_desk_camera.current = false   # 归还摄像机控制权
	if _player:
		# 释放 keep_pose 锁定的 _one_shot_active，否则 _update_animation 永远跳过
		_player.set("_one_shot_active", false)
		_player.call("reset_to", Vector3(-4.0, 2.0, 0.0))   # Force1 真正起点（含 frozen=false）
