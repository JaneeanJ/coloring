extends Node3D

# Force 03：Connection（连接）场景控制器
# 步骤三：NPC 路径行走 + 染色 + 轨迹

enum DreamState { WALKING, STILL, ENDING }
var state: DreamState = DreamState.WALKING

signal ending_done(tool_id: String)   # 步骤八：结局特效结束后通知 world.gd 触发字幕+配饰

# ── 拼图参数 ─────────────────────────────────────────────────────
# 8×8 网格坐标 → 世界单位，缩放 3.0（拼图整体约 24×24m）
const PUZZLE_SCALE := 3.0

# 七块拼图：顶点（8×8 网格坐标）、颜色、名称
# 索引 0~5 = 六位旅人；索引 6 = 玩家（小三角形 B）
const PIECE_DATA := [
	{"verts": [Vector2(0,0), Vector2(0,8), Vector2(4,4)],              "color": "#5B7C99", "id": "npc_0"},  # 大三角形 A 黛蓝
	{"verts": [Vector2(0,8), Vector2(8,8), Vector2(4,4)],              "color": "#B56B5C", "id": "npc_1"},  # 大三角形 B 赭红
	{"verts": [Vector2(8,0), Vector2(8,4), Vector2(4,0)],              "color": "#D3A34D", "id": "npc_2"},  # 中三角形   藤黄
	{"verts": [Vector2(2,2), Vector2(6,2), Vector2(4,4)],              "color": "#7FA98C", "id": "npc_3"},  # 小三角形 A 竹青
	{"verts": [Vector2(4,4), Vector2(6,2), Vector2(8,4), Vector2(6,6)],"color": "#A79BB0", "id": "npc_4"},  # 正方形     雾紫
	{"verts": [Vector2(0,0), Vector2(4,0), Vector2(6,2), Vector2(2,2)],"color": "#C5D0D3", "id": "npc_5"},  # 平行四边形 月白
	{"verts": [Vector2(8,4), Vector2(8,8), Vector2(6,6)],              "color": "#F4C6D0", "id": "player"}, # 小三角形 B 樱霞粉（玩家）
]

const PLAYER_PIECE_INDEX := 6

var _pieces:     Array = []   # MeshInstance3D × 7
var _piece_mats: Array = []   # StandardMaterial3D × 7

# ── NPC 参数 ─────────────────────────────────────────────────────
const NPC_COUNT      := 6
const NPC_SPEED      := 1.2   # 漂浮速度（单位/秒）
const NPC_REACH_DIST := 0.4   # 到达路径点的距离阈值
const NPC_SCALE      := 2.5   # 模型缩放

# 玩家进入此距离后 NPC 才开始移动（相对 Connection 节点原点）
const ACTIVATION_RADIUS := 28.0

# NPC 颜色（与拼图索引 0~5 一一对应）
const NPC_COLORS := [
	"#5B7C99",  # 黛蓝  — 大三角形 A
	"#B56B5C",  # 赭红  — 大三角形 B
	"#D3A34D",  # 藤黄  — 中三角形
	"#7FA98C",  # 竹青  — 小三角形 A
	"#A79BB0",  # 雾紫  — 正方形
	"#C5D0D3",  # 月白  — 平行四边形
]

# 各 NPC 的漫游路径（本地坐标，PUZZLE_SCALE=3.0 时拼图跨度 -12~12）
# y≈1.0 轻微悬浮地面，路径走完后 progress_ratio = 1.0
const NPC_WAYPOINTS := [
	# NPC 0 — 大三角形 A（左侧，顶点 (-12,-12) (-12,12) (0,0)）
	[Vector3(-12.0, 1.0, -11.0), Vector3(-12.0, 1.0, -2.0),
	 Vector3(-8.0,  1.0,   3.0), Vector3(-2.0,  1.0,  0.0),
	 Vector3(-6.0,  1.0,  -8.0), Vector3(-12.0, 1.0, -11.0)],
	# NPC 1 — 大三角形 B（底部，顶点 (-12,12) (12,12) (0,0)）
	[Vector3(-11.0, 1.0, 11.0), Vector3(-3.0, 1.0,  8.0),
	 Vector3(  0.0, 1.0,  5.0), Vector3( 4.0, 1.0,  8.0),
	 Vector3( 11.0, 1.0, 11.0), Vector3(  1.0, 1.0,  6.0)],
	# NPC 2 — 中三角形（右上，顶点 (12,-12) (12,0) (0,-12)）
	[Vector3( 7.0, 1.0, -12.0), Vector3(12.0, 1.0, -10.0),
	 Vector3(12.0, 1.0,  -4.0), Vector3( 9.0, 1.0,  -7.0),
	 Vector3( 7.0, 1.0, -11.0)],
	# NPC 3 — 小三角形 A（中央，顶点 (-6,-6) (6,-6) (0,0)）
	[Vector3(-5.0, 1.0, -6.0), Vector3( 0.0, 1.0, -3.0),
	 Vector3( 5.0, 1.0, -6.0), Vector3( 0.0, 1.0, -5.0),
	 Vector3(-4.0, 1.0, -6.0)],
	# NPC 4 — 正方形（右中，顶点 (0,0) (6,-6) (12,0) (6,6)）
	[Vector3( 5.0, 1.0, -6.0), Vector3(11.0, 1.0, -2.0),
	 Vector3(12.0, 1.0,  1.0), Vector3( 6.0, 1.0,  5.0),
	 Vector3( 1.0, 1.0,  1.0), Vector3( 5.0, 1.0, -5.0)],
	# NPC 5 — 平行四边形（上方，顶点 (-12,-12) (0,-12) (6,-6) (-6,-6)）
	[Vector3(-11.0, 1.0, -11.0), Vector3(-3.0, 1.0, -12.0),
	 Vector3(  3.0, 1.0, -11.0), Vector3( 5.0, 1.0,  -7.0),
	 Vector3( -5.0, 1.0,  -7.0), Vector3(-11.0, 1.0,  -9.0)],
]

var _npcs:             Array = []  # Node3D × 6
var _npc_waypoint_idx: Array = []  # 当前目标 waypoint 索引 × 6
var _npc_path_done:    Array = []  # 已累计路程 × 6
var _npc_path_total:   Array = []  # 总路程 × 6
var _npc_progress:     Array = []  # progress_ratio 0~1 × 6

# ── 同行加成参数 ──────────────────────────────────────────────────
const COMPANION_RADIUS := 8.0   # 触发加成的距离阈值
const COMPANION_GAIN   := 2.0   # 靠近时 bonus 增速（/s，约 0.25s 满）
const COMPANION_DECAY  := 0.30  # 离开后 bonus 衰减速度（/s）
const COMPANION_MAX    := 0.50  # bonus 上限

