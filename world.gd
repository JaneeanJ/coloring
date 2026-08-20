extends Node3D

signal player_fell   # 退出动画完成、玩家被重置前发出，供 costume_manager 监听

# =========================
# 台阶参数（与设计书 3.3 一致）
# =========================
const STEP_SIZE := Vector3(6, 0.15, 1.0)
const STEP_RISE := 0.60          # 每级 Y 增量
const STEP_RUN := 0.90           # 每级 Z 减量
const STEP_X := 3.0              # 台阶中轴

# Identity 区域世界坐标（路左侧，更远处）
const IDENTITY_CENTER := Vector3(-14.0, 0.0, -40.0)

# Connection 区域世界坐标（路右侧，更远处；Identity Z=-40，此处 Z=-100）
const CONNECTION_CENTER := Vector3(16.0, 0.0, -100.0)

# Eros 区域世界坐标（路左侧，Connection 之后）
const EROS_CENTER := Vector3(-80.0, 0.0, -250.0)

# Order 区域世界坐标（路右侧，路延长段末端，Eros 之前）
const ORDER_CENTER := Vector3(20.0, 0.0, -215.0)

# Creation 区域世界坐标（路左侧，Eros 之后；四首歌区域以此为原点中心展开）
const CREATION_CENTER   := Vector3(-40.0, 0.0, -320.0)
const CONSTANTS_CENTER  := Vector3( 40.0, 0.0, -350.0)
const VARIABLES_CENTER  := Vector3( -2.5, 0.0, -430.0)   # Force08 对齐主道路中心轴

# 无限台阶滚动窗口（方案 B：以鹿/玩家中较靠前者为参照）
const STEPS_AHEAD := 40          # 参照物前方保持的台阶数
const STEPS_BEHIND := 20         # 落后台阶超过此数则回收

# 出生点：台阶旁的空地（与边缘错开）
const SPAWN := Vector3(-4.0, 2.0, 0.0)      # 出生点：楼梯旁边的路上（Force1 起点）

# 退出淡出（Step 6）：无字，只有一层柔和暖光
const FADE_TIME := 1.8
var _fade_rect: ColorRect
var _exit_state := 0             # 0=空闲 1=淡出 2=淡入
var _fade_t := 0.0

# 脚边生长的「新花」：随离开进度冒出，提交离开时向上长高包裹玩家
const BLOOM_MAX := 18            # 最多长出的花朵数
const BLOOM_RADIUS := 2.2        # 环绕玩家脚边的半径
const BLOOM_TALL := 7.0          # 包裹时向上生长的倍数
var _bloom := []                 # Array[MeshInstance3D]

var _player: Node3D
var _player_skeleton: Skeleton3D
var _deer: Node3D
var _ground: Node3D              # 跟随玩家的无尽地面
var _flowers: MultiMeshInstance3D  # 下方花海（占位），跟随玩家
var _steps := {}                 # 活跃台阶：index -> StaticBody3D
var _next_index := 0             # 下一个待生成的台阶编号（只增不减）

# 天气系统：玩家有效攀登 → 世界从冷灰渐染暖色；停下/下行 → 缓缓褪去
const WEATHER_GAIN      := 0.08  # 有效攀登上色速度（约 12s 爬满）
const WEATHER_FADE_IDLE := 0.04  # 站着慢褪
const WEATHER_FADE_DOWN := 0.10  # 下行稍快
const WEATHER_FADE_BAND := 0.12  # 踏入花带中等褪（取代原 ×4 极端）
const VTREND_DEADZONE_W := 0.3   # 竖直趋势死区（单位/秒）
const VTREND_WINDOW_W   := 0.4   # 滑动窗口长度（秒）
const ON_STAIRS_Y_W     := 1.0   # 在台阶上的高度判定

var _weather        := 0.0       # 0=冷灰未名 … 1=暖梦满色
var _vtrend_w       := 0         # +1 升 / 0 平 / -1 降
var _win_start_y_w  := 0.0       # 滑动窗口起点 Y
var _sample_t_w     := 0.0       # 滑动窗口计时

var _identity_root:    Node3D    # Identity 场景根节点
var _connection_root:  Node3D    # Connection 场景根节点
var _eros_root:        Node3D    # Eros 场景根节点
var _order_root:       Node3D    # Order 场景根节点
var _creation_root:    Node3D    # Creation 场景根节点
var _constants_root:   Node3D    # Constants 场景根节点
var _variables_root:   Node3D    # Variables 场景根节点（Force 08）

