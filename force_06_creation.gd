extends Node3D

# Force 06 — Creation（创造）
# Step 1：全量数据定义
# Step 2：锚点生成与玩家检测

# ═══════════════════════════════════════════════════════
# Step 1 — 常量与数据
# ═══════════════════════════════════════════════════════

# ── 锚点系统参数 ──────────────────────────────────────
const ANCHOR_RADIUS     := 0.65   # 触发半径（米），设计书建议 0.5~0.8 取中值
const ANCHOR_VIS_RADIUS := 0.20   # 可视球体半径
const ANCHOR_PULSE_SLOW := 0.5    # 即将触发锚点的脉冲频率（Hz）
const ANCHOR_PULSE_FAST := 1.5    # 当前活跃锚点的脉冲频率（Hz）

# ── 各曲目绘画区局部偏移（相对于本 Node3D，X 轴横向排开）──
const SONG_OFFSETS: Array[Vector3] = [
	Vector3(-30.0, 0.0, 0.0),  # Promise
	Vector3(-10.0, 0.0, 0.0),  # Lemon
	Vector3( 10.0, 0.0, 0.0),  # 我心翱翔
	Vector3( 30.0, 0.0, 0.0),  # 大教堂时代
]

# ── 线条视觉参数（随乐层变化）────────────────────────
const STROKE_COLORS: Array[Color] = [
	Color(0.90, 0.90, 1.00),  # 笔1 伴奏：细冷白
	Color(1.00, 0.95, 0.80),  # 笔2 +吉他：淡暖金
	Color(1.00, 0.90, 0.70),  # 笔3 +钢琴：柔暖白
	Color(1.00, 0.70, 0.30),  # 笔4 +人声：暖橙发光
]
const STROKE_GLOW: Array[float] = [0.30, 0.60, 0.90, 1.80]

# ── 完成序列时长（秒）────────────────────────────────
const PHOTO_FADE_IN_DUR  := 3.5
const PHOTO_FADE_OUT_DUR := 3.5
const QUOTE_FADE_DUR     := 1.0
const QUOTE_HOLD_DUR     := 3.0
const SILENCE_DUR        := 1.5

# ── 曲目数据（SONGS）─────────────────────────────────
# strokes 结构：Array[Array[Array[Vector2]]]
#   外层：4 笔
#   中层：该笔的段落列表（不连续笔画有多个段）
#   内层：该段落的锚点局部坐标（单位：米，原点为该曲区中心）
# 局部坐标 → 世界坐标：_to_world(song_idx, local_pos)