var _companion_bonus: Array = []  # float × 6，叠加在 base_progress 上显示
var _npc_lights:      Array = []  # OmniLight3D × 6，挂在各 NPC 上

var _tint_shader:    Shader
var _player:         Node3D      = null
var _activated:      bool        = false
var _player_light:   OmniLight3D = null   # 跟随玩家的光源

# ── 拼图区域灯参数 ────────────────────────────────────────────────
const PIECE_LIGHT_MIN_E  := 0.3    # 初始底光 energy
const PIECE_LIGHT_MAX_E  := 3.5    # 完全点亮时 energy
const PIECE_LIGHT_RANGE  := 10.0   # 光照半径

# 七块拼图重心（用于放置区域灯，高度 6.0 俯射拼图面）
const PIECE_CENTROIDS := [
	Vector3(-8.0, 6.0,  0.0),  # 0 大三角形 A
	Vector3( 0.0, 6.0,  8.0),  # 1 大三角形 B
	Vector3( 8.0, 6.0, -8.0),  # 2 中三角形
	Vector3( 0.0, 6.0, -4.0),  # 3 小三角形 A
	Vector3( 6.0, 6.0,  0.0),  # 4 正方形
	Vector3(-3.0, 6.0, -9.0),  # 5 平行四边形
	Vector3(10.0, 6.0,  6.0),  # 6 玩家
]

var _piece_lights: Array = []  # OmniLight3D × 7

# ── STILL 阶段 ────────────────────────────────────────────────────
var _npc_frozen:     bool  = false
var _still_delay:    float = 0.0   # 进入 STILL 后等待工具淡入的计时
var _tools_shown:    bool  = false
var _float_time:     float = 0.0   # 工具漂浮动画时间

# ── 结局工具 UI ───────────────────────────────────────────────────
var _ending_ui:    CanvasLayer = null
var _tools:        Array       = []   # Control × 3 (frame, water, scissors)
var _tool_base_y:  Array       = []   # float × 3，各工具初始 Y，用于漂浮基准

# ── 拖拽 DropZone + 悬停预览（步骤 7-1/7-3）────────────────────
const DROP_ZONE_SIZE := Vector2(400.0, 400.0)  # 覆盖拼图在正常视角下的投影范围，可运行时调试
var _drop_zone:           Control = null
var _preview_tool:        String  = ""   # 当前悬停预览的 tool_id，""=无
var _frame_preview_rects: Array   = []   # 4 个 ColorRect，画框预览金边
var _outline_meshes:      Array   = []   # 7 个 MeshInstance3D，剪刀预览轮廓

# ── 结局特效（步骤 7-4/7-5）────────────────────────────────────
var _frame_edges: Array        = []    # 4 个 ColorRect，画框结局从屏幕外合拢用
var _noise_tex:   NoiseTexture2D = null  # 水盆结局溶解噪声纹理（程序生成）

# ── 玩家圆形区域参数 ──────────────────────────────────────────────
const CIRCLE_COLOR      := "#F4C6D0"   # 樱霞粉
const CIRCLE_RADIUS     := 1.2         # 圆半径（单位）
const CIRCLE_STAND_TIME := 5.0         # 需要站立的秒数
# 圆心 = 玩家三角形重心（顶点 (12,0)(12,12)(6,6) 的重心）
const CIRCLE_CENTER     := Vector3(10.0, 0.0, 6.0)

var _circle_area:      Area3D             = null
var _circle_mat:       StandardMaterial3D = null
var _player_in_circle: bool               = false
var _circle_timer:     float              = 0.0
var _circle_lit:       bool               = false


func _ready() -> void:
	_create_puzzle()
	_init_tint_shader()
	_create_npcs()
	_create_player_circle()
	_create_player_light()
	_create_base_light()
	_create_piece_lights()
	_create_noise_texture()   # 步骤 7-5：提前生成，确保结局时已就绪
	_create_ending_ui()
	_player = get_tree().get_first_node_in_group("player") as Node3D
	print("[connection] state=WALKING, puzzle + NPCs + lights ready")


func _process(delta: float) -> void:
	match state:
		DreamState.WALKING:
			_update_walking(delta)
		DreamState.STILL:
			_update_still(delta)
		DreamState.ENDING:
			pass


func _update_walking(delta: float) -> void:
	# 玩家灯跟随玩家世界坐标
	if _player_light and _player:
		_player_light.global_position = _player.global_position + Vector3(0.0, 1.2, 0.0)

	_update_player_circle(delta)

	# 等玩家走近再激活 NPC
	if not _activated:
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as Node3D
			return
		var dist: float = global_position.distance_to(_player.global_position)
		if dist > ACTIVATION_RADIUS:
			return
		# 玩家进入范围：激活 NPC，启动粒子
		_activated = true
		for npc in _npcs:
			var p := npc.get_node_or_null("TrailParticles") as GPUParticles3D
			if p:
				p.emitting = true
		print("[connection] player entered, NPCs activated")

	_update_npc_movement(delta)
	_update_companion_bonus(delta)
	_update_piece_lights()

	# 检查进入 STILL：玩家圆圈点亮 + 六个 NPC 全部走完
	if _circle_lit:
		var all_done := true
		for prog in _npc_progress:
			if (prog as float) < 1.0:
				all_done = false
				break
		if all_done:
			_enter_still()


func _enter_still() -> void:
	state        = DreamState.STILL
	_npc_frozen  = true
	_still_delay = 0.0
	_tools_shown = false
	# DropZone 在 NPC 全部走完后才显示
	if _drop_zone != null:
		_drop_zone.visible = true
	print("[connection] state=STILL, NPCs frozen")


func _enter_ending(tool_id: String) -> void:
	state = DreamState.ENDING
	print("[connection] state=ENDING tool=", tool_id)


# 步骤 7-2：DropZone 松手确认后的入口
# 负责：禁用所有交互、选中工具标记确认、另外两个工具淡出消失、分发结局
func on_ending_confirmed(tool_id: String) -> void:
	# 禁用全部工具交互（包括未被选中的两个）
	for tool in _tools:
		if is_instance_valid(tool):
			tool.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 禁用 DropZone（防止二次触发，drop_zone.gd 已设 IGNORE，此处双保险）
	if is_instance_valid(_drop_zone):
		_drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 选中工具标记确认（阻止 draggable_tool 的归位 Tween）；另外两个淡出后销毁
	for tool in _tools:
		if not is_instance_valid(tool):
			continue
		if tool.get("tool_id") == tool_id:
			tool.call("confirm")
		else:
			var tw := create_tween()
			tw.tween_property(tool, "modulate:a", 0.0, 0.5)
			tw.tween_callback(tool.queue_free)

	print("[connection] ending confirmed: ", tool_id)
	_enter_ending(tool_id)
	match tool_id:
		"frame":    _play_frame_ending()
		"water":    _play_water_ending()
		"scissors": _play_scissors_ending()