var _step_mat: ShaderMaterial    # 全体台阶共享，靠 progress 统一驱动
var _rail_mat: ShaderMaterial    # 扶手独立材质，贴图与台阶分离
var _env: Environment
var _sky_mat: ProceduralSkyMaterial

# 连续扶手：独立于台阶生成，两条长斜板跟随玩家滚动
var _rail_left:  Node3D
var _rail_right: Node3D


func _ready():

	print("Welcome to Coloring")

	create_environment()

	_setup_step_material()

	_setup_rail_material()

	create_ground()

	create_flowers()

	create_player()
	
	create_deer()

	create_ramp()

	_create_continuous_railings()

	create_fade_ui()

	_fill_initial_stairs()

	_create_path()

	_create_identity()

	_create_connection()

	_create_eros()

	_create_order()

	_create_creation()
	_create_constants()
	_create_variables()

	create_behavior()

	create_costume_manager()

	_win_start_y_w = _player.position.y


# 行为识别器（Step 5）：解耦的独立 Node，只读世界状态、打印埋点
func create_behavior():

	var behavior = Node.new()
	behavior.name = "BehaviorRecognizer"
	behavior.set_script(load("res://behavior.gd"))  # core/ 暂留根目录
	add_child(behavior)


func create_costume_manager():

	var behavior = get_node_or_null("BehaviorRecognizer")
	if behavior == null:
		push_warning("costume_manager: BehaviorRecognizer not found")
		return

	var mgr = Node.new()
	mgr.name = "CostumeManager"
	mgr.set_script(load("res://costume/costume_manager.gd"))
	add_child(mgr)

	# 连线：行为信号 + 掉落信号 + 一瞥结束信号
	behavior.state_changed.connect(mgr.on_state_changed)
	player_fell.connect(mgr.on_player_fell)
	if _deer:
		_deer.glance_finished.connect(mgr.on_glance_finished)

	# 创建 UI 层并连接到 CostumeManager
	var ui = CanvasLayer.new()
	ui.name = "CostumeUI"
	ui.set_script(load("res://costume/costume_ui.gd"))
	add_child(ui)
	mgr.costume_triggered.connect(ui.on_costume_triggered)
	ui.sequence_started.connect(_on_costume_sequence_started)
	ui.sequence_finished.connect(_on_costume_sequence_finished)

	# 创建服装视觉层
	if _player_skeleton:
		var wardrobe = Node.new()
		wardrobe.name = "CostumeWardrobe"
		wardrobe.set_script(load("res://costume/costume_wardrobe.gd"))
		add_child(wardrobe)
		wardrobe.setup(_player_skeleton)
		mgr.costume_triggered.connect(wardrobe.on_costume_triggered)
	else:
		push_warning("CostumeWardrobe: player Skeleton3D not found")

	# 步骤八：Connection 结局完成后触发字幕 + 配饰
	if _connection_root and _connection_root.has_signal("ending_done"):
		_connection_root.ending_done.connect(mgr.on_connection_ending)


func _process(delta):

	_update_stairs()

	_update_ground()

	_update_flowers()

	_update_railings()

	_update_weather(delta)

	_update_bloom(delta)

	_update_exit(delta)


# 花海跟随玩家水平位置（占位）→ 始终铺在下方
func _update_flowers():

	if _flowers == null or _player == null:
		return

	_flowers.position.x = _player.position.x
	_flowers.position.z = _player.position.z


# 地面始终跟随玩家水平位置 → 看起来无边无际
func _update_ground():

	if _ground == null or _player == null:
		return

	_ground.position.x = _player.position.x
	_ground.position.z = _player.position.z



# =========================
# 创建地面
# =========================

func create_ground():

	var ground = StaticBody3D.new()

	ground.name = "Ground"


	# 地面模型
	var mesh = MeshInstance3D.new()

	var box = BoxMesh.new()

	box.size = Vector3(200, 0.2, 200)

	mesh.mesh = box

	ground.add_child(mesh)



	# 地面碰撞
	var collision = CollisionShape3D.new()

	var shape = BoxShape3D.new()

	shape.size = Vector3(200, 0.2, 200)

	collision.shape = shape

	ground.add_child(collision)



	# 地面高度
	ground.position = Vector3(0, -0.1, 0)


	add_child(ground)

	_ground = ground




# =========================
# 下方花海（占位：MultiMesh 撒一片彩色小花）
# =========================