const SONGS: Array = [
	# ── 0. Promise（寂静岭）—— 脸 ────────────────────────────────
	{
		"name":      "promise",
		"music_dir": "res://music/promise/",
		"picture":   "res://picture/promise.jpg",
		"quote":     "有些遗忘，只是在等一双手把它重新描出来",
		"accessory": "collar",
		"strokes": [
			# 笔1 伴奏：脸部轮廓椭圆（单段，闭合）
			[[
				Vector2( 0.0,  2.6), Vector2( 1.7,  1.3), Vector2( 1.7, -1.3),
				Vector2( 0.0, -2.6), Vector2(-1.7, -1.3), Vector2(-1.7,  1.3),
				Vector2( 0.0,  2.6),
			]],
			# 笔2 +吉他：肩颈线，左右两段不连续
			[
				[Vector2(-1.5, -2.6), Vector2(-2.5, -4.5)],  # 左肩
				[Vector2( 1.5, -2.6), Vector2( 2.5, -4.5)],  # 右肩
			],
			# 笔3 +钢琴：眼位（暗）+ 鼻线（单段）
			[[
				Vector2(-0.8,  0.5), Vector2( 0.8,  0.5),
				Vector2( 0.0,  0.0), Vector2( 0.0, -0.6),
			]],
			# 笔4 +人声：实心双眼 + 微笑弧线（单段）
			[[
				Vector2(-0.8,  0.5), Vector2( 0.8,  0.5),
				Vector2(-1.0, -1.2), Vector2( 0.0, -1.6), Vector2(1.0, -1.2),
			]],
		],
	},
	# ── 1. Lemon（米津玄师）—— 柠檬 ──────────────────────────────
	{
		"name":      "lemon",
		"music_dir": "res://music/lemon/",
		"picture":   "res://picture/lemon.jpg",
		"quote":     "苦涩没有消失，只是被酿成了回甘",
		"accessory": "sleeve",
		"strokes": [
			# 笔1 伴奏：树枝主干（单段）
			[[Vector2(-1.5, 1.5), Vector2(0.0, 0.0), Vector2(1.5, -1.5)]],
			# 笔2 +吉他：两片叶子（单段）
			[[
				Vector2(0.3,  0.3), Vector2(1.5,  0.9),
				Vector2(0.6, -0.2), Vector2(1.8,  0.3),
			]],
			# 笔3 +钢琴：柠檬轮廓空心（单段，闭合）
			[[
				Vector2(1.7,  0.0), Vector2(3.1, -1.8),
				Vector2(1.7, -3.6), Vector2(0.3, -1.8),
				Vector2(1.7,  0.0),
			]],
			# 笔4 +人声：果皮光泽 / 高光（单段）
			[[
				Vector2(1.2, -1.2), Vector2(1.7,  0.0),
				Vector2(2.4, -1.0), Vector2(1.0, -1.0),
			]],
		],
	},
	# ── 2. 我心翱翔（SNH48）—— 鸟 ────────────────────────────────
	{
		"name":      "我心翱翔",
		"music_dir": "res://music/我心翱翔/",
		"picture":   "res://picture/我心翱翔.jpg",
		"quote":     "翅膀不是被给予的，是自己一笔一笔画出来的",
		"accessory": "hairpin",
		"strokes": [
			# 笔1 伴奏：躯干椭圆（单段，闭合）
			[[
				Vector2( 1.8,  0.0), Vector2( 0.0,  1.0),
				Vector2(-1.8,  0.0), Vector2( 0.0, -1.0),
				Vector2( 1.8,  0.0),
			]],
			# 笔2 +吉他：左翼（单段）
			[[Vector2(-1.5,  0.3), Vector2(-3.2,  1.5), Vector2(-1.5, -0.5)]],
			# 笔3 +钢琴：右翼（单段）
			[[Vector2( 1.5,  0.3), Vector2( 3.2,  1.5), Vector2( 1.5, -0.5)]],
			# 笔4 +人声：动态尾迹（单段）
			[[
				Vector2(-1.3, -0.8), Vector2(-2.5, -1.5),
				Vector2(-1.3, -1.3), Vector2(-2.8, -2.2),
			]],
		],
	},
	# ── 3. 大教堂时代（巴黎圣母院音乐剧）—— 教堂 ────────────────
	{
		"name":      "大教堂时代",
		"music_dir": "res://music/大教堂时代/",
		"picture":   "res://picture/大教堂时代.jpg",
		"quote":     "有些创造，活得比创造者更久",
		"accessory": "necklace",
		"strokes": [
			# 笔1 伴奏：地基矩形（单段，闭合）
			[[
				Vector2(-1.5, -1.5), Vector2( 1.5, -1.5),
				Vector2( 1.5,  0.5), Vector2(-1.5,  0.5),
				Vector2(-1.5, -1.5),
			]],
			# 笔2 +吉他：立柱与墙体（单段，玩家自由穿行各列）
			[[
				Vector2(-1.5,  2.5), Vector2( 1.5,  2.5),
				Vector2(-0.5, -1.5), Vector2(-0.5,  2.5),
				Vector2( 0.5, -1.5), Vector2( 0.5,  2.5),
			]],
			# 笔3 +钢琴：尖顶 / 塔楼三角（单段）
			[[Vector2(-1.7, 2.5), Vector2(0.0, 4.5), Vector2(1.7, 2.5)]],
			# 笔4 +人声：玫瑰花窗 + 塔顶十字（单段）
			[[
				Vector2( 0.0, 1.0), Vector2( 0.0, 4.5), Vector2( 0.0, 5.5),
				Vector2(-0.5, 5.0), Vector2( 0.5, 5.0),
			]],
		],
	},
]

# ═══════════════════════════════════════════════════════
# 运行时变量
# ═══════════════════════════════════════════════════════

var _current_song:   int        = 0
var _current_stroke: int        = 0
var _next_anchor:    int        = 0      # 展平序号，当前笔中下一个待触发的锚点
var _soft_locked:    bool       = false
var _song_complete:  Array[bool] = [false, false, false, false]

var _player: Node3D

# [s][k] = Array[Area3D]
var _anchors: Array = []