# ── 拼图生成 ─────────────────────────────────────────────────────

func _create_puzzle() -> void:
	for i in PIECE_DATA.size():
		var data: Dictionary = PIECE_DATA[i]
		var verts  := data["verts"] as Array
		var color  := Color(data["color"] as String)
		var piece  := _make_piece_mesh(verts, color)
		piece.name = "Piece_" + data["id"]
		add_child(piece)
		_pieces.append(piece)
		_piece_mats.append(piece.material_override)

	# 初始全透明；NPC 行走后逐步显现（玩家块由步骤四驱动）
	for i in _pieces.size():
		set_piece_alpha(i, 0.0)

	_create_outline_meshes()   # 步骤 7-3：剪刀预览轮廓线


# 将 8×8 网格坐标列表构建为地面平面 ArrayMesh
func _make_piece_mesh(grid_verts: Array, color: Color) -> MeshInstance3D:
	var v3: Array = []
	for gv in grid_verts:
		v3.append(_grid_to_local(gv))

	# 扇形三角剖分（首顶点为扇心）
	var positions := PackedVector3Array()
	var normals   := PackedVector3Array()
	for i in range(1, v3.size() - 1):
		positions.append(v3[0]);   normals.append(Vector3.UP)
		positions.append(v3[i]);   normals.append(Vector3.UP)
		positions.append(v3[i+1]); normals.append(Vector3.UP)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(color.r, color.g, color.b, 0.0)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness     = 0.82
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh              = arr_mesh
	mi.material_override = mat
	return mi


# 8×8 网格坐标 → 本地 Vector3（居中，y 略高于地面）
func _grid_to_local(gv: Vector2) -> Vector3:
	return Vector3((gv.x - 4.0) * PUZZLE_SCALE, 0.02, (gv.y - 4.0) * PUZZLE_SCALE)


# ── 公共接口：驱动某块的显现进度（0=透明，1=完全不透明）────────
func set_piece_alpha(index: int, alpha: float) -> void:
	if index < 0 or index >= _piece_mats.size():
		return
	var mat := _piece_mats[index] as StandardMaterial3D
	var c   := mat.albedo_color
	c.a = clamp(alpha, 0.0, 1.0)
	mat.albedo_color = c


# ── 染色 Shader（material_overlay 叠加在 NPC 模型上）────────────

func _init_tint_shader() -> void:
	_tint_shader = Shader.new()
	_tint_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, unshaded, cull_back;
uniform vec4 tint_color : source_color = vec4(0.5, 0.7, 0.9, 0.88);