func create_flowers():

	# 单朵占位：一根细长竖条（茎/花），靠 per-instance 颜色变斑斓
	var blade = BoxMesh.new()
	blade.size = Vector3(0.08, 0.4, 0.08)


	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade

	var count := 6000
	var half := 120.0            # 撒布半径
	mm.instance_count = count

	for i in range(count):

		var s := randf_range(0.6, 1.5)          # 高矮不一

		var basis := Basis()
		basis = basis.rotated(Vector3.UP, randf() * TAU)
		basis = basis.scaled(Vector3(1.0, s, 1.0))

		var pos := Vector3(
			randf_range(-half, half),
			0.4 * s * 0.5,                       # 底部贴地
			randf_range(-half, half)
		)

		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, Color.from_hsv(randf(), randf_range(0.55, 0.9), randf_range(0.8, 1.0)))


	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9


	_flowers = MultiMeshInstance3D.new()
	_flowers.name = "Flowers"
	_flowers.multimesh = mm
	_flowers.material_override = mat
	_flowers.position = Vector3(0, 0, 0)

	add_child(_flowers)




# =========================
# 创建玩家
# =========================

func create_player():

	var player = CharacterBody3D.new()

	player.name = "Player"


	# 初始位置
	player.position = SPAWN


	# 玩家脚本
	player.set_script(load("res://player.gd"))  # core/ 暂留根目录

	player.add_to_group("player")



	# 玩家模型
	var char_scene = load("res://models/player/character_base.fbx").instantiate()
	char_scene.scale = Vector3(1.4, 1.4, 1.4)  # 视实际大小在此调整
	char_scene.rotation_degrees.y = 180        # 背面朝向摄像机
	player.add_child(char_scene)
	_player_skeleton = char_scene.get_node_or_null("Armature/Skeleton3D") as Skeleton3D

	# 玩家碰撞
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	collision.shape = shape
	player.add_child(collision)

	# AnimationPlayer 获取 + 动画库注册
	var anim: AnimationPlayer = char_scene.get_node_or_null("AnimationPlayer")
	if anim:
		anim.add_animation_library("idle",       load("res://models/player/character_idle.fbx"))
		anim.add_animation_library("walk",       load("res://models/player/character_walk.fbx"))
		anim.add_animation_library("stairs",     load("res://models/player/character_ascending_stairs.fbx"))
		anim.add_animation_library("drink",      load("res://models/player/character_drink.fbx"))
		anim.add_animation_library("drunk_idle", load("res://models/player/character_drunk_idle.fbx"))
		anim.add_animation_library("drunk_walk", load("res://models/player/character_drunk_walk.fbx"))
		anim.add_animation_library("raise",      load("res://models/player/character_raise.fbx"))
		anim.add_animation_library("sitting",    load("res://models/player/character_sitting.fbx"))
		anim.play("idle/mixamo_com")
		player.set("_anim", anim)
	else:
		push_warning("player: AnimationPlayer not found")



	# =====================
	# 摄像机
	# =====================

	var camera = Camera3D.new()


	# 相对玩家位置
	camera.position = Vector3(0, 5, 8)


	player.add_child(camera)


	camera.current = true


	# 加入世界

	add_child(player)

	_player = player


	# 看向玩家（须在进入场景树后调用）
	camera.look_at(player.global_position + Vector3(0, 1, 0))
	
	
func create_deer():

	var deer = CharacterBody3D.new()

	deer.name = "SeekingDeer"

	deer.position = Vector3(3,0.5,1)


	deer.set_script(load("res://entities/deer.gd"))


	# 鹿模型
	var deer_scene = load("res://models/deer/deer.glb").instantiate()
	deer_scene.rotation_degrees.y = 180
	deer_scene.scale = Vector3(0.6, 0.6, 0.6)
	deer.add_child(deer_scene)

	# 播放 idle 动画
	var anim: AnimationPlayer = deer_scene.get_node_or_null("AnimationPlayer")
	if anim:
		anim.play("Animation")
	else:
		push_warning("deer: AnimationPlayer not found at Armature/AnimationPlayer")


	# 碰撞
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 0.8
	collision.shape = shape
	deer.add_child(collision)
	add_child(deer)

	_deer = deer


# =========================
# 无限台阶（方案 B：滚动生成 / 回收）
# =========================

# 扶手参数
const RAIL_WALL_HEIGHT := 1.6    # 护墙高度
const RAIL_WALL_THICK  := 0.18   # 护墙厚度
const RAIL_TOP_R       := 0.07   # 顶部扶手杆半径（用细 BoxMesh 模拟）
const RAIL_TOP_H       := 0.10   # 顶部扶手杆截面高度