# [s][k] = Array[MeshInstance3D]，与 _anchors 同构
var _anchor_meshes: Array = []

# [s][k] = Array[Vector3]，已触发锚点的世界坐标（供线条渲染用）
var _drawn_points: Array = []

# [s][k] = MeshInstance3D，Step 5 填充
var _line_meshes: Array = []

# [s][k] = AudioStream，Step 3 填充
var _music_streams: Array = []

var _music_player: AudioStreamPlayer

# ── Step 6 UI 节点 ────────────────────────────────────
var _ui_layer:    CanvasLayer = null
var _photo_rect:  TextureRect = null
var _quote_flash: ColorRect   = null   # 白屏底（与 costume_ui 同一套）
var _quote_label: Label       = null
var _tween_quote_flash: Tween = null   # 用于中断上一次动画
var _tween_quote_text:  Tween = null


# ═══════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════

func _ready() -> void:
	_find_player()
	_init_runtime_arrays()
	_setup_song_areas()
	_setup_line_meshes()
	_setup_music_player()
	_load_all_music()
	_create_ui_layer()
	print("[creation] ready")



func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		push_warning("[creation] player not found")


func _init_runtime_arrays() -> void:
	_anchors.resize(SONGS.size())
	_anchor_meshes.resize(SONGS.size())
	_drawn_points.resize(SONGS.size())
	_line_meshes.resize(SONGS.size())
	_music_streams.resize(SONGS.size())

	for s in SONGS.size():
		var stroke_count: int = (SONGS[s].strokes as Array).size()
		_anchors[s]       = []
		_anchor_meshes[s] = []
		_drawn_points[s]  = []
		_line_meshes[s]   = []
		_music_streams[s] = []

		_anchors[s].resize(stroke_count)
		_anchor_meshes[s].resize(stroke_count)
		_drawn_points[s].resize(stroke_count)
		_line_meshes[s].resize(stroke_count)
		_music_streams[s].resize(stroke_count)

		for k in stroke_count:
			_anchors[s][k]       = []
			_anchor_meshes[s][k] = []
			_drawn_points[s][k]  = []
			_line_meshes[s][k]   = null
			_music_streams[s][k] = null


# ═══════════════════════════════════════════════════════
# Step 3 — 音乐加载与分层播放
# ═══════════════════════════════════════════════════════

func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)


# 扫描各曲目目录，按数字前缀（1_/2_/3_/4_）排序加载 4 层音频流
func _load_all_music() -> void:
	for s in SONGS.size():
		var dir_path: String = SONGS[s].music_dir
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_warning("[creation] 音乐目录不存在: %s" % dir_path)
			continue

		# 收集所有音频文件（排除 .import 元文件）
		var files: Array[String] = []
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and not fname.ends_with(".import"):
				var ext := fname.get_extension().to_lower()
				if ext in ["ogg", "wav", "mp3"]:
					files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()

		# 按文件名排序，1_xxx < 2_xxx < 3_xxx < 4_xxx
		files.sort()

		var loaded := 0
		for f in files:
			if loaded >= 4:
				break
			var stream := load(dir_path + f) as AudioStream
			if stream:
				_music_streams[s][loaded] = stream
				loaded += 1

		print("[creation] song=%d (%s) 加载音乐 %d/4" % [s, SONGS[s].name, loaded])


# ═══════════════════════════════════════════════════════
# Step 5 — 线条渲染（ImmediateMesh）
# ═══════════════════════════════════════════════════════

# 为每笔预建 MeshInstance3D，挂到 Creation 节点下（位置 = Zero，与本节点同坐标系）
func _setup_line_meshes() -> void:
	for s in SONGS.size():
		for k in 4:
			var mi := MeshInstance3D.new()
			mi.name             = "Line_%d_%d" % [s, k]
			mi.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.material_override = _make_line_material(k)
			add_child(mi)
			_line_meshes[s][k] = mi