void fragment() {
\tALBEDO   = tint_color.rgb;
\tALPHA    = tint_color.a;
\tEMISSION = tint_color.rgb * 0.12;
}
"""


# ── NPC 创建 ─────────────────────────────────────────────────────

func _create_npcs() -> void:
	var npc_res = load("res://models/npc/npc.glb")
	if npc_res == null:
		push_warning("[connection] NPC model not found: res://models/npc/npc.glb")
		return

	for i in NPC_COUNT:
		var npc_root := Node3D.new()
		npc_root.name = "NPC_%d" % i
		add_child(npc_root)

		# 放置到路径起点
		npc_root.position = NPC_WAYPOINTS[i][0]

		# 实例化模型
		var model: Node3D = npc_res.instantiate()
		model.scale = Vector3(NPC_SCALE, NPC_SCALE, NPC_SCALE)
		npc_root.add_child(model)

		# 整体染色
		var color := Color(NPC_COLORS[i])
		_apply_npc_tint(model, color)

		# 轨迹粒子（初始关闭，玩家进入范围后启动）
		_create_trail_particles(npc_root, color)

		# 预计算路径总长
		# NPC 自身光源（初始熄灭）
		var npc_light := OmniLight3D.new()
		npc_light.name             = "CompanionLight"
		npc_light.light_color      = Color(NPC_COLORS[i])
		npc_light.light_energy     = 0.0
		npc_light.omni_range       = 10.0
		npc_light.shadow_enabled   = false
		npc_light.position         = Vector3(0.0, 1.5, 0.0)
		npc_root.add_child(npc_light)

		_npcs.append(npc_root)
		_npc_waypoint_idx.append(1)
		_npc_path_done.append(0.0)
		_npc_path_total.append(_compute_path_total(NPC_WAYPOINTS[i]))
		_npc_progress.append(0.0)
		_companion_bonus.append(0.0)
		_npc_lights.append(npc_light)

	print("[connection] %d NPCs created, waiting for activation" % NPC_COUNT)


# 对模型下所有 MeshInstance3D 挂 material_overlay，实现整体染色
func _apply_npc_tint(model: Node3D, color: Color) -> void:
	if _tint_shader == null:
		return
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		var mat := ShaderMaterial.new()
		mat.shader = _tint_shader
		mat.set_shader_parameter("tint_color", Color(color.r, color.g, color.b, 0.88))
		mi.material_overlay = mat


# 在 NPC 脚下挂 GPUParticles3D，粒子不跟随节点移动，形成彩色轨迹
func _create_trail_particles(parent: Node3D, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.name         = "TrailParticles"
	particles.amount       = 40
	particles.lifetime     = 25.0
	particles.emitting     = false  # 玩家激活后再开启
	particles.fixed_fps    = 0
	particles.local_coords = false  # 粒子留在世界坐标，形成实际轨迹

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape       = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction            = Vector3(0.0, -1.0, 0.0)
	pm.spread               = 25.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.20
	pm.gravity              = Vector3(0.0, -0.2, 0.0)
	pm.scale_min            = 0.15
	pm.scale_max            = 0.40
	pm.color                = Color(color.r, color.g, color.b, 0.55)
	particles.process_material = pm

	# 粒子形状：扁平小圆片（CylinderMesh，height 极小）
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.20
	cyl.bottom_radius = 0.20
	cyl.height        = 0.02

	var p_mat := StandardMaterial3D.new()
	p_mat.albedo_color               = Color(color.r, color.g, color.b, 0.70)
	p_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.emission_enabled           = true
	p_mat.emission                   = color
	p_mat.emission_energy_multiplier = 0.35
	cyl.surface_set_material(0, p_mat)
	particles.draw_passes = 1
	particles.set_draw_pass_mesh(0, cyl)

	parent.add_child(particles)


# 计算路径总长（相邻 waypoint 之间距离的累加）
func _compute_path_total(waypoints: Array) -> float:
	var total := 0.0
	for i in range(1, waypoints.size()):
		total += (waypoints[i] as Vector3).distance_to(waypoints[i - 1])
	return total


# ── NPC 移动更新 ─────────────────────────────────────────────────

func _update_npc_movement(delta: float) -> void:
	if _npc_frozen:
		return
	for i in _npcs.size():
		_move_npc(i, delta)


func _move_npc(idx: int, delta: float) -> void:
	var npc      : Node3D = _npcs[idx]
	var waypoints: Array  = NPC_WAYPOINTS[idx]
	var wp       : int    = _npc_waypoint_idx[idx]

	# 已抵达终点：进度锁定为 1.0
	if wp >= waypoints.size():
		if _npc_progress[idx] < 1.0:
			_npc_progress[idx] = 1.0
			set_piece_alpha(idx, 1.0)
		return

	var target   : Vector3 = waypoints[wp]
	var to_target: Vector3 = target - npc.position
	var dist     : float   = to_target.length()

	if dist <= NPC_REACH_DIST:
		# 到达当前 waypoint，累计本段路程并推进到下一个目标
		if wp > 0:
			_npc_path_done[idx] += (waypoints[wp - 1] as Vector3).distance_to(target)
		_npc_waypoint_idx[idx] += 1
		npc.position = target
	else:
		# 向目标漂浮移动（不使用物理，梦境漂浮感）
		var dir  : Vector3 = to_target / dist
		var step : float   = min(NPC_SPEED * delta, dist)
		npc.position += dir * step
		# 面朝行进方向（仅 XZ 平面旋转）
		if abs(dir.x) + abs(dir.z) > 0.01:
			npc.rotation.y = atan2(-dir.x, -dir.z)

	# 实时进度 = 已完成段累计 + 当前段已走距离
	var cur_wp : int   = _npc_waypoint_idx[idx]
	var extra  : float = 0.0
	if cur_wp < waypoints.size() and cur_wp > 0:
		var seg_end : Vector3 = waypoints[cur_wp]
		var seg_len : float   = (waypoints[cur_wp - 1] as Vector3).distance_to(seg_end)
		extra = seg_len - npc.position.distance_to(seg_end)
		extra = max(0.0, extra)

	if _npc_path_total[idx] > 0.0:
		_npc_progress[idx] = clamp((_npc_path_done[idx] + extra) / _npc_path_total[idx], 0.0, 1.0)
		set_piece_alpha(idx, _npc_progress[idx])


# ── 玩家圆形区域 ─────────────────────────────────────────────────

func _create_player_circle() -> void:
	_circle_area = Area3D.new()
	_circle_area.name = "PlayerCircle"
	# y=0.75 让碰撞圆柱中心在玩家腰部，覆盖 y:0~1.5
	_circle_area.position = CIRCLE_CENTER + Vector3(0.0, 0.75, 0.0)

	# 碰撞形状：圆柱
	var col   := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = CIRCLE_RADIUS
	shape.height = 1.5
	col.shape = shape
	_circle_area.add_child(col)

	# 视觉：扁平圆盘（CylinderMesh）
	var mi  := MeshInstance3D.new()
	mi.name  = "CircleMesh"
	var cyl := CylinderMesh.new()
	cyl.top_radius    = CIRCLE_RADIUS
	cyl.bottom_radius = CIRCLE_RADIUS
	cyl.height        = 0.04
	cyl.radial_segments = 48
	mi.mesh       = cyl
	mi.position.y = -0.72   # 相对 area 中心下移，圆盘贴地 y≈0.03

	var base_color   := Color(CIRCLE_COLOR)
	base_color.a      = 0.22
	_circle_mat                   = StandardMaterial3D.new()
	_circle_mat.albedo_color      = base_color
	_circle_mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
	_circle_mat.roughness         = 0.70
	_circle_mat.emission_enabled  = false
	mi.material_override = _circle_mat
	_circle_area.add_child(mi)

	_circle_area.body_entered.connect(_on_circle_body_entered)
	_circle_area.body_exited.connect(_on_circle_body_exited)
	add_child(_circle_area)
	print("[connection] player circle created, radius=", CIRCLE_RADIUS)


func _on_circle_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_circle = true


func _on_circle_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_circle = false


func _update_player_circle(delta: float) -> void:
	if _circle_lit or _circle_mat == null:
		return

	if _player_in_circle:
		_circle_timer = min(_circle_timer + delta, CIRCLE_STAND_TIME)
	else:
		# 离开后缓慢衰减（0.5 倍速），不瞬间归零
		_circle_timer = max(0.0, _circle_timer - delta * 0.5)

	var progress  := _circle_timer / CIRCLE_STAND_TIME
	var base      := Color(CIRCLE_COLOR)

	# 随进度加深 alpha 和发光
	base.a = lerpf(0.22, 0.90, progress)
	_circle_mat.albedo_color = base

	if progress > 0.1:
		_circle_mat.emission_enabled           = true
		_circle_mat.emission                   = Color(CIRCLE_COLOR)
		_circle_mat.emission_energy_multiplier = progress * 1.8
	else:
		_circle_mat.emission_enabled = false

	# 5 秒满：点亮玩家拼图块，圆圈消失
	if _circle_timer >= CIRCLE_STAND_TIME:
		_circle_lit = true
		set_piece_alpha(PLAYER_PIECE_INDEX, 1.0)
		if is_instance_valid(_circle_area):
			_circle_area.queue_free()
			_circle_area = null
		print("[connection] player circle lit!")


# ── 玩家光源创建 ─────────────────────────────────────────────────

func _create_player_light() -> void:
	_player_light = OmniLight3D.new()
	_player_light.name           = "PlayerCompanionLight"
	_player_light.light_energy   = 0.0
	_player_light.omni_range     = 8.0
	_player_light.shadow_enabled = false
	add_child(_player_light)


# ── 同行加成 ──────────────────────────────────────────────────────

func _update_companion_bonus(delta: float) -> void:
	if _player == null:
		return

	var max_bonus    : float = 0.0
	var max_bonus_idx: int   = -1

	for i in _npcs.size():
		if i >= _companion_bonus.size():
			break

		var npc  : Node3D = _npcs[i]
		var dist : float  = npc.global_position.distance_to(_player.global_position)
		var near : bool   = dist < COMPANION_RADIUS

		# bonus 积累 / 衰减
		if near:
			_companion_bonus[i] = min(_companion_bonus[i] + COMPANION_GAIN * delta, COMPANION_MAX)
		else:
			_companion_bonus[i] = max(_companion_bonus[i] - COMPANION_DECAY * delta, 0.0)

		# 记录 bonus 最大的 NPC（用于驱动玩家灯颜色）
		if _companion_bonus[i] > max_bonus:
			max_bonus     = _companion_bonus[i]
			max_bonus_idx = i

		# 拼图 alpha = base_progress + bonus
		set_piece_alpha(i, clamp(_npc_progress[i] + _companion_bonus[i], 0.0, 1.0))

		# NPC 光源随 bonus 渐亮（最大 energy 2.5）
		if i < _npc_lights.size():
			var npc_light := _npc_lights[i] as OmniLight3D
			if npc_light:
				npc_light.light_energy = (_companion_bonus[i] / COMPANION_MAX) * 2.5

		# 粒子视觉：靠近时略微变大变亮
		var p := npc.get_node_or_null("TrailParticles") as GPUParticles3D
		if p == null:
			continue
		var pm := p.process_material as ParticleProcessMaterial
		if pm == null:
			continue
		var npc_color := Color(NPC_COLORS[i])
		if near:
			pm.scale_min = 0.20
			pm.scale_max = 0.50
			pm.color     = Color(
				min(npc_color.r + 0.25, 1.0),
				min(npc_color.g + 0.25, 1.0),
				min(npc_color.b + 0.25, 1.0), 0.85)
		else:
			pm.scale_min = 0.15
			pm.scale_max = 0.40
			pm.color     = Color(npc_color.r, npc_color.g, npc_color.b, 0.55)

	# 玩家灯：颜色取 bonus 最大的 NPC，随其 bonus 渐亮
	if _player_light:
		if max_bonus_idx >= 0:
			_player_light.light_color  = Color(NPC_COLORS[max_bonus_idx])
			_player_light.light_energy = (max_bonus / COMPANION_MAX) * 2.0
		else:
			_player_light.light_energy = 0.0


# ── 拼图底光 + 区域灯 ─────────────────────────────────────────────

func _create_base_light() -> void:
	# 整个拼图区域的底光，暖白色，让颜色基本可见
	var base := OmniLight3D.new()
	base.name            = "PuzzleBaseLight"
	base.light_color     = Color(1.0, 0.97, 0.92)  # 暖白
	base.light_energy    = 0.8
	base.omni_range      = 38.0
	base.shadow_enabled  = false
	base.position        = Vector3(0.0, 14.0, 0.0)  # 拼图中央正上方
	add_child(base)


func _create_piece_lights() -> void:
	for i in PIECE_DATA.size():
		var piece_color := Color(PIECE_DATA[i]["color"] as String)
		var light       := OmniLight3D.new()
		light.name           = "PieceLight_%d" % i
		light.light_color    = piece_color
		light.shadow_enabled = false
		light.position       = PIECE_CENTROIDS[i]

		# 大三角形 A（蓝，index 0）和大三角形 B（红，index 1）面积最大，单独加强
		if i == 0 or i == 1:
			light.light_energy = 0.7
			light.omni_range   = 18.0
		else:
			light.light_energy = PIECE_LIGHT_MIN_E
			light.omni_range   = PIECE_LIGHT_RANGE

		add_child(light)
		_piece_lights.append(light)
	print("[connection] %d piece lights created" % _piece_lights.size())


func _update_piece_lights() -> void:
	for i in _piece_lights.size():
		if i >= _piece_mats.size():
			break
		var mat   := _piece_mats[i] as StandardMaterial3D
		var light := _piece_lights[i] as OmniLight3D
		if mat == null or light == null:
			continue
		var alpha   := mat.albedo_color.a
		var min_e   := 0.7 if (i == 0 or i == 1) else PIECE_LIGHT_MIN_E
		var max_e   := 5.0 if (i == 0 or i == 1) else PIECE_LIGHT_MAX_E
		light.light_energy = lerpf(min_e, max_e, alpha)


# ── 结局工具 UI ───────────────────────────────────────────────────

func _create_ending_ui() -> void:
	_ending_ui = CanvasLayer.new()
	_ending_ui.name = "EndingUI"
	add_child(_ending_ui)

	var vp   := get_viewport().get_visible_rect().size
	var cx   := vp.x * 0.5
	var cy   := vp.y * 0.78

	# 三个工具：画框 / 水盆 / 剪刀，均初始透明
	var tool_data := [
		{"name": "ToolFrame",    "offset_x": -240.0, "tool_id": "frame"},
		{"name": "ToolWater",    "offset_x":    0.0, "tool_id": "water"},
		{"name": "ToolScissors", "offset_x":  240.0, "tool_id": "scissors"},
	]
	var builders := [
		_build_tool_frame,
		_build_tool_water,
		_build_tool_scissors,
	]

	# 步骤 7-1：为每个工具附加拖拽脚本
	var dragger_script := load("res://draggable_tool.gd")

	for i in 3:
		var ctrl: Control = builders[i].call()
		ctrl.name         = tool_data[i]["name"]
		ctrl.position     = Vector2(cx + tool_data[i]["offset_x"] - ctrl.custom_minimum_size.x * 0.5, cy)
		ctrl.modulate.a   = 0.0
		# set_script 在 add_child 之前调用：_ready 在 add_child 时触发，position 已就位
		ctrl.set_script(dragger_script)
		_ending_ui.add_child(ctrl)
		ctrl.set("tool_id", tool_data[i]["tool_id"])
		_tools.append(ctrl)
		_tool_base_y.append(ctrl.position.y)

	_create_drop_zone()
	_create_frame_edges()   # 步骤 7-4：画框结局四条边，初始在屏幕外
	print("[connection] ending UI created, 3 tools + DropZone ready")


func _build_tool_frame() -> Control:
	var root  := Control.new()
	var sz    := Vector2(88.0, 88.0)
	var t     := 7.0            # 边框厚度
	root.custom_minimum_size = sz
	var col   := Color(0.96, 0.86, 0.42)
	for rect_data: Array in [
		[Vector2(0, 0),        Vector2(sz.x, t)],           # 上
		[Vector2(0, sz.y - t), Vector2(sz.x, t)],           # 下
		[Vector2(0, 0),        Vector2(t, sz.y)],            # 左
		[Vector2(sz.x - t, 0), Vector2(t, sz.y)],           # 右
	]:
		var cr      := ColorRect.new()
		cr.color     = col
		cr.position  = rect_data[0]
		cr.size      = rect_data[1]
		root.add_child(cr)
	return root


func _build_tool_water() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(110.0, 68.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.38, 0.70, 0.96)
	style.set_corner_radius_all(34)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _build_tool_scissors() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(88.0, 88.0)
	var col  := Color(0.76, 0.76, 0.82)
	for angle: float in [32.0, -32.0]:
		var cr           := ColorRect.new()
		cr.color          = col
		cr.size           = Vector2(82.0, 8.0)
		cr.pivot_offset   = Vector2(41.0, 4.0)
		cr.position       = Vector2(3.0, 40.0)
		cr.rotation_degrees = angle
		root.add_child(cr)
	return root


func _update_still(delta: float) -> void:
	_still_delay += delta

	# 0.5 秒定格演出后工具淡入
	if not _tools_shown and _still_delay >= 0.5:
		_tools_shown = true
		for tool in _tools:
			var tw := create_tween()
			tw.tween_property(tool, "modulate:a", 1.0, 0.9)
		# 淡入结束后启用拖拽交互（步骤 7-1）
		get_tree().create_timer(0.9).timeout.connect(_enable_tool_interaction)

	if not _tools_shown:
		return

	# DropZone 跟随拼图 3D→2D 投影（步骤 7-1）
	if _drop_zone != null:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var screen_pos := camera.unproject_position(global_position)
			_drop_zone.position = screen_pos - DROP_ZONE_SIZE * 0.5

	# 漂浮动画
	_float_time += delta
	for i in _tools.size():
		if not is_instance_valid(_tools[i]):
			continue
		_tools[i].position.y = _tool_base_y[i] + sin(_float_time * 1.2 + i * 2.1) * 9.0

	# 步骤 7-3：悬停预览实时驱动（水盆颜色震荡 / 剪刀轮廓 alpha 震荡）
	match _preview_tool:
		"water":
			_update_water_preview()
		"scissors":
			_update_scissors_preview_alpha()


# ── 步骤 7-1：DropZone 建立 ──────────────────────────────────────

func _create_drop_zone() -> void:
	var dz := Control.new()
	dz.name               = "DropZone"
	dz.custom_minimum_size = DROP_ZONE_SIZE
	dz.size               = DROP_ZONE_SIZE
	dz.z_index            = -1                         # 工具层下方
	dz.mouse_filter       = Control.MOUSE_FILTER_STOP
	dz.set_script(load("res://drop_zone.gd"))
	dz.visible = false                                 # WALKING 阶段隐藏，_enter_still 时显示
	_ending_ui.add_child(dz)
	dz.set_connection(self)                            # 绑定回调目标（步骤 7-2 起生效）
	_drop_zone = dz

	# 临时调试色块：半透明红色背景，辅助确认覆盖范围，步骤七完成后移除
	var dbg := ColorRect.new()
	dbg.color        = Color(1.0, 0.2, 0.2, 0.08)
	dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dz.add_child(dbg)

	# 步骤 7-3：画框预览金边（初始 alpha=0，悬停时淡入）
	_create_frame_preview_rects()

	print("[connection] drop zone created size=", DROP_ZONE_SIZE)


# 步骤 7-1：工具淡入完成后由 timer 回调，启用拖拽交互
func _enable_tool_interaction() -> void:
	for tool in _tools:
		if is_instance_valid(tool):
			tool.mouse_filter = Control.MOUSE_FILTER_STOP
	print("[connection] tools interactive, drag enabled")


# ── 步骤 7-3：悬停预览 ───────────────────────────────────────────

# DropZone 回调（公共）：切换预览
func start_preview(tool_id: String) -> void:
	if _preview_tool == tool_id:
		return
	clear_preview()
	_preview_tool = tool_id
	match tool_id:
		"frame":    _start_frame_preview()
		"scissors": _start_scissors_preview()
		# "water" 预览由 _update_still 逐帧驱动，无需显式 start


# DropZone 回调（公共）：清除预览
func clear_preview() -> void:
	match _preview_tool:
		"frame":    _clear_frame_preview()
		"water":    _clear_water_preview()
		"scissors": _clear_scissors_preview()
	_preview_tool = ""


# ── 画框预览 ──────────────────────────────────────────────────────

func _create_frame_preview_rects() -> void:
	if _drop_zone == null:
		return
	var sz := DROP_ZONE_SIZE
	var t  := 4.0   # 边框厚度（px）
	for rect_data: Array in [
		[Vector2(0,       0),      Vector2(sz.x, t)],    # 上
		[Vector2(0,       sz.y-t), Vector2(sz.x, t)],    # 下
		[Vector2(0,       0),      Vector2(t, sz.y)],    # 左
		[Vector2(sz.x-t,  0),      Vector2(t, sz.y)],    # 右
	]:
		var cr         := ColorRect.new()
		cr.color        = Color(0.96, 0.86, 0.42, 0.0)   # 金色，初始 alpha=0
		cr.position     = rect_data[0]
		cr.size         = rect_data[1]
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drop_zone.add_child(cr)
		_frame_preview_rects.append(cr)


func _start_frame_preview() -> void:
	for cr in _frame_preview_rects:
		if is_instance_valid(cr):
			var tw := create_tween()
			tw.tween_property(cr, "color:a", 0.55, 0.25)


func _clear_frame_preview() -> void:
	for cr in _frame_preview_rects:
		if is_instance_valid(cr):
			var tw := create_tween()
			tw.tween_property(cr, "color:a", 0.0, 0.2)


# ── 水盆预览（逐帧驱动，无显式 start）────────────────────────────

func _update_water_preview() -> void:
	var t := sin(_float_time * 5.0) * 0.5 + 0.5   # 0~1 震荡
	for i in _pieces.size():
		if i >= _piece_mats.size():
			break
		var mat := _piece_mats[i] as StandardMaterial3D
		if mat == null:
			continue
		var orig    := Color(PIECE_DATA[i]["color"] as String)
		var blue    := Color(0.24, 0.67, 0.85)
		var blended := orig.lerp(blue, t * 0.45)
		blended.a    = mat.albedo_color.a
		mat.albedo_color = blended


func _clear_water_preview() -> void:
	# 恢复各块原色（保留当前 alpha）
	for i in _pieces.size():
		if i >= _piece_mats.size():
			break
		var mat := _piece_mats[i] as StandardMaterial3D
		if mat == null:
			continue
		var orig := Color(PIECE_DATA[i]["color"] as String)
		orig.a    = mat.albedo_color.a
		mat.albedo_color = orig


# ── 剪刀预览 ──────────────────────────────────────────────────────

func _create_outline_meshes() -> void:
	for i in _pieces.size():
		var verts: Array = PIECE_DATA[i]["verts"]

		# 构建闭合线框：顶点顺序 + 首顶点重复形成闭环
		var positions := PackedVector3Array()
		for gv in verts:
			positions.append(_grid_to_local(gv) + Vector3(0.0, 0.04, 0.0))  # 轻微上移防 z-fighting
		positions.append(_grid_to_local(verts[0]) + Vector3(0.0, 0.04, 0.0))

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions

		var arr_mesh := ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)

		var mat := StandardMaterial3D.new()
		mat.albedo_color             = Color(1.0, 1.0, 1.0, 0.8)
		mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled         = true
		mat.emission                 = Color(0.9, 0.9, 0.9)
		mat.emission_energy_multiplier = 0.6

		var mi    := MeshInstance3D.new()
		mi.name    = "OutlineMesh"
		mi.mesh    = arr_mesh
		mi.material_override = mat
		mi.visible = false
		_pieces[i].add_child(mi)
		_outline_meshes.append(mi)

	print("[connection] outline meshes created: ", _outline_meshes.size())


func _start_scissors_preview() -> void:
	for mi in _outline_meshes:
		if not is_instance_valid(mi):
			continue
		mi.visible = true
		# MeshInstance3D 无 modulate，直接操作材质 alpha
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			var c  := mat.albedo_color
			c.a    = 0.7
			mat.albedo_color = c


func _clear_scissors_preview() -> void:
	for mi in _outline_meshes:
		if is_instance_valid(mi):
			mi.visible = false


# 在 _update_still 中调用：轮廓线 alpha 随时间震荡（0.3~1.0）
func _update_scissors_preview_alpha() -> void:
	var alpha := sin(_float_time * 4.0) * 0.35 + 0.65
	for mi in _outline_meshes:
		if not is_instance_valid(mi):
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			var c  := mat.albedo_color
			c.a    = alpha
			mat.albedo_color = c


# ── 步骤 7-4：画框结局特效 ───────────────────────────────────────

func _create_frame_edges() -> void:
	var t   := 8.0
	var col := Color(0.52, 0.32, 0.14)   # 原木褐色
	var vp  := get_viewport().get_visible_rect().size

	# 上下横贯全屏宽；左右纵贯全屏高（位置在 _play_frame_ending 里定）
	var edge_data := [
		["FrameEdge_Top",    Vector2(vp.x, t)],
		["FrameEdge_Bottom", Vector2(vp.x, t)],
		["FrameEdge_Left",   Vector2(t, vp.y)],
		["FrameEdge_Right",  Vector2(t, vp.y)],
	]

	for data: Array in edge_data:
		var cr         := ColorRect.new()
		cr.name         = data[0]
		cr.color        = col
		cr.position     = Vector2(-2000.0, -2000.0)   # 隐藏到屏幕外，播放时再定位
		cr.size         = data[1]
		cr.modulate.a   = 0.0
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ending_ui.add_child(cr)
		_frame_edges.append(cr)


func _play_frame_ending() -> void:
	if _frame_edges.size() < 4:
		push_warning("[connection] frame edges not ready")
		_on_ending_fx_done("frame")
		return

	var t      := 8.0
	var vp     := get_viewport().get_visible_rect().size
	var dz_pos := _drop_zone.position if is_instance_valid(_drop_zone) else Vector2.ZERO

	# 各条边：全屏延伸，从屏幕外飞入，终止在 DropZone 对应边界
	# 上下：x=0 横贯全屏宽，Y 轴对齐 DropZone 上下边
	# 左右：y=0 纵贯全屏高，X 轴对齐 DropZone 左右边
	# [起点, 终点]
	var move_data := [
		[Vector2(0.0, -t - 20.0),                             Vector2(0.0, dz_pos.y)],                              # Top    从上方飞入
		[Vector2(0.0, vp.y + 20.0),                           Vector2(0.0, dz_pos.y + DROP_ZONE_SIZE.y - t)],       # Bottom 从下方飞入
		[Vector2(-t - 20.0, 0.0),                             Vector2(dz_pos.x, 0.0)],                              # Left   从左侧飞入
		[Vector2(vp.x + 20.0, 0.0),                           Vector2(dz_pos.x + DROP_ZONE_SIZE.x - t, 0.0)],       # Right  从右侧飞入
	]

	# 各条边：设置起点后淡入 + 合拢（EASE_OUT TRANS_BACK 轻微回弹）
	for i in _frame_edges.size():
		var cr: ColorRect = _frame_edges[i]
		if not is_instance_valid(cr):
			continue
		cr.position    = move_data[i][0]   # 先定位到起点
		var tw := create_tween()
		tw.tween_property(cr, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(cr, "position", move_data[i][1], 1.2) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 时序回调链
	var seq := create_tween()
	seq.tween_interval(1.3)
	seq.tween_callback(_frame_glow_pieces)
	seq.tween_interval(0.2)
	seq.tween_callback(func():
		var tool := _get_selected_tool("frame")
		if is_instance_valid(tool):
			create_tween().tween_property(tool, "modulate:a", 0.0, 0.3)
	)
	seq.tween_interval(0.7)
	seq.tween_callback(func(): _on_ending_fx_done("frame"))


# 画框合拢后：拼图各块 emission 轻微提升（玻璃感）
func _frame_glow_pieces() -> void:
	for mat in _piece_mats:
		var m := mat as StandardMaterial3D
		if m == null:
			continue
		m.emission_enabled           = true
		m.emission                   = Color(1.0, 0.97, 0.88)
		m.emission_energy_multiplier = 0.35


# ── 通用工具：按 tool_id 找到对应 Control ────────────────────────

func _get_selected_tool(tool_id: String) -> Control:
	for tool in _tools:
		if is_instance_valid(tool) and tool.get("tool_id") == tool_id:
			return tool as Control
	return null


# ── 结局完成收尾（三种结局共用）────────────────────────────────────

func _on_ending_fx_done(tool_id: String) -> void:
	var selected := _get_selected_tool(tool_id)
	if is_instance_valid(selected):
		selected.queue_free()
	print("[connection] ending done: ", tool_id)
	ending_done.emit(tool_id)   # 步骤八：触发字幕 + 配饰


# ── 步骤 7-5：水盆结局特效 ───────────────────────────────────────

func _create_noise_texture() -> void:
	var noise            := FastNoiseLite.new()
	noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency       = 0.04
	_noise_tex            = NoiseTexture2D.new()
	_noise_tex.width      = 256
	_noise_tex.height     = 256
	_noise_tex.generate_mipmaps = false
	_noise_tex.noise      = noise


func _play_water_ending() -> void:
	# ── A. 溶解 Shader（内嵌，用世界 XZ 坐标作为 UV）──────────────
	var dissolve_shader := Shader.new()
	dissolve_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D noise_tex  : source_color;
uniform float dissolve_cutoff : hint_range(0.0, 1.0) = 0.0;
uniform vec4  edge_color     : source_color = vec4(0.38, 0.70, 0.96, 1.0);
uniform vec4  piece_color    : source_color = vec4(1.0,  1.0,  1.0,  1.0);

varying vec3 v_world;

void vertex() {
\tv_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
\tvec2  uv   = v_world.xz / 24.0 + 0.5;
\tfloat n    = texture(noise_tex, uv).r;
\tif (n < dissolve_cutoff) { discard; }
\tfloat edge = smoothstep(dissolve_cutoff, dissolve_cutoff + 0.06, n);
\tALBEDO   = mix(edge_color.rgb, piece_color.rgb, edge);
\tALPHA    = 1.0;
\tEMISSION = edge_color.rgb * (1.0 - edge) * 1.8;
}
"""

	# ── B. 替换每块材质 + 建粒子 ──────────────────────────────────
	for i in _pieces.size():
		var piece := _pieces[i] as MeshInstance3D
		if not is_instance_valid(piece):
			continue

		# 原色
		var orig_color := Color(PIECE_DATA[i]["color"] as String)

		# 创建独立 ShaderMaterial
		var mat := ShaderMaterial.new()
		mat.shader = dissolve_shader
		mat.set_shader_parameter("noise_tex",   _noise_tex)
		mat.set_shader_parameter("piece_color", orig_color)
		mat.set_shader_parameter("edge_color",  Color(0.38, 0.70, 0.96, 1.0))
		mat.set_shader_parameter("dissolve_cutoff", 0.0)
		piece.material_override = mat
		_piece_mats[i]          = mat   # 同步引用，_clear_water_preview 中 as StandardMaterial3D 会返回 null（安全）

		# 粒子：蓝色小球从拼图块重心上方漂起
		var center := _piece_centroid_ground(i)
		var p      := _make_water_ripple(center, orig_color)
		add_child(p)
		p.emitting = true   # 立即开始发射

	# ── C. 各块溶解 Tween（独立随机时序）─────────────────────────
	for i in _pieces.size():
		var piece := _pieces[i] as MeshInstance3D
		if not is_instance_valid(piece):
			continue
		var mat     := piece.material_override as ShaderMaterial
		if mat == null:
			continue
		var delay    := randf_range(0.2, 0.6)
		var duration := randf_range(2.2, 2.7)
		var tw       := create_tween()
		tw.tween_interval(delay)
		tw.tween_method(
			func(v: float): mat.set_shader_parameter("dissolve_cutoff", v),
			0.0, 1.0, duration
		).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# ── D. 回调链 ─────────────────────────────────────────────────
	var seq := create_tween()
	seq.tween_interval(3.3)
	seq.tween_callback(func():
		var tool := _get_selected_tool("water")
		if is_instance_valid(tool):
			create_tween().tween_property(tool, "modulate:a", 0.0, 0.3)
	)
	seq.tween_interval(0.5)
	seq.tween_callback(func(): _on_ending_fx_done("water"))