# 生成第 i 级台阶（踏板 + 踢面 + 扶手墙，碰撞交给隐形斜坡）
func _spawn_step(i: int):

	if i < 0:        # 不在反方向生成台阶
		return
	if _steps.has(i):
		return

	# 根节点：方便整体回收
	var step := Node3D.new()
	step.name = "Step_" + str(i)
	step.position = Vector3(STEP_X, i * STEP_RISE, -i * STEP_RUN)
	add_child(step)

	# ── 实心台阶块 ────────────────────────────────────────
	# 高度 = STEP_RISE，顶面对齐步节点 Y（local y = 0），
	# 底面 = (i-1)*STEP_RISE，恰好接住下一级顶面，无缝无悬空
	var tread := MeshInstance3D.new()
	var tread_box := BoxMesh.new()
	tread_box.size = Vector3(STEP_SIZE.x, STEP_RISE, STEP_SIZE.z)
	tread.mesh = tread_box
	tread.material_override = _step_mat
	tread.position = Vector3(0.0, -STEP_RISE * 0.5, 0.0)
	step.add_child(tread)

	_steps[i] = step


# =========================
# 连续扶手系统（独立于台阶，两条长斜板跟随玩家）
# =========================

# 每侧扶手 = 静态长斜板，从第 0 级延伸到第 RAIL_TOTAL_STEPS 级
# 不跟随玩家，不随进度消失
const RAIL_TOTAL_STEPS := 500    # 覆盖约 500 级，足够整场游戏

func _create_continuous_railings():

	var slope_angle := atan2(STEP_RISE, STEP_RUN)
	var diag        := sqrt(STEP_RISE * STEP_RISE + STEP_RUN * STEP_RUN)
	var rail_len    := RAIL_TOTAL_STEPS * diag   # 全长覆盖 0~500 级

	# 中心在第 RAIL_TOTAL_STEPS/2 级对应的坡面位置
	var center_step := RAIL_TOTAL_STEPS / 2.0
	var center_y    := center_step * STEP_RISE
	var center_z    := -center_step * STEP_RUN

	for side in [-1, 1]:
		var x_off := STEP_X + float(side) * (STEP_SIZE.x * 0.5 + RAIL_WALL_THICK * 0.5)

		var node := Node3D.new()
		node.name = "Rail_" + ("L" if side == -1 else "R")
		node.rotation.x = slope_angle
		node.position    = Vector3(x_off, center_y, center_z)
		add_child(node)

		# ── 护墙板 ──────────────────────────────────────────
		var wall      := MeshInstance3D.new()
		var wall_box  := BoxMesh.new()
		wall_box.size  = Vector3(RAIL_WALL_THICK, RAIL_WALL_HEIGHT, rail_len)
		wall.mesh      = wall_box
		wall.material_override = _rail_mat
		wall.position  = Vector3(0.0, RAIL_WALL_HEIGHT * 0.5, 0.0)
		node.add_child(wall)

		# ── 顶部扶手杆 ──────────────────────────────────────
		var top_rail     := MeshInstance3D.new()
		var top_box      := BoxMesh.new()
		top_box.size      = Vector3(RAIL_WALL_THICK + 0.08, RAIL_TOP_H, rail_len)
		top_rail.mesh     = top_box
		top_rail.material_override = _rail_mat
		top_rail.position = Vector3(0.0, RAIL_WALL_HEIGHT + RAIL_TOP_H * 0.5, 0.0)
		node.add_child(top_rail)

		if side == -1:
			_rail_left  = node
		else:
			_rail_right = node


# 扶手静态，无需每帧更新
func _update_railings():
	pass


# 隐形斜坡：为玩家提供可行走的连续物理表面（约 40°，可攀爬）
# 视觉上是台阶，物理上是一条长斜面；鹿是脚本驱动，不受影响
func create_ramp():

	var ramp = StaticBody3D.new()

	ramp.name = "StairRamp"


	var collision = CollisionShape3D.new()

	var shape = BoxShape3D.new()

	# 沿斜面方向足够长，一次游玩内走不到头
	shape.size = Vector3(STEP_SIZE.x, 0.2, 4000.0)

	collision.shape = shape

	ramp.add_child(collision)


	# 斜坡中心放在台阶中段，绕 X 轴旋转到与台阶同坡度
	var center_index := 500.0

	ramp.position = Vector3(
		STEP_X,
		center_index * STEP_RISE,
		-center_index * STEP_RUN
	)

	ramp.rotation.x = atan(STEP_RISE / STEP_RUN)

	add_child(ramp)