# 每笔独立材质：颜色与发光强度随乐层递进
func _make_line_material(stroke_idx: int) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4  line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow       : hint_range(0.0, 5.0) = 1.0;
void fragment() {
	ALBEDO = line_color.rgb * glow;
	ALPHA  = line_color.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("line_color", STROKE_COLORS[stroke_idx])
	mat.set_shader_parameter("glow",       STROKE_GLOW[stroke_idx])
	return mat


# 根据 _drawn_points[s][k] 重建该笔的 ImmediateMesh
# 不连续段（如 Promise 笔2 左右肩）分别绘制独立 LINE_STRIP
func _update_stroke_line(s: int, k: int) -> void:
	var mi := _line_meshes[s][k] as MeshInstance3D
	if mi == null:
		return

	var points: Array = _drawn_points[s][k] as Array
	if points.size() < 2:
		return

	var seg_sizes := _get_segment_sizes(s, k)
	var im        := ImmediateMesh.new()
	var pt_idx    := 0

	for seg_size in seg_sizes:
		var remaining := points.size() - pt_idx
		var available := mini(seg_size, remaining)

		if available >= 2:
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for j in available:
				im.surface_add_vertex(to_local(points[pt_idx + j] as Vector3))
			im.surface_end()

		pt_idx += available
		if pt_idx >= points.size():
			break

	mi.mesh = im


# 返回指定笔各段落的锚点数量列表，用于拆分 drawn_points 到各段
func _get_segment_sizes(s: int, k: int) -> Array[int]:
	var sizes: Array[int] = []
	for seg in (_get_segments(s, k) as Array):
		sizes.append((seg as Array).size())
	return sizes


# ═══════════════════════════════════════════════════════
# Step 2 — 锚点生成与检测
# ═══════════════════════════════════════════════════════

func _setup_song_areas() -> void:
	for s in SONGS.size():
		var song_node := Node3D.new()
		song_node.name = "Song_%d_%s" % [s, SONGS[s].name]
		song_node.position = SONG_OFFSETS[s]
		add_child(song_node)

		var strokes := SONGS[s].strokes as Array
		for k in strokes.size():
			var flat := _get_flat_anchors(s, k)
			var area_list: Array = []
			var mesh_list: Array = []

			for i in flat.size():
				var pair := _make_anchor(s, k, i, flat[i])
				song_node.add_child(pair[0])
				area_list.append(pair[0])
				mesh_list.append(pair[1])

			_anchors[s][k]       = area_list
			_anchor_meshes[s][k] = mesh_list

	_refresh_anchor_states()


# 创建单个锚点，返回 [Area3D, MeshInstance3D]
# local_pos 为相对于曲目 Song 节点（SONG_OFFSETS[s]）的平面坐标
func _make_anchor(s: int, k: int, i: int, local_pos: Vector2) -> Array:
	var area := Area3D.new()
	area.name       = "Anchor_%d_%d_%d" % [s, k, i]
	area.monitoring = false   # _refresh_anchor_states() 控制，默认关闭

	# 碰撞体
	var col    := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = ANCHOR_RADIUS
	col.shape     = sphere
	area.add_child(col)

	# 可视球体
	var mesh_inst   := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = ANCHOR_VIS_RADIUS
	sphere_mesh.height = ANCHOR_VIS_RADIUS * 2.0
	mesh_inst.mesh = sphere_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color             = STROKE_COLORS[k]
	mat.emission_enabled         = true
	mat.emission                 = STROKE_COLORS[k]
	mat.emission_energy_multiplier = 1.0
	mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override  = mat
	area.add_child(mesh_inst)

	# 位置：局部坐标相对于 Song 节点，Y=0.1 略微抬离地面
	area.position = Vector3(local_pos.x, 0.1, local_pos.y)

	area.body_entered.connect(_on_anchor_entered.bind(s, k, i))

	return [area, mesh_inst]


# 玩家进入锚点触发区
func _on_anchor_entered(body: Node3D, s: int, k: int, i: int) -> void:
	if not body.is_in_group("player"):
		return
	# 双重保险：monitoring 已控制，此处再检查一次
	if s != _current_song or k != _current_stroke or i != _next_anchor:
		return
	if _soft_locked:
		return

	# 记录世界坐标并立即更新线条
	var flat := _get_flat_anchors(s, k)
	(_drawn_points[s][k] as Array).append(_to_world(s, flat[i]))
	_update_stroke_line(s, k)

	_next_anchor += 1
	var anchor_count: int = (_anchors[s][k] as Array).size()

	print("[creation] ✓ song=%d stroke=%d anchor=%d/%d" % [s, k, i + 1, anchor_count])

	if _next_anchor >= anchor_count:
		_on_stroke_complete(s, k)
	else:
		_refresh_anchor_states()


# 当前笔全部锚点触发完成 → 播放对应层音乐 → finished 后解锁
func _on_stroke_complete(s: int, k: int) -> void:
	_soft_locked = true
	_refresh_anchor_states()
	print("[creation] 笔完成 song=%d stroke=%d → 播放音乐层 %d" % [s, k, k + 1])

	var stream: AudioStream = _music_streams[s][k]
	if stream:
		_music_player.stream = stream
		_music_player.play()
		_music_player.finished.connect(func(): _on_music_finished(s, k), CONNECT_ONE_SHOT)
	else:
		# 音乐文件缺失时 fallback：2 秒后自动解锁，不中断流程
		push_warning("[creation] 无音乐流 song=%d stroke=%d，2s 后自动解锁" % [s, k])
		get_tree().create_timer(2.0).timeout.connect(
			func(): _on_music_finished(s, k), CONNECT_ONE_SHOT
		)


# 音乐播放完毕 → 解除软锁，推进到下一笔（或标记曲目完成）
func _on_music_finished(s: int, k: int) -> void:
	_soft_locked = false
	if k + 1 < 4:
		_current_stroke = k + 1
		_next_anchor    = 0
		_refresh_anchor_states()
		print("[creation] 下一笔激活 song=%d stroke=%d" % [s, k + 1])
	else:
		_song_complete[s] = true
		_refresh_anchor_states()
		print("[creation] 曲目完成 song=%d → 启动 Step 6 完成序列" % s)
		_song_ending_sequence(s)


# ─── 状态刷新：更新所有锚点的 monitoring 与初始可视状态 ───
func _refresh_anchor_states() -> void:
	for s in SONGS.size():
		for k in (_anchors[s] as Array).size():
			var area_list: Array = _anchors[s][k] as Array
			var mesh_list: Array = _anchor_meshes[s][k] as Array
			for i in area_list.size():
				var area := area_list[i] as Area3D
				var mesh := mesh_list[i] as MeshInstance3D
				var state := _get_anchor_state(s, k, i)
				match state:
					1:  # ACTIVE：开启检测，可见，高亮（_process 驱动脉冲）
						area.set_deferred("monitoring", true)
						mesh.visible    = true
						(mesh.material_override as StandardMaterial3D)\
							.emission_energy_multiplier = 2.0
					2:  # UPCOMING：关闭检测，可见但暗淡（_process 驱动慢脉冲）
						area.set_deferred("monitoring", false)
						mesh.visible    = true
						(mesh.material_override as StandardMaterial3D)\
							.emission_energy_multiplier = 0.4
					_:  # DONE / LOCKED：关闭检测，不可见
						area.set_deferred("monitoring", false)
						mesh.visible    = false


# 返回锚点当前状态
# 1=ACTIVE（下一个待触发）  2=UPCOMING（当前笔后续）
# 0=DONE（已触发）         3=LOCKED（其他笔/曲目或软锁中）
func _get_anchor_state(s: int, k: int, i: int) -> int:
	if s != _current_song:
		return 3
	if _song_complete[s]:
		return 0
	if k < _current_stroke:
		return 0
	if k > _current_stroke:
		return 3
	# k == _current_stroke
	if i < _next_anchor:
		return 0
	if _soft_locked:
		return 3
	if i == _next_anchor:
		return 1
	return 2


# ─── 每帧：驱动锚点发光脉冲 ─────────────────────────────
func _process(_delta: float) -> void:
	if _player == null or _soft_locked:
		return

	var t   := Time.get_ticks_msec() * 0.001
	var s   := _current_song
	var k   := _current_stroke

	if s >= SONGS.size():
		return

	var mesh_list: Array = _anchor_meshes[s][k] as Array
	for i in mesh_list.size():
		var mesh := mesh_list[i] as MeshInstance3D
		if not mesh.visible:
			continue
		var mat := mesh.material_override as StandardMaterial3D
		if mat == null:
			continue

		if i == _next_anchor:
			# 活跃锚点：快速脉冲，能量 1.2 ~ 3.0
			var pulse := (sin(t * ANCHOR_PULSE_FAST * TAU) + 1.0) * 0.5
			mat.emission_energy_multiplier = lerp(1.2, 3.0, pulse)
		else:
			# 即将到来的锚点：慢速脉冲，能量 0.2 ~ 0.6
			var pulse := (sin(t * ANCHOR_PULSE_SLOW * TAU + float(i)) + 1.0) * 0.5
			mat.emission_energy_multiplier = lerp(0.2, 0.6, pulse)


# ═══════════════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════════════

# 局部坐标 → 世界坐标
# local_pos(x, y) 对应设计书俯视坐标系，映射到 3D 的 XZ 平面
func _to_world(song_idx: int, local_pos: Vector2) -> Vector3:
	return global_position + SONG_OFFSETS[song_idx] + Vector3(local_pos.x, 0.0, local_pos.y)


# 返回指定笔的展平锚点列表（跨段落合并，保留顺序）
func _get_flat_anchors(song_idx: int, stroke_idx: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var segments := SONGS[song_idx].strokes[stroke_idx] as Array
	for seg in segments:
		for pt in (seg as Array):
			result.append(pt as Vector2)
	return result


# 返回指定笔的段落列表（供 Step 5 线条渲染跳过不连续段）
func _get_segments(song_idx: int, stroke_idx: int) -> Array:
	return SONGS[song_idx].strokes[stroke_idx] as Array


# ═══════════════════════════════════════════════════════
# Step 6 — 曲目完成序列
# ═══════════════════════════════════════════════════════

# 创建 CanvasLayer 承载剧照与短句（在 3D 世界上方叠加）
func _create_ui_layer() -> void:
	_ui_layer       = CanvasLayer.new()
	_ui_layer.name  = "CreationUI"
	_ui_layer.layer = 10          # 高于默认 UI 层
	add_child(_ui_layer)

	# ── 剧照矩形（全屏，保持比例居中，默认不可见）──────────
	_photo_rect             = TextureRect.new()
	_photo_rect.name        = "PhotoRect"
	_photo_rect.anchor_right  = 1.0
	_photo_rect.anchor_bottom = 1.0
	_photo_rect.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo_rect.modulate.a    = 0.0
	_ui_layer.add_child(_photo_rect)

	# ── 白屏底（与 costume_ui 相同，短句浮现时使用）──────
	_quote_flash             = ColorRect.new()
	_quote_flash.name        = "QuoteFlash"
	_quote_flash.color       = Color(1.0, 1.0, 1.0, 0.0)
	_quote_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quote_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_quote_flash)

	# ── 短句标签（全屏居中，深褐色，与 costume_ui 一致）──
	_quote_label             = Label.new()
	_quote_label.name        = "QuoteLabel"
	_quote_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_quote_label.add_theme_font_size_override("font_size", 28)
	_quote_label.add_theme_color_override("font_color", Color(0.25, 0.12, 0.05, 1.0))
	_quote_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quote_label.modulate     = Color(1.0, 1.0, 1.0, 0.0)
	_ui_layer.add_child(_quote_label)


# 8 节点完成序列（协程，fire-and-forget 调用）
func _song_ending_sequence(s: int) -> void:
	# ── 节点 1：线稿定格（已由 _refresh_anchor_states 完成）

	# ── 节点 2：剧照淡入（3.5 s）
	# 注：当前为全屏淡入；遮罩效果（线稿轮廓 clip）待后续 shader 实现
	var tex := load(SONGS[s].picture) as Texture2D
	if tex:
		_photo_rect.texture = tex
	var tw_in := create_tween()
	tw_in.tween_property(_photo_rect, "modulate:a", 0.72, PHOTO_FADE_IN_DUR)
	await tw_in.finished

	# ── 节点 3：停留欣赏 —— 重播人声版，剧照维持至音乐结束
	var vocal: AudioStream = _music_streams[s][3]
	if vocal:
		_music_player.stream = vocal
		_music_player.play()
		await _music_player.finished
	else:
		await get_tree().create_timer(5.0).timeout   # fallback

	# ── 节点 4：剧照淡出（3.5 s）
	var tw_out := create_tween()
	tw_out.tween_property(_photo_rect, "modulate:a", 0.0, PHOTO_FADE_OUT_DUR)
	await tw_out.finished

	# ── 节点 5：短句浮现（淡入 1 s → 停留 3 s → 淡出 1 s）
	await _show_quote(SONGS[s].quote as String)

	# ── 节点 6：配饰变化
	_trigger_accessory_change(s)

	# ── 节点 7：静默留白（1.5 s）
	await get_tree().create_timer(SILENCE_DUR).timeout

	# ── 节点 8：推进到下一首歌
	_advance_to_next_song(s)


# 短句浮现协程（与 costume_ui 相同样式）
# 白屏渐入 → 深褐色文字同步浮现 → 停留 → 白屏+文字同步淡出
func _show_quote(text: String) -> void:
	# 打断上一次未完成的动画
	if _tween_quote_flash and _tween_quote_flash.is_running():
		_tween_quote_flash.kill()
	if _tween_quote_text and _tween_quote_text.is_running():
		_tween_quote_text.kill()
	_quote_flash.color.a  = 0.0
	_quote_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	_quote_label.text = text

	# 白屏底：渐入 → 停留 → 渐出
	_tween_quote_flash = create_tween()
	_tween_quote_flash.tween_property(_quote_flash, "color:a", 1.0, QUOTE_FADE_DUR)
	_tween_quote_flash.tween_interval(QUOTE_HOLD_DUR)
	_tween_quote_flash.tween_property(_quote_flash, "color:a", 0.0, QUOTE_FADE_DUR)

	# 文字：与白屏同步
	_tween_quote_text = create_tween()
	_tween_quote_text.tween_property(_quote_label, "modulate:a", 1.0, QUOTE_FADE_DUR)
	_tween_quote_text.tween_interval(QUOTE_HOLD_DUR)
	_tween_quote_text.tween_property(_quote_label, "modulate:a", 0.0, QUOTE_FADE_DUR)

	# 等待白屏动画结束（文字与其同步，无需单独等待）
	await _tween_quote_flash.finished


# 配饰变化：通过 CostumeManager → wardrobe 显示对应配饰
# creation_3（大教堂时代）完成时 wardrobe 内部会自动触发四件共鸣发光
func _trigger_accessory_change(s: int) -> void:
	var mgr := get_tree().root.find_child("CostumeManager", true, false)
	if mgr:
		mgr.call("on_creation_ending", s)
		print("[creation] 配饰触发 song=%d  accessory=%s" % [s, SONGS[s].accessory])
	else:
		push_warning("[creation] CostumeManager 未找到，配饰变化跳过")


# 推进到下一首歌，或触发 Step 8 总结尾
func _advance_to_next_song(s: int) -> void:
	var next := s + 1
	if next < SONGS.size():
		_current_song   = next
		_current_stroke = 0
		_next_anchor    = 0
		_refresh_anchor_states()
		print("[creation] → 下一首歌 song=%d (%s)" % [next, SONGS[next].name])
	else:
		print("[creation] Force 06 全部完成 → 启动 Step 8 四图并置")
		_force06_finale()


# ═══════════════════════════════════════════════════════
# Step 8 — 四图并置总结尾
# ═══════════════════════════════════════════════════════

func _force06_finale() -> void:
	# ── 1. 收集所有已绘完的线条材质与基础发光值 ────────────────
	var mats:       Array = []   # Array[ShaderMaterial]
	var base_glows: Array = []   # Array[float]

	for s in SONGS.size():
		for k in 4:
			var mi := _line_meshes[s][k] as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var mat := mi.material_override as ShaderMaterial
			if mat:
				mats.append(mat)
				base_glows.append(STROKE_GLOW[k])

	if mats.is_empty():
		return

	# ── 2. 四图同步冲高发光（1.2 s 升至峰值）────────────────────
	for i in mats.size():
		var mat: ShaderMaterial = mats[i]
		var base: float         = base_glows[i]
		var tw := create_tween()
		tw.tween_method(
			func(v: float) -> void: mat.set_shader_parameter("glow", v),
			base, 6.0, 1.2
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# ── 3. 峰值停留（静默凝视）───────────────────────────────────
	await get_tree().create_timer(2.5).timeout

	# ── 4. 缓落至永久略亮状态（比原值亮 1.6 倍，2.0 s）─────────
	for i in mats.size():
		var mat: ShaderMaterial = mats[i]
		var settled: float      = base_glows[i] * 1.6
		var tw := create_tween()
		tw.tween_method(
			func(v: float) -> void: mat.set_shader_parameter("glow", v),
			6.0, settled, 2.0
		).set_ease(Tween.EASE_OUT)

	# ── 5. 最终静默留白 ──────────────────────────────────────────
	await get_tree().create_timer(2.0).timeout

	print("[creation] Force 06 完结")