# 计算第 i 块拼图的地面重心（用于粒子起点）
func _piece_centroid_ground(idx: int) -> Vector3:
	var verts: Array = PIECE_DATA[idx]["verts"]
	var sum   := Vector2.ZERO
	for v: Vector2 in verts:
		sum += v
	var avg := sum / verts.size()
	var pos := _grid_to_local(avg)
	return Vector3(pos.x, 0.5, pos.z)


# 建一个水波粒子节点（SphereMesh 小球，蓝色，朝上漂浮）
func _make_water_ripple(center: Vector3, piece_col: Color) -> GPUParticles3D:
	var p             := GPUParticles3D.new()
	p.amount           = 24
	p.lifetime         = 2.2
	p.one_shot         = true
	p.explosiveness    = 0.2
	p.emitting         = false

	var pm                    := ParticleProcessMaterial.new()
	pm.emission_shape          = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents    = Vector3(2.5, 0.05, 2.5)
	pm.direction               = Vector3(0.0, 1.0, 0.0)
	pm.spread                  = 25.0
	pm.initial_velocity_min    = 0.4
	pm.initial_velocity_max    = 1.2
	pm.gravity                 = Vector3(0.0, -0.2, 0.0)
	pm.scale_min               = 0.06
	pm.scale_max               = 0.14
	# 颜色：原色与蓝色各半混合，保留与拼图的关联感
	pm.color = piece_col.lerp(Color(0.38, 0.70, 0.96), 0.55)
	p.process_material = pm

	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color             = pm.color
	mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled         = true
	mat.emission                 = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.9
	sphere.surface_set_material(0, mat)
	p.draw_passes = 1
	p.set_draw_pass_mesh(0, sphere)
	p.position = center
	return p