# 由 Z 坐标推算所处台阶编号
func _index_from_z(z: float) -> int:
	return int(round(-z / STEP_RUN))


# 开局先铺满参照物前方的窗口
func _fill_initial_stairs():
	for i in range(_next_index, STEPS_AHEAD + 1):
		_spawn_step(i)
		_next_index = i + 1


# 每帧维护滚动窗口：前方补齐、身后回收
func _update_stairs():

	if _player == null or _deer == null:
		return

	var player_index := _index_from_z(_player.position.z)
	var deer_index := _index_from_z(_deer.position.z)

	var front_index: int = max(player_index, deer_index)
	var back_index: int = min(player_index, deer_index)


	# 前方补齐（clamp 到 0，不向反方向生成）
	var target: int = max(0, front_index + STEPS_AHEAD)
	while _next_index <= target:
		_spawn_step(_next_index)
		_next_index += 1


	# 身后回收（以较落后者为准，避免删掉谁脚下的台阶）
	var cutoff: int = back_index - STEPS_BEHIND
	for i in _steps.keys():
		if i < cutoff:
			_steps[i].queue_free()
			_steps.erase(i)


# =========================
# 上色系统 + 氛围
# =========================

# 全体台阶共享的材质：progress=0 时灰，越大越沿高度染出颜色
func _setup_step_material():

	var shader := Shader.new()
	shader.code = """
shader_type spatial;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cold = vec3(0.74, 0.73, 0.71);
	vec3 gold = vec3(1.00, 0.84, 0.32);

	// 世界坐标 UV：贴图在世界空间中平铺，不受面朝向影响
	// 0.06 → 每 ~16 单位重复一次，台阶（宽6）显示约半张图案
	vec2 uv = v_world.xz * 0.06;
	vec3 tex = texture(albedo_tex, uv).rgb;

	// progress=0 时显示轻微去饱和的贴图（而非纯灰），让纹路始终可见
	float luma = dot(tex, vec3(0.299, 0.587, 0.114));
	vec3 tex_desat = mix(vec3(luma) * 0.7, tex, 0.25);   // 暗淡去色版
	vec3 base = mix(tex_desat, tex, progress);

	// 自发光：只取贴图最亮区域，强度压低，避免过曝
	float glow_mask = smoothstep(0.72, 0.92, luma);
	float h_glow = clamp(v_world.y * 0.02, 0.0, 0.28);   // 封顶降至 0.28

	ALBEDO    = base;
	ROUGHNESS = mix(0.90, 0.60, progress);               // 最低粗糙度 0.60，抑制高光
	METALLIC  = glow_mask * progress * 0.2;
	EMISSION  = gold * glow_mask * progress * h_glow * 0.09;  // 系数 0.18 → 0.09
}
"""

	_step_mat = ShaderMaterial.new()
	_step_mat.shader = shader
	_step_mat.set_shader_parameter("progress", 0.0)

	var marble := load("res://textures/step_marble.png") as Texture2D
	if marble:
		_step_mat.set_shader_parameter("albedo_tex", marble)
	else:
		push_warning("step_marble.png not found, using procedural color only")


# 扶手专属 shader：用网格 UV 包裹贴图，不受世界坐标投影影响
# uv_tile.x = 高度方向平铺次数，uv_tile.y = 长度方向平铺次数
func _setup_rail_material():

	var rail_shader := Shader.new()
	rail_shader.code = """
shader_type spatial;

uniform float progress  : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_tile = vec2(1.0, 60.0);   // x=高度方向, y=长度方向

void fragment() {
	vec2 uv = UV * uv_tile;
	vec3 tex  = texture(albedo_tex, uv).rgb;

	vec3 gold = vec3(1.00, 0.84, 0.32);

	float luma       = dot(tex, vec3(0.299, 0.587, 0.114));
	vec3  tex_desat  = mix(vec3(luma) * 0.7, tex, 0.25);
	vec3  base       = mix(tex_desat, tex, progress);

	float glow_mask  = smoothstep(0.72, 0.92, luma);

	ALBEDO    = base;
	ROUGHNESS = mix(0.90, 0.60, progress);
	METALLIC  = glow_mask * progress * 0.15;
	EMISSION  = gold * glow_mask * progress * 0.06;
}
"""

	_rail_mat = ShaderMaterial.new()
	_rail_mat.shader = rail_shader
	_rail_mat.set_shader_parameter("progress", 0.0)
	_rail_mat.set_shader_parameter("uv_tile", Vector2(1.0, 60.0))

	# 优先加载专属贴图 rail.png；不存在则回退到台阶贴图
	var rail_tex := load("res://textures/rail.png") as Texture2D
	if rail_tex:
		_rail_mat.set_shader_parameter("albedo_tex", rail_tex)
	else:
		var marble := load("res://textures/step_marble.png") as Texture2D
		if marble:
			_rail_mat.set_shader_parameter("albedo_tex", marble)
		push_warning("rail.png not found, falling back to step_marble.png")


# 渐变天空 + 雾 + 环境光
func create_environment():

	var world_env := WorldEnvironment.new()

	var env := Environment.new()

	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = _sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	env.fog_enabled = true
	env.fog_density = 0.015

	world_env.environment = env
	add_child(world_env)

	_env = env

	_apply_weather()


# 天气驱动：滑动窗口判「有效攀登」→ 六条规则更新 weather
func _update_weather(delta: float):

	if _player == null:
		return

	# 滑动窗口：每 VTREND_WINDOW_W 秒更新一次竖直趋势
	_sample_t_w += delta
	if _sample_t_w >= VTREND_WINDOW_W:
		var rate: float = (_player.global_position.y - _win_start_y_w) / _sample_t_w
		if rate > VTREND_DEADZONE_W:
			_vtrend_w = 1
		elif rate < -VTREND_DEADZONE_W:
			_vtrend_w = -1
		else:
			_vtrend_w = 0
		_win_start_y_w = _player.global_position.y
		_sample_t_w = 0.0

	var in_band: bool = _player.get("in_band")
	var frozen:  bool = _player.get("frozen")
	var on_stairs: bool = _player.position.y > ON_STAIRS_Y_W

	# 那一瞥期间冻结 weather，世界颜色维持住
	if frozen:
		return

	# 有效攀登：在台阶上、不在花带、竖直趋势向上
	var climbing: bool = on_stairs and not in_band and _vtrend_w == 1

	if climbing:
		_weather += WEATHER_GAIN * delta
	elif in_band:
		_weather -= WEATHER_FADE_BAND * delta
	elif _vtrend_w == -1:
		_weather -= WEATHER_FADE_DOWN * delta
	else:
		_weather -= WEATHER_FADE_IDLE * delta

	_weather = clamp(_weather, 0.0, 1.0)
	_apply_weather()


# 将 weather 映射到三路输出：台阶色 / 天空 / 雾色
func _apply_weather():

	var step_t: float = smoothstep(0.0, 1.0, _weather)   # S 曲线，台阶中段最明显
	var sky_t:  float = pow(_weather, 0.85)               # 天空略提前暖

	# 台阶材质
	if _step_mat != null:
		_step_mat.set_shader_parameter("progress", step_t)

	# 扶手材质（同步 progress，贴图独立）
	if _rail_mat != null:
		_rail_mat.set_shader_parameter("progress", step_t)

	# 天空配色：冷灰 → 暖金白（对齐象牙/暖金调）
	if _sky_mat != null:
		var top     := Color(0.24, 0.24, 0.26).lerp(Color(0.98, 0.92, 0.72), sky_t)
		var horizon := Color(0.46, 0.45, 0.43).lerp(Color(1.00, 0.96, 0.78), sky_t)
		_sky_mat.sky_top_color        = top
		_sky_mat.sky_horizon_color    = horizon
		_sky_mat.ground_horizon_color = horizon
		_sky_mat.ground_bottom_color  = Color(0.30, 0.28, 0.26).lerp(Color(0.96, 0.88, 0.65), sky_t)

	# 雾色（密度在 Step 8.2 动态化，此处保持基底）
	if _env != null:
		_env.fog_light_color = Color(0.55, 0.54, 0.52).lerp(Color(1.00, 0.95, 0.78), sky_t)


# =========================
# 退出：飘落沉入后淡出 → 回出生点重生
# =========================

func create_fade_ui():

	var layer := CanvasLayer.new()

	# 无字：只有一层柔和暖光，随花海升起而弥漫
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.97, 0.94, 0.92, 0.0)   # 柔和暖白
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)

	add_child(layer)