# ── 步骤 7-6：剪刀结局特效 ───────────────────────────────────────

func _play_scissors_ending() -> void:
	# ── A. 轮廓线闪亮（快速亮起 → 短暂保持 → 淡出）──────────────────
	for mi in _outline_meshes:
		if not is_instance_valid(mi):
			continue
		mi.visible = true
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		# 局部捕获，避免 for 循环闭包问题
		var _mat: StandardMaterial3D = mat
		var _mi:  MeshInstance3D     = mi
		var tw   := create_tween()
		tw.tween_method(func(a: float):
			var c := _mat.albedo_color; c.a = a; _mat.albedo_color = c
			_mat.emission_energy_multiplier = lerpf(0.6, 2.4, a),
			0.6, 1.0, 0.12)
		tw.tween_interval(0.28)
		tw.tween_method(func(a: float):
			var c := _mat.albedo_color; c.a = a; _mat.albedo_color = c
			_mat.emission_energy_multiplier = a * 1.2,
			1.0, 0.0, 0.85)
		tw.tween_callback(func(): if is_instance_valid(_mi): _mi.visible = false)

	# ── B. 七块拼图各自随机方向缓慢飘散 + 透明淡出 ──────────────────
	for i in _pieces.size():
		var piece := _pieces[i] as MeshInstance3D
		if not is_instance_valid(piece):
			continue
		var mat := _piece_mats[i] as StandardMaterial3D
		if mat == null:
			continue

		# 随机飘散参数
		var angle    := randf() * TAU
		var dist_xz  := randf_range(4.0, 8.0)
		var rise     := randf_range(0.5, 2.0)
		var drift    := Vector3(cos(angle) * dist_xz, rise, sin(angle) * dist_xz)
		var delay    := randf_range(0.0, 0.5)
		var duration := randf_range(2.0, 2.8)
		var target   := piece.position + drift

		# 局部捕获
		var _i     := i
		var _piece := piece

		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(_piece, "position", target, duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_method(
			func(a: float): set_piece_alpha(_i, a),
			1.0, 0.0, duration
		)

	# ── C. 时序回调链 ──────────────────────────────────────────────
	var seq := create_tween()
	seq.tween_interval(4.3)
	seq.tween_callback(func():
		var tool := _get_selected_tool("scissors")
		if is_instance_valid(tool):
			create_tween().tween_property(tool, "modulate:a", 0.0, 0.3)
	)
	seq.tween_interval(0.5)
	seq.tween_callback(func(): _on_ending_fx_done("scissors"))