# 脚边的新花：随离开进度冒出；提交离开时向上长高，把玩家温柔地包起来
func _update_bloom(delta):

	if _player == null:
		return

	var lp = _player.get("leave_progress")
	var leaving = _player.get("leaving")

	# 目标数量随离开进度增长；提交离开后拉满
	var target := int(round(lp * BLOOM_MAX))
	if leaving:
		target = BLOOM_MAX

	# 需要更多 → 在玩家脚边长出新花
	while _bloom.size() < target:
		_spawn_bloom_flower()

	# 进度回落（走回主道）→ 多余的花收回（可逆）
	while _bloom.size() > target and not leaving:
		var f = _bloom.pop_back()
		if is_instance_valid(f):
			f.queue_free()

	# 生长：离开时逐渐向上长高包裹；平常保持矮小
	var grow := 1.0
	if leaving:
		grow = 1.0 + clamp(_fade_t / FADE_TIME, 0.0, 1.0) * BLOOM_TALL

	for fl in _bloom:
		if is_instance_valid(fl):
			fl.scale.y = lerp(fl.scale.y, grow, delta * 4.0)


func _spawn_bloom_flower():

	var f := MeshInstance3D.new()

	var box := BoxMesh.new()
	box.size = Vector3(0.1, randf_range(0.4, 0.8), 0.1)
	f.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(randf(), randf_range(0.6, 0.95), 1.0)
	f.material_override = mat

	# 环绕玩家脚边随机撒布，基点固定在提交/停留处
	var ang := randf() * TAU
	var r: float = sqrt(randf()) * BLOOM_RADIUS
	var base: Vector3 = _player.position
	f.position = Vector3(
		base.x + cos(ang) * r,
		base.y - 0.4,
		base.z + sin(ang) * r
	)

	add_child(f)
	_bloom.append(f)


func _clear_bloom():
	for f in _bloom:
		if is_instance_valid(f):
			f.queue_free()
	_bloom.clear()


# 花海向上包裹 → 暖光淡出 → 回出生点 → 淡入（全程无字）
func _update_exit(delta):

	if _fade_rect == null or _player == null:
		return

	match _exit_state:

		0:
			if _player.get("leaving"):
				_exit_state = 1
				_fade_t = 0.0

		1:
			_fade_t += delta
			var a: float = clamp(_fade_t / FADE_TIME, 0.0, 1.0)
			_fade_rect.color.a = a
			if a >= 1.0:
				_clear_bloom()
				player_fell.emit()
				_player.call("reset_to", SPAWN)
				# 重生后天气归零，世界干净回到冷灰起点
				_weather = 0.0
				_vtrend_w = 0
				_win_start_y_w = SPAWN.y
				_sample_t_w = 0.0
				_apply_weather()
				_exit_state = 2
				_fade_t = 0.0

		2:
			_fade_t += delta
			var a2: float = 1.0 - clamp(_fade_t / FADE_TIME, 0.0, 1.0)
			_fade_rect.color.a = a2
			if a2 <= 0.0:
				_exit_state = 0


# =========================
# 路径 + Identity 占位
# =========================

# 路面：连接出生点与楼梯的小路，视觉上区分主道与地面
# 路沿 Z 轴延伸，Seeking 楼梯在路右侧（+X），Identity 在路左侧更远（-X）
func _create_path() -> void:

	# ── 路面板 ──────────────────────────────────────────────────
	var path_mesh := MeshInstance3D.new()
	path_mesh.name = "PathSurface"
	var box := BoxMesh.new()
	box.size = Vector3(4.5, 0.06, 800.0)  # 从 Z≈+6 延伸到 Z≈-794（覆盖 Force08 全段）
	path_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.50, 0.47)
	mat.roughness    = 0.92
	path_mesh.material_override = mat
	path_mesh.position = Vector3(-2.5, 0.03, -394.0)  # 居中：(+6 到 -794) / 2 = -394
	add_child(path_mesh)

	# ── 路边石块（纯视觉）──────────────────────────────────────
	_spawn_path_stone(Vector3(-5.2, 0.13,  -2.5), 0.20)
	_spawn_path_stone(Vector3(-0.2, 0.18,  -9.5), 0.22)
	_spawn_path_stone(Vector3(-5.0, 0.15, -16.0), 0.17)
	# 原段（Z -50 ~ -110）
	_spawn_path_stone(Vector3(-0.3, 0.16, -52.0), 0.19)
	_spawn_path_stone(Vector3(-5.1, 0.14, -68.0), 0.21)
	_spawn_path_stone(Vector3(-0.4, 0.17, -84.0), 0.18)
	# 延长段一（Z -120 ~ -185，通向 Order 入口）
	_spawn_path_stone(Vector3(-5.2, 0.13, -122.0), 0.19)
	_spawn_path_stone(Vector3(-0.3, 0.16, -138.0), 0.21)
	_spawn_path_stone(Vector3(-5.0, 0.15, -155.0), 0.18)
	_spawn_path_stone(Vector3(-0.4, 0.17, -172.0), 0.20)
	# 延长段二（Z -190 ~ -285，Order Z=-215、通向 Eros Z=-250）
	_spawn_path_stone(Vector3(-5.2, 0.13, -193.0), 0.20)
	_spawn_path_stone(Vector3(-0.3, 0.16, -210.0), 0.18)
	_spawn_path_stone(Vector3(-5.0, 0.15, -228.0), 0.21)
	_spawn_path_stone(Vector3(-0.4, 0.17, -245.0), 0.19)
	_spawn_path_stone(Vector3(-5.1, 0.14, -262.0), 0.20)
	_spawn_path_stone(Vector3(-0.3, 0.16, -278.0), 0.17)
	# 延长段三（Z -290 ~ -320，通向 Creation 入口）
	_spawn_path_stone(Vector3(-5.2, 0.13, -293.0), 0.19)
	_spawn_path_stone(Vector3(-0.3, 0.16, -308.0), 0.18)
	_spawn_path_stone(Vector3(-5.0, 0.15, -318.0), 0.20)
	# 延长段四（Z -330 ~ -445，通向 Constants 入口）
	_spawn_path_stone(Vector3(-5.2, 0.13, -333.0), 0.20)
	_spawn_path_stone(Vector3(-0.3, 0.16, -348.0), 0.18)
	_spawn_path_stone(Vector3(-5.0, 0.15, -363.0), 0.21)
	_spawn_path_stone(Vector3(-0.4, 0.17, -378.0), 0.19)
	_spawn_path_stone(Vector3(-5.1, 0.14, -393.0), 0.20)
	_spawn_path_stone(Vector3(-0.3, 0.16, -408.0), 0.18)
	_spawn_path_stone(Vector3(-5.0, 0.15, -423.0), 0.21)
	_spawn_path_stone(Vector3(-0.4, 0.17, -438.0), 0.19)

	print("[path] extended to Z=-450, Constants at ", CONSTANTS_CENTER)


func _create_connection() -> void:
	var connection := Node3D.new()
	connection.name = "Connection"
	connection.set_script(load("res://forces/connection.gd"))
	connection.position = CONNECTION_CENTER
	add_child(connection)
	_connection_root = connection


func _create_eros() -> void:
	var eros := Node3D.new()
	eros.name = "Eros"
	eros.set_script(load("res://forces/eros.gd"))
	eros.position = EROS_CENTER
	add_child(eros)
	_eros_root = eros


func _create_identity() -> void:
	var identity := Node3D.new()
	identity.name = "Identity"
	identity.set_script(load("res://forces/identity.gd"))
	identity.position = IDENTITY_CENTER
	add_child(identity)
	_identity_root = identity


func _create_order() -> void:
	var order := Node3D.new()
	order.name = "Order"
	order.set_script(load("res://forces/force_05_order.gd"))
	order.position = ORDER_CENTER
	add_child(order)
	_order_root = order


func _create_creation() -> void:
	var creation := Node3D.new()
	creation.name = "Creation"
	creation.set_script(load("res://forces/force_06_creation.gd"))
	creation.position = CREATION_CENTER
	add_child(creation)
	_creation_root = creation


func _create_constants() -> void:
	var constants := Node3D.new()
	constants.name = "Constants"
	constants.set_script(load("res://forces/force_07_constants.gd"))
	constants.position = CONSTANTS_CENTER
	add_child(constants)
	_constants_root = constants


func _create_variables() -> void:
	var variables := Node3D.new()
	variables.name = "Variables"
	variables.set_script(load("res://forces/force_08_variables.gd"))
	variables.position = VARIABLES_CENTER
	add_child(variables)
	_variables_root = variables



func _spawn_path_stone(pos: Vector3, radius: float) -> void:
	var stone := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.6   # 略扁
	stone.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.42, 0.40)
	mat.roughness    = 1.0
	stone.material_override = mat
	stone.position = pos
	add_child(stone)


# 字幕开始：暂停鹿的移动
func _on_costume_sequence_started(_event_name: String) -> void:
	if _deer:
		_deer.set("paused", true)


# 字幕结束：恢复鹿的移动；obsession 结局额外重置玩家
func _on_costume_sequence_finished(event_name: String) -> void:
	if _deer:
		_deer.set("paused", false)
	if event_name == "obsession" and _player:
		_player.call("reset_to", SPAWN)
