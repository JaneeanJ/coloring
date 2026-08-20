extends Node3D

# FORCE 04 — Eros（爱欲）/ 《酒海》场景控制器

enum ErosState { ROAMING, ISLAND, SHIP, DRIFTING, ENDING }
var state: ErosState = ErosState.ROAMING

const SEA_WIDTH    := 130.0   # 海面宽度（X方向）：覆盖岛(-40)到船(+35)两侧各留余量
const SEA_LENGTH   := 90.0    # 海面长度（Z方向）：玩家入场(Z≈75)到岛/船前(Z≈0)
const SEA_OFFSET_X := -2.5    # 海面中心X（岛-40与船+35之间）
const SEA_OFFSET_Z := 42.0    # 海面中心Z（入场Z≈75与岛Z≈0之间）
const ROSE_COUNT   := 120
const ROSE_SCALE   := 1.5

var _player: Node3D
var _splash_particles: GPUParticles3D
var _step_accum := 0.0          # 累计行走距离，用于按步触发水花
var dye_system: Node            # 染色系统，步骤六各结局调用

const STEP_DIST := 1.4          # 每走约 1.4m（约两步）触发一次

# 醉意系统（步骤五）
const MAX_DRUNK            := 10
const DRUNK_ANIM_THRESHOLD := 3     # 达到此值切换醉酒 idle/walk
const HOLD_BASE            := 2.0   # 长按基础阈值（秒）
const HOLD_PER_LEVEL       := 0.5   # 每级醉意增加的阈值
const DRINK_LINES := [
	"想再靠近一点。",
	"你的轮廓，越来越清晰。",
	"脚下，好像轻了一点。",
	"玫瑰，好像在为谁开。",
	"我想抵达谁的心里，来着？",
	"话，说不完整了。",
	"分不清，是海，还是你。",
	"好像，不需要抵达了。",
	"我，还是海？",
]
var _drunk_level   := 0
var _hold_time     := 0.0
var _is_holding    := false
var _drink_locked  := false   # 饮酒动画播放中，防叠加
var _drink_line_label: Label
var _drink_line_tween: Tween

# 小岛
const ISLAND_POS    := Vector3(-25.0, 0.8, 55.0)   # 相对 eros 节点的本地坐标（Y>0.55 才露出液面）
const ISLAND_SCALE  := 0.07                         # 岛屿模型缩放（GLB 原始单位过大，调小后微调此值）
const ISLAND_BOX    := Vector3(14.0, 3.0, 14.0)    # Area3D 碰撞盒（包住岛屿顶面 + 站立玩家）
const ISLAND_BOX_Y  := 1.0                          # 碰撞盒中心上移，使底部贴近岛面
var _island_root: Node3D

# 小岛道具（相对 _island_root 的本地坐标）
# 玩家从 +Z 方向靠近小岛，道具摆在近侧（Z=+4）
const INTERACT_RADIUS   := 4.0                       # 点灯/浇水触发半径
const INTERACT_COOLDOWN := 0.5                       # 重复触发冷却（秒），防边缘抖动
const ENDING_RADIUS     := 3.0                       # 结局触发感应半径
# NPC 并肩位置（NPC 在 X=-5，并肩偏右一点）
const ENDING_AREA_POS   := Vector3(-4.5, ISLAND_PROP_Y, 9.5)
const NPC_SCALE         := 0.018                     # NPC 缩放：比玩家(1.4)稍大，微调此值
const LAMP_SCALE        := 0.5                       # 灯缩放
const FLOWER_SCALE      := 1.4                       # 花盆缩放
const ISLAND_SURFACE_Y  := 6.0                       # 玩家碰撞地板高度（_island_root 本地坐标）
const ISLAND_PROP_Y     := 1.4                       # 道具独立Y，单独对齐沙面视觉，与地板无关
const ISLAND_FLOOR_SIZE := Vector3(20.0, 1.0, 20.0) # 隐形碰撞地板尺寸
const NPC_POS           := Vector3(-5.0, ISLAND_PROP_Y, 9.5)
const NPC_ROT_Y         := 0.0
const LAMP_POS          := Vector3(-3.5, ISLAND_PROP_Y + 0.5, 9.5)   # 灯稍高，偏左
const FLOWER_POS        := Vector3( 0.5, ISLAND_PROP_Y,       9.5)   # 花稍右
var _npc_node: Node3D
var _lamp_glow: OmniLight3D       # 灯交互专用光晕（平时 energy=0）
var _flower_glow: OmniLight3D     # 花盆交互粉光（平时 energy=0）
var _flower_mesh: Node3D          # 花盆根节点，用于呼吸缩放
var _is_playing_action     := false   # 防止动作叠加
var _lamp_cooldown         := 0.0     # 灯冷却计时
var _flower_cooldown       := 0.0     # 花盆冷却计时
var _player_in_ending_area := false   # 玩家是否在结局感应区内
var _is_triggering_ending  := false   # 结局进行中，阻断所有交互
var _ending_prompt: Label             # 占位提示 Label，步骤六替换为 costume_ui

# 船（步骤四）
const BOAT_POS         := Vector3(35.0, 2.5, 55.0)    # 小岛右侧（eros 本地坐标）
const BOAT_ROT_Y       := deg_to_rad(-40.0)            # 船绕 Y 轴的偏转角（斜放）
const BOAT_SCALE       := 1.2                           # 船模型缩放
const BOAT_SURFACE_Y   := 1.0                           # 甲板高度（_boat_root 本地坐标）
const BOAT_FLOOR_SIZE  := Vector3(10.0, 1.0, 10.0)     # 隐形碰撞地板
const BOAT_BOARD_RADIUS := 4.0                          # 登船感应半径
const BOAT_EXIT_POS    := Vector3(0.0, BOAT_SURFACE_Y, -4.0)   # 船尾离船点（本地坐标）
const BOAT_EXIT_RADIUS := 2.5
const BOAT_SPEED       := 3.0              # 船自动前进速度（m/s）
const BOAT_TURN_SPEED  := 0.8              # A/D 转向速度（rad/s）
const BOARD_TWEEN_T    := 0.6              # 登船传送动画时长（秒）
const LIGHT_INTERVAL   := 4.0             # 发光点生成间隔（秒）
const BEACON_RANGE     := 55.0            # 发光点生成半径（世界单位）
const PASSING_DIST     := 5.0             # 擦肩触发距离
const HELM_POS         := Vector3(0.0, BOAT_SURFACE_Y, 3.0)   # 船舵位置（_boat_root 本地坐标）
var _boat_root: Node3D
var _sea_body: Node3D       # 海面根节点，跟随船 XZ 位置
var _player_on_sea := false # 玩家是否在海面上（用于限制喝酒）
var _player_near_boat    := false   # 玩家在登船感应区内
var _player_at_boat_exit := false   # 玩家在离船区内
var _boat_prompt: Label
var _drink_prompt: Label
var _boat_exit_prompt: Label
# 4-3：发光点系统
var _beacon_root: Node3D        # 发光点根节点（含 OmniLight3D + Mesh）
var _beacon_light: OmniLight3D  # 发光点光源
var _beacon_mesh: MeshInstance3D  # 发光点球体，流星拖尾用
var _light_timer   := 0.0       # 距下次生成的计时器
var _passing_done  := false     # 是否已经历过一次擦肩
var _helm_prompt: Label         # 船舵处结局提示


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set("disable_leave", true)
	_create_sea()
	_create_roses()
	_setup_splash()
	_create_sea_fog()
	_create_liquid_surface()
	_setup_dye_system()
	_create_island()
	_create_boat()
	_create_beacon()
	_setup_interact_action()
	_create_ending_prompt()
	_create_drink_prompt()
	_create_drink_line_label()
	print("[eros] ready")


func _process(delta: float) -> void:
	match state:
		ErosState.ROAMING:   _process_roaming(delta)
		ErosState.ISLAND:    pass
		ErosState.SHIP:      _process_ship(delta)
		ErosState.DRIFTING:  pass
		ErosState.ENDING:    pass


func _process_roaming(delta: float) -> void:
	# 水花（仅在海面区域内触发）
	if _splash_particles and _player and _player_on_sea:
		var h_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		if h_speed > 0.3:
			_step_accum += h_speed * delta
			if _step_accum >= STEP_DIST:
				_step_accum = 0.0
				_splash_particles.emitting = true
		else:
			_step_accum = 0.0
	elif not _player_on_sea:
		_step_accum = 0.0   # 离开海面时重置累计，避免回来立刻触发
	# 交互冷却倒计时
	if _lamp_cooldown   > 0.0: _lamp_cooldown   -= delta
	if _flower_cooldown > 0.0: _flower_cooldown -= delta
	# 醉意输入
	_process_drunk_input(delta)


# =============================================================
# 调试标记球（确认位置用，后续删除）
# =============================================================


# =============================================================
# 酒海地面
# =============================================================

func _create_sea() -> void:
	var body  := StaticBody3D.new()
	body.name  = "SeaBody"
	# X 偏移使右边缘对齐路左侧（X≈-5），Y=0.04 低于路面顶部避免遮路
	body.position = Vector3(SEA_OFFSET_X, 0.04, SEA_OFFSET_Z)

	# 视觉平面
	var mesh  := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size             = Vector2(SEA_WIDTH, SEA_LENGTH)
	mesh.mesh              = plane
	var mat                := StandardMaterial3D.new()
	mat.albedo_color       = Color(0.0, 0.22, 0.6)
	mat.emission_enabled   = true
	mat.emission           = Color(0.0, 0.08, 0.35)
	mat.emission_energy_multiplier = 0.6
	mat.roughness          = 0.2
	mat.metallic           = 0.1
	mesh.material_override = mat
	# 防 frustum culling：PlaneMesh AABB 高度为零，快速转向时会被误剔除
	# custom_aabb 给 Y 方向一个足够大的范围，让引擎始终认为它在视野内
	mesh.custom_aabb = AABB(
		Vector3(-SEA_WIDTH * 0.5, -20.0, -SEA_LENGTH * 0.5),
		Vector3(SEA_WIDTH, 40.0, SEA_LENGTH)
	)
	body.add_child(mesh)

	# 碰撞：平面三角网格，无侧壁，玩家可从路边直接走上来
	var col   := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var hw    := SEA_WIDTH  * 0.5
	var hl    := SEA_LENGTH * 0.5
	shape.set_faces(PackedVector3Array([
		Vector3(-hw, 0.0, -hl), Vector3( hw, 0.0, -hl), Vector3( hw, 0.0,  hl),
		Vector3(-hw, 0.0, -hl), Vector3( hw, 0.0,  hl), Vector3(-hw, 0.0,  hl),
	]))
	col.shape  = shape
	body.add_child(col)

	# Area3D：检测玩家是否在海面上（仅海平面高度，排除路面/岛屿）
	var sea_area   := Area3D.new()
	sea_area.name  = "SeaArea"
	var sa_col     := CollisionShape3D.new()
	var sa_box     := BoxShape3D.new()
	sa_box.size    = Vector3(SEA_WIDTH, 0.6, SEA_LENGTH)
	sa_col.shape   = sa_box
	sa_col.position = Vector3(0.0, 0.3, 0.0)   # 薄层：Y=0.04~0.64，排除高处的路/岛
	sea_area.add_child(sa_col)
	sea_area.body_entered.connect(_on_sea_entered)
	sea_area.body_exited.connect(_on_sea_exited)
	body.add_child(sea_area)

	add_child(body)
	_sea_body = body


# =============================================================
# 玫瑰散布
# =============================================================

func _create_roses() -> void:
	var rose_scene := load("res://models/rose/RedRose.glb") as PackedScene
	if rose_scene == null:
		push_warning("[eros] RedRose.glb 加载失败")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	for i in range(ROSE_COUNT):
		var rose              := rose_scene.instantiate()
		rose.scale            = Vector3.ONE * ROSE_SCALE
		rose.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		rose.position = Vector3(
			SEA_OFFSET_X + rng.randf_range(-SEA_WIDTH  * 0.45, SEA_WIDTH  * 0.45),
			1.35,
			SEA_OFFSET_Z + rng.randf_range(-SEA_LENGTH * 0.45, SEA_LENGTH * 0.45)
		)
		add_child(rose)


# =============================================================
# B — 脚步水花（GPUParticles3D，挂载在玩家脚部）
# =============================================================

func _setup_splash() -> void:
	if _player == null:
		return

	_splash_particles = GPUParticles3D.new()
	_splash_particles.name        = "FootSplash"
	# 发射量：一次爆发 12 粒，lifetime=0.5s，单次爆发模式
	_splash_particles.amount      = 12
	_splash_particles.lifetime    = 0.5
	_splash_particles.explosiveness = 0.85   # 聚集在帧首发射（更像水花）
	_splash_particles.emitting    = false
	_splash_particles.one_shot    = true   # 每次触发一次爆发，不持续喷射
	# 抬到液面以上（液面 world Y=0.55，玩家原点在脚底约 Y=0.04）
	_splash_particles.position    = Vector3(0.0, 0.6, 0.0)

	var pmat := ParticleProcessMaterial.new()
	# 发射形状：扁球形（水平扩散）
	pmat.emission_shape           = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius   = 0.25
	# 速度
	pmat.initial_velocity_min     = 0.6
	pmat.initial_velocity_max     = 1.8
	# 方向：主要向上，但扁平展开
	pmat.direction                = Vector3(0.0, 1.0, 0.0)
	pmat.spread                   = 60.0       # 上方 60° 锥形
	pmat.flatness                 = 0.7        # 压扁到水平面
	# 重力：向下拉弧
	pmat.gravity                  = Vector3(0.0, -4.0, 0.0)
	# 颜色：深蓝
	pmat.color                    = Color(0.05, 0.22, 0.72, 0.88)
	# 粒子尺寸：更大，出生稍大再渐隐
	var size_curve               := Curve.new()
	size_curve.add_point(Vector2(0.0, 0.55))
	size_curve.add_point(Vector2(0.35, 0.65))
	size_curve.add_point(Vector2(1.0, 0.0))
	var size_tex                 := CurveTexture.new()
	size_tex.curve               = size_curve
	pmat.scale_curve             = size_tex

	_splash_particles.process_material = pmat

	# draw_pass_1 必须设置，否则粒子完全不可见
	var droplet              := SphereMesh.new()
	droplet.radius           = 0.11
	droplet.height           = 0.22
	var droplet_mat          := StandardMaterial3D.new()
	droplet_mat.vertex_color_use_as_albedo = true   # 让 pmat.color 生效
	droplet_mat.emission_enabled           = true
	droplet_mat.emission                   = Color(0.0, 0.18, 0.65)  # 深蓝发光
	droplet_mat.emission_energy_multiplier = 0.9    # 柔和，不刺眼
	droplet_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	droplet.material                       = droplet_mat
	_splash_particles.draw_pass_1          = droplet

	_player.add_child(_splash_particles)


# =============================================================
# C — 海面薄雾（FogVolume + 启用体积雾）
# =============================================================

func _create_sea_fog() -> void:
	# 1. 全局体积雾：极淡大气感，关闭时域重投影（消除闪烁）
	var world_env: WorldEnvironment = null
	for child in get_parent().get_children():
		if child is WorldEnvironment:
			world_env = child
			break
	if world_env and world_env.environment:
		var env := world_env.environment
		env.volumetric_fog_enabled                       = true
		env.volumetric_fog_density                       = 0.004  # 极淡，仅做大气底色
		env.volumetric_fog_albedo                        = Color(0.0, 0.08, 0.3)
		env.volumetric_fog_emission                      = Color(0.0, 0.02, 0.1)
		env.volumetric_fog_emission_energy               = 0.12
		env.volumetric_fog_temporal_reprojection_enabled = false   # 关闭后消除频闪

	# 2. FogVolume：覆盖小腿高度，密度降低让水花透出
	#    中心 Y=0.35（海面+小腿中段），高度 0.65 → 顶部约 Y=0.68
	var fog_vol          := FogVolume.new()
	fog_vol.name         = "SeaFog"
	fog_vol.position     = Vector3(SEA_OFFSET_X, 0.5, SEA_OFFSET_Z)
	fog_vol.size         = Vector3(SEA_WIDTH, 0.9, SEA_LENGTH)

	var fmat             := FogMaterial.new()
	fmat.density         = 1.2   # 原 3.5 → 1.2，水花可透出
	fmat.albedo          = Color(0.0, 0.15, 0.55)
	fmat.emission        = Color(0.0, 0.04, 0.18)
	fog_vol.material     = fmat

	add_child(fog_vol)


# =============================================================
# B2 — 液面分界平面（给大脑"腿在水里"的视觉锚点）
# =============================================================

func _create_liquid_surface() -> void:
	var surf             := MeshInstance3D.new()
	surf.name            = "LiquidSurface"

	var plane            := PlaneMesh.new()
	plane.size           = Vector2(SEA_WIDTH, SEA_LENGTH)
	# 细分让发光边缘更平滑
	plane.subdivide_width  = 4
	plane.subdivide_depth  = 4
	surf.mesh            = plane

	var mat              := StandardMaterial3D.new()
	# 半透明：alpha 够高才能看到分界线
	mat.transparency          = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color          = Color(0.0, 0.22, 0.68, 0.50)
	# 发光让液面本身有"荧光酒液"质感
	mat.emission_enabled      = true
	mat.emission              = Color(0.0, 0.10, 0.40)
	mat.emission_energy_multiplier = 0.45
	# 轻微菲涅耳：斜视时更不透明，模拟液体反射
	mat.rim_enabled           = true
	mat.rim                   = 0.4
	mat.rim_tint              = 0.6
	# 正反面均渲染（玩家进入液面以下时也能看到）
	mat.cull_mode             = BaseMaterial3D.CULL_DISABLED
	surf.material_override    = mat

	# Y=0.55：小腿中段，雾顶 ≈ Y=0.95 在其上继续填充朦胧感
	surf.position = Vector3(SEA_OFFSET_X, 0.55, SEA_OFFSET_Z)

	add_child(surf)


# =============================================================
# 步骤 3-1 — 小岛放置 + 上岛状态切换
# =============================================================

func _create_island() -> void:
	_island_root = Node3D.new()
	_island_root.name = "Island"
	_island_root.position = ISLAND_POS
	add_child(_island_root)

	# 岛屿模型
	var island_scene := load("res://models/island/island.glb") as PackedScene
	if island_scene == null:
		push_warning("[eros] island.glb 加载失败")
	else:
		var island_mesh := island_scene.instantiate()
		island_mesh.scale = Vector3.ONE * ISLAND_SCALE
		_island_root.add_child(island_mesh)

	# Area3D：覆盖岛屿顶面，检测玩家进出
	var area       := Area3D.new()
	area.name       = "IslandArea"
	var col        := CollisionShape3D.new()
	var shape      := BoxShape3D.new()
	shape.size      = ISLAND_BOX
	col.shape       = shape
	col.position    = Vector3(0.0, ISLAND_BOX_Y, 0.0)
	area.add_child(col)
	area.body_entered.connect(_on_island_entered)
	area.body_exited.connect(_on_island_exited)
	_island_root.add_child(area)

	_create_island_floor()
	_create_island_props()


func _create_island_floor() -> void:
	# 隐形 StaticBody3D：顶面对齐沙面视觉高度，让玩家/NPC 可以站稳
	var floor_body  := StaticBody3D.new()
	floor_body.name  = "IslandFloor"
	var col         := CollisionShape3D.new()
	var shape       := BoxShape3D.new()
	shape.size       = ISLAND_FLOOR_SIZE
	col.shape        = shape
	# 盒子顶面 = ISLAND_SURFACE_Y → 中心下移半个盒高
	col.position     = Vector3(0.0, ISLAND_SURFACE_Y - ISLAND_FLOOR_SIZE.y * 0.5, 0.0)
	floor_body.add_child(col)
	_island_root.add_child(floor_body)


func _create_island_props() -> void:
	# —— NPC ——
	var npc_scene := load("res://models/island_npc/island.glb") as PackedScene
	if npc_scene:
		_npc_node = npc_scene.instantiate()
		_npc_node.name = "IslandNPC"
		_npc_node.scale = Vector3.ONE * NPC_SCALE
		_npc_node.position = NPC_POS
		_npc_node.rotation_degrees.y = NPC_ROT_Y
		_island_root.add_child(_npc_node)
		# 播放内嵌 idle 动画（名称按实际 glb 内容）
		var anim := _npc_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim and anim.get_animation_list().size() > 0:
			anim.play(anim.get_animation_list()[0])
		else:
			push_warning("[eros] island_npc: AnimationPlayer 未找到或无动画")
	else:
		push_warning("[eros] island_npc/island.glb 加载失败")

	# —— 灯 ——
	var lamp_scene := load("res://models/island_lamp/lamp.glb") as PackedScene
	if lamp_scene:
		var lamp := lamp_scene.instantiate()
		lamp.name = "IslandLamp"
		lamp.scale = Vector3.ONE * LAMP_SCALE
		lamp.position = LAMP_POS
		_island_root.add_child(lamp)
		# 专用光晕（平时 energy=0，交互时脉冲）
		_lamp_glow = OmniLight3D.new()
		_lamp_glow.light_energy = 0.0
		_lamp_glow.omni_range   = 4.0
		_lamp_glow.light_color  = Color(1.0, 0.85, 0.4)
		lamp.add_child(_lamp_glow)
		# 触发 Area3D
		_island_root.add_child(_make_interact_area(LAMP_POS, "_on_lamp_entered", "_on_lamp_exited"))
	else:
		push_warning("[eros] island_lamp/lamp.glb 加载失败")

	# —— 花盆 ——
	var flower_scene := load("res://models/island_flower/flower.glb") as PackedScene
	if flower_scene:
		var flower := flower_scene.instantiate()
		flower.name = "IslandFlower"
		flower.scale = Vector3.ONE * FLOWER_SCALE
		flower.position = FLOWER_POS
		_island_root.add_child(flower)
		_flower_mesh = flower
		# 专用粉光（平时 energy=0，交互时脉冲）
		_flower_glow = OmniLight3D.new()
		_flower_glow.light_energy = 0.0
		_flower_glow.omni_range   = 4.0
		_flower_glow.light_color  = Color(1.0, 0.5, 0.75)   # 粉色
		flower.add_child(_flower_glow)
		# 触发 Area3D
		_island_root.add_child(_make_interact_area(FLOWER_POS, "_on_flower_entered", "_on_flower_exited"))
	else:
		push_warning("[eros] island_flower/flower.glb 加载失败")

	_create_island_ending_area()


# =============================================================
# 步骤 3-3 / 3-4 — 日常交互（点灯 + 浇水）
# =============================================================

# 通用辅助：生成一个球形 Area3D，信号连到 self 上的方法名
func _make_interact_area(pos: Vector3, on_enter: String, on_exit: String) -> Area3D:
	var area   := Area3D.new()
	var col    := CollisionShape3D.new()
	var shape  := SphereShape3D.new()
	shape.radius = INTERACT_RADIUS
	col.shape    = shape
	col.position = pos
	area.add_child(col)
	area.body_entered.connect(Callable(self, on_enter))
	area.body_exited.connect(Callable(self, on_exit))
	return area


func _on_lamp_entered(body: Node3D) -> void:
	if body != _player or _is_playing_action or _lamp_cooldown > 0.0:
		return
	_is_playing_action = true
	_lamp_cooldown = INTERACT_COOLDOWN
	_pulse_lamp_glow()
	await get_tree().create_timer(0.8).timeout
	_is_playing_action = false


func _on_lamp_exited(_body: Node3D) -> void:
	pass   # 冷却由 _process_roaming 计时，无需 exited 处理


func _pulse_lamp_glow() -> void:
	if _lamp_glow == null:
		return
	var tween := create_tween()
	tween.tween_property(_lamp_glow, "light_energy", 2.5, 0.15)
	tween.tween_property(_lamp_glow, "light_energy", 0.0, 0.6)


func _on_flower_entered(body: Node3D) -> void:
	if body != _player or _is_playing_action or _flower_cooldown > 0.0:
		return
	_is_playing_action = true
	_flower_cooldown = INTERACT_COOLDOWN
	_breathe_flower()
	await get_tree().create_timer(0.8).timeout
	_is_playing_action = false


func _on_flower_exited(_body: Node3D) -> void:
	pass


func _breathe_flower() -> void:
	if _flower_mesh == null:
		return
	var orig  := _flower_mesh.scale
	var tween := create_tween()
	tween.tween_property(_flower_mesh, "scale", orig * 1.05, 0.5)
	tween.tween_property(_flower_mesh, "scale", orig,        0.5)
	# 粉光脉冲：与呼吸同步，膨胀时亮起，收缩时渐灭
	if _flower_glow:
		var glow_tween := create_tween()
		glow_tween.tween_property(_flower_glow, "light_energy", 2.0, 0.3)
		glow_tween.tween_property(_flower_glow, "light_energy", 0.0, 0.7)


func _on_island_entered(body: Node3D) -> void:
	if body != _player:
		return
	state = ErosState.ISLAND
	if _drink_prompt: _drink_prompt.visible = false
	print("[eros] state=ISLAND")


func _on_island_exited(body: Node3D) -> void:
	if body != _player:
		return
	# 仅在 ISLAND 状态下回退，防止结局中误触发
	if state == ErosState.ISLAND:
		state = ErosState.ROAMING
		if _drink_prompt and _player_on_sea: _drink_prompt.visible = true
		print("[eros] state=ROAMING")


# =============================================================
# 步骤 4-1 — 船体放置 + 登船检测
# =============================================================

func _create_boat() -> void:
	_boat_root = Node3D.new()
	_boat_root.name = "Boat"
	_boat_root.position = BOAT_POS
	_boat_root.rotation.y = BOAT_ROT_Y
	add_child(_boat_root)

	# 船体模型
	var boat_scene := load("res://models/island_boat/celtic_music_boat.glb") as PackedScene
	if boat_scene:
		var boat_mesh := boat_scene.instantiate()
		boat_mesh.scale = Vector3.ONE * BOAT_SCALE
		_boat_root.add_child(boat_mesh)
	else:
		push_warning("[eros] celtic_music_boat.glb 加载失败")

	# 隐形甲板碰撞（玩家站稳用）
	var floor_body := StaticBody3D.new()
	floor_body.name = "BoatFloor"
	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = BOAT_FLOOR_SIZE
	col.shape  = shape
	col.position = Vector3(0.0, BOAT_SURFACE_Y - BOAT_FLOOR_SIZE.y * 0.5, 0.0)
	floor_body.add_child(col)
	_boat_root.add_child(floor_body)

	# 登船感应 Area3D（以船为中心，半径 BOAT_BOARD_RADIUS）
	var board_area := Area3D.new()
	board_area.name = "BoardArea"
	var bc   := CollisionShape3D.new()
	var bs   := SphereShape3D.new()
	bs.radius = BOAT_BOARD_RADIUS
	bc.shape  = bs
	bc.position = Vector3(0.0, BOAT_SURFACE_Y, 0.0)
	board_area.add_child(bc)
	board_area.body_entered.connect(_on_boat_board_entered)
	board_area.body_exited.connect(_on_boat_board_exited)
	_boat_root.add_child(board_area)

	# 离船 Area3D（船尾）
	var exit_area := Area3D.new()
	exit_area.name = "BoatExitArea"
	var ec   := CollisionShape3D.new()
	var es   := SphereShape3D.new()
	es.radius = BOAT_EXIT_RADIUS
	ec.shape  = es
	ec.position = BOAT_EXIT_POS
	exit_area.add_child(ec)
	exit_area.body_entered.connect(_on_boat_exit_entered)
	exit_area.body_exited.connect(_on_boat_exit_exited)
	_boat_root.add_child(exit_area)


	# 提示 Label：登船
	_boat_prompt = _make_prompt_label("[ E ] 登船", -95.0)   # 登船在喝酒上方
	# 提示 Label：离船
	_boat_exit_prompt = _make_prompt_label("[ E ] 下船", -60.0)  # 下船在底部
	_boat_exit_prompt.visible = false


func _make_prompt_label(text: String, y_offset: float = -60.0) -> Label:
	var layer := CanvasLayer.new()
	var lbl   := Label.new()
	lbl.text  = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl.position.y += y_offset
	lbl.visible    = false
	layer.add_child(lbl)
	add_child(layer)
	return lbl


func _on_sea_entered(body: Node3D) -> void:
	if body == _player:
		_player_on_sea = true
		if _drink_prompt and not _is_triggering_ending:
			_drink_prompt.visible = true


func _on_sea_exited(body: Node3D) -> void:
	if body == _player:
		_player_on_sea = false
		if _drink_prompt:
			_drink_prompt.visible = false


func _on_boat_board_entered(body: Node3D) -> void:
	if body != _player or state == ErosState.SHIP or _is_triggering_ending:
		return
	_player_near_boat = true
	_boat_prompt.visible = true


func _on_boat_board_exited(body: Node3D) -> void:
	if body != _player:
		return
	_player_near_boat = false
	_boat_prompt.visible = false


func _on_boat_exit_entered(body: Node3D) -> void:
	if body != _player or state != ErosState.SHIP:
		return
	_player_at_boat_exit = true
	_boat_exit_prompt.visible = true


func _on_boat_exit_exited(body: Node3D) -> void:
	if body != _player:
		return
	_player_at_boat_exit = false
	_boat_exit_prompt.visible = false


# =============================================================
# 步骤 3-5 — 结局触发区域 + 提示 UI
# =============================================================

func _setup_interact_action() -> void:
	# 若 InputMap 中没有 interact 动作则动态注册，映射到 E 键
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev       := InputEventKey.new()
		ev.keycode    = KEY_E
		InputMap.action_add_event("interact", ev)

	# 远航专用交互键：F 键
	if not InputMap.has_action("sail"):
		InputMap.add_action("sail")
		var ev2      := InputEventKey.new()
		ev2.keycode   = KEY_F
		InputMap.action_add_event("sail", ev2)

	# 饮酒键：R 键
	if not InputMap.has_action("eros_drink"):
		InputMap.add_action("eros_drink")
		var ev3      := InputEventKey.new()
		ev3.keycode   = KEY_R
		InputMap.action_add_event("eros_drink", ev3)


func _create_drink_line_label() -> void:
	var layer := CanvasLayer.new()
	_drink_line_label = Label.new()
	_drink_line_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_drink_line_label.position.y    -= 130   # 台词在按键提示上方，不重叠
	_drink_line_label.position.x    -= 200   # 稍微靠左
	_drink_line_label.add_theme_font_size_override("font_size", 24)
	_drink_line_label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))  # 淡蓝白
	_drink_line_label.modulate.a = 0.0   # 初始透明
	_drink_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_drink_line_label)
	add_child(layer)


func _show_drink_line(text: String) -> void:
	if _drink_line_label == null:
		return
	# 打断上一句尚未淡完的动画
	if _drink_line_tween and _drink_line_tween.is_running():
		_drink_line_tween.kill()
	_drink_line_label.text      = text
	_drink_line_label.modulate.a = 0.0
	_drink_line_tween = create_tween()
	_drink_line_tween.tween_property(_drink_line_label, "modulate:a", 1.0, 0.3)
	_drink_line_tween.tween_interval(1.5)
	_drink_line_tween.tween_property(_drink_line_label, "modulate:a", 0.0, 0.3)


func _create_drink_prompt() -> void:
	_drink_prompt = _make_prompt_label("[ R ] 喝酒", -60.0)
	_drink_prompt.visible = false  # 只有踏上海面才显示


func _create_ending_prompt() -> void:
	# 占位 Label，步骤六换为正式 costume_ui 提示
	var layer         := CanvasLayer.new()
	_ending_prompt     = Label.new()
	_ending_prompt.text              = "[ E ] 共同眺望"
	_ending_prompt.add_theme_font_size_override("font_size", 22)
	_ending_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	_ending_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ending_prompt.position.y       -= 60   # 岛上结局提示，独占底部
	_ending_prompt.visible           = false
	layer.add_child(_ending_prompt)
	add_child(layer)


func _create_island_ending_area() -> void:
	var area   := Area3D.new()
	area.name   = "EndingArea"
	var col    := CollisionShape3D.new()
	var shape  := SphereShape3D.new()
	shape.radius = ENDING_RADIUS
	col.shape    = shape
	col.position = ENDING_AREA_POS
	area.add_child(col)
	area.body_entered.connect(_on_ending_area_entered)
	area.body_exited.connect(_on_ending_area_exited)
	_island_root.add_child(area)


func _on_ending_area_entered(body: Node3D) -> void:
	if body != _player or _is_triggering_ending:
		return
	_player_in_ending_area = true
	_ending_prompt.visible = true


func _on_ending_area_exited(body: Node3D) -> void:
	if body != _player:
		return
	_player_in_ending_area = false
	_ending_prompt.visible = false


func _input(event: InputEvent) -> void:
	# 远航结局（F 键）
	if event.is_action_pressed("sail"):
		if state == ErosState.SHIP and _passing_done and not _is_triggering_ending:
			_trigger_ending_ship()
		return

	if not event.is_action_pressed("interact"):
		return

	# 登船
	if _player_near_boat and state == ErosState.ROAMING and not _is_triggering_ending:
		state = ErosState.SHIP
		_boat_prompt.visible = false
		_player_near_boat    = false
		_player.set("frozen", true)
		# 传送动画：玩家滑向甲板中心
		var deck_world := _boat_root.to_global(Vector3(0.0, BOAT_SURFACE_Y + 0.1, 0.0))
		var tw := create_tween()
		tw.tween_property(_player, "global_position", deck_world, BOARD_TWEEN_T) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_boat_exit_prompt.visible = true
		_drink_prompt.visible     = false
		print("[eros] state=SHIP")
		return

	# 下船（E 任意时刻，未触发结局）
	if state == ErosState.SHIP and not _is_triggering_ending:
		var exit_world := _boat_root.to_global(BOAT_EXIT_POS)
		_player.global_position   = exit_world
		_player.set("frozen", false)
		_boat_exit_prompt.visible = false
		_drink_prompt.visible     = true
		state = ErosState.ROAMING
		print("[eros] state=ROAMING（下船）")
		return

	# 停泊结局
	if _player_in_ending_area and not _is_triggering_ending:
		_trigger_ending_island()


# =============================================================
# 步骤五 — 醉意系统
# =============================================================

func _process_drunk_input(delta: float) -> void:
	if _is_triggering_ending or not _player_on_sea:
		return

	if Input.is_action_pressed("eros_drink"):
		_is_holding = true
		_hold_time += delta
		# 长按进度：到阈值触发 Awake
		var threshold := HOLD_BASE + _drunk_level * HOLD_PER_LEVEL
		if _hold_time >= threshold:
			_trigger_awake()
	elif _is_holding:
		# 松键：短按判定
		if _hold_time < 0.3 and not _drink_locked:
			_drink()
		_hold_time  = 0.0
		_is_holding = false


func _drink() -> void:
	if _drunk_level >= MAX_DRUNK:
		return
	_drink_locked = true
	_drunk_level += 1
	print("[eros] drunk_level=", _drunk_level)

	# 喝酒台词（第1~9口，第10口直接触发结局不弹台词）
	if _drunk_level - 1 < DRINK_LINES.size():
		_show_drink_line(DRINK_LINES[_drunk_level - 1])

	# 播放饮酒动画（锁定玩家移动，await 动画结束后解冻）
	if _player and _player.has_method("play_one_shot"):
		_player.set("frozen", true)
		await _player.play_one_shot("drink")
		_player.set("frozen", false)

	# 切换醉酒 idle/walk
	if _drunk_level >= DRUNK_ANIM_THRESHOLD and _player:
		_player.set("drunk_anim", true)

	# 染色渐变
	if dye_system:
		dye_system.set_dye(float(_drunk_level) / MAX_DRUNK)

	_drink_locked = false

	if _drunk_level >= MAX_DRUNK:
		_trigger_drift()


func _trigger_drift() -> void:
	_is_triggering_ending = true
	state = ErosState.ENDING
	if _drink_prompt: _drink_prompt.visible = false
	if _player:
		_player.set("frozen", true)
	# 角色缓慢下沉
	var tw := create_tween()
	tw.tween_property(_player, "position:y", _player.position.y - 1.2, 3.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	var mgr := get_parent().get_node_or_null("CostumeManager") as Node
	if mgr:
		mgr.call("on_eros_ending", "eros_drift")
	print("[eros] ending=eros_drift")


func _trigger_awake() -> void:
	if _is_triggering_ending:
		return
	_is_triggering_ending = true
	if _drink_prompt: _drink_prompt.visible = false
	_is_holding = false
	_hold_time  = 0.0
	state = ErosState.ENDING
	if _player:
		_player.set("frozen", true)
	# 锁定当前染色
	if dye_system:
		dye_system.freeze()
	# 播放举手动画（0.5倍速放慢），播完后冻结姿势
	if _player and _player.has_method("play_one_shot"):
		await _player.play_one_shot("raise", true, 0.5)
	# 停留在举手姿势
	await get_tree().create_timer(3.0).timeout
	# 保持姿势飞升
	var tw := create_tween()
	tw.tween_property(_player, "position:y", _player.position.y + 1.5, 3.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	# 释放姿势锁定
	if _player:
		_player.set("_one_shot_active", false)
	var mgr := get_parent().get_node_or_null("CostumeManager") as Node
	if mgr:
		mgr.call("on_eros_ending", "eros_awake")
	print("[eros] ending=eros_awake")


func _process_ship(delta: float) -> void:
	if not _boat_root or not _player:
		return

	# 船自动向本地 -Z 方向前进
	var forward := -_boat_root.global_transform.basis.z.normalized()
	_boat_root.global_position += forward * BOAT_SPEED * delta

	# A/D 转向
	var turn := Input.get_axis("ui_left", "ui_right")
	_boat_root.rotation.y -= turn * BOAT_TURN_SPEED * delta

	# 玩家锁定在甲板中心，跟随船运动
	_player.global_position = _boat_root.to_global(Vector3(0.0, BOAT_SURFACE_Y + 0.1, 0.0))
	_player.rotation.y      = _boat_root.rotation.y

	# 海面跟随船 XZ，Y 保持原值，防止远航后露出边缘
	if _sea_body:
		var bp := _boat_root.global_position
		_sea_body.global_position = Vector3(bp.x, _sea_body.global_position.y, bp.z)

	# 发光点循环
	_process_light_beacon(delta)


# =============================================================
# 步骤 4-3 — 发光点循环 + 擦肩演出
# =============================================================

func _create_beacon() -> void:
	# 根节点（默认隐藏，出现时定位到世界位置）
	_beacon_root = Node3D.new()
	_beacon_root.name    = "Beacon"
	_beacon_root.visible = false
	add_child(_beacon_root)

	# 光晕
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color          = Color(0.9, 0.95, 1.0)   # 冷白
	_beacon_light.light_energy         = 3.0
	_beacon_light.omni_range           = 12.0
	_beacon_root.add_child(_beacon_light)

	# 小球 Mesh
	var mi   := MeshInstance3D.new()
	var sm   := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.4
	mi.mesh   = sm
	var mat   := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.85, 0.95, 1.0)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.85, 0.95, 1.0)
	mat.emission_energy_multiplier = 4.0
	mi.material_override           = mat
	_beacon_root.add_child(mi)
	_beacon_mesh = mi

	# 船舵结局提示（默认隐藏，擦肩后显示）；y_offset -90 与下船提示错开一行
	_helm_prompt = _make_prompt_label("[ F ] 远航", -95.0)   # 远航在下船上方
	_helm_prompt.visible = false


func _process_light_beacon(delta: float) -> void:
	if _is_triggering_ending:
		return

	# 发光点隐藏时计时，到时间后在船前方随机方向生成
	if not _beacon_root.visible:
		_light_timer += delta
		if _light_timer >= LIGHT_INTERVAL:
			_light_timer = 0.0
			# 沿船头前方方向生成，左右随机偏转 ±30°
			var forward := -_boat_root.global_transform.basis.z.normalized()
			var jitter  := deg_to_rad(randf_range(-30.0, 30.0))
			forward = forward.rotated(Vector3.UP, jitter)
			_beacon_root.global_position = _boat_root.global_position + forward * BEACON_RANGE
			_beacon_root.global_position.y = _boat_root.global_position.y + 1.5
			_beacon_root.visible = true
	else:
		# 检测擦肩距离
		var dist := _beacon_root.global_position.distance_to(_boat_root.global_position)
		if dist < PASSING_DIST:
			_trigger_passing()


func _trigger_passing() -> void:
	_passing_done = true

	# 流星方向：斜向上飞射（随机左右偏）
	var shoot_dir := Vector3(randf_range(-0.4, 0.4), 1.2, randf_range(-0.4, 0.4)).normalized()
	var start_pos := _beacon_root.global_position
	var end_pos   := start_pos + shoot_dir * 25.0

	# 位移 tween：0.7s 飞出去
	var tw_pos := create_tween()
	tw_pos.tween_property(_beacon_root, "global_position", end_pos, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 光晕 tween：先亮起再熄灭
	var tw_light := create_tween()
	tw_light.tween_property(_beacon_light, "light_energy", 6.0, 0.1)
	tw_light.tween_property(_beacon_light, "light_energy", 0.0, 0.6)

	# 球体 tween：缩小消失
	var tw_scale := create_tween()
	tw_scale.tween_property(_beacon_mesh, "scale", Vector3.ZERO, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_scale.tween_callback(func():
		_beacon_root.visible = false
		_beacon_mesh.scale   = Vector3.ONE   # 重置缩放，下次生成用
		_beacon_light.light_energy = 3.0      # 重置光能，下次生成用
	)

	# 擦肩后船舵出现结局提示
	await get_tree().create_timer(0.4).timeout
	if _helm_prompt and not _helm_prompt.visible:
		_helm_prompt.visible = true
	print("[eros] 擦肩而过，helm_prompt 显示")


func _trigger_ending_ship() -> void:
	_is_triggering_ending = true
	state = ErosState.ENDING
	_helm_prompt.visible      = false
	_boat_exit_prompt.visible = false

	_player.set("frozen", true)

	if dye_system:
		dye_system.set_dye_instant(Color(0.18, 0.72, 0.42))   # 翠绿

	await get_tree().create_timer(0.8).timeout

	var mgr := get_parent().get_node_or_null("CostumeManager") as Node
	if mgr:
		mgr.call("on_eros_ending", "eros_ship")
	print("[eros] ending=eros_ship")


func _trigger_ending_island() -> void:
	_is_triggering_ending = true
	state = ErosState.ENDING
	_ending_prompt.visible = false

	# 锁定玩家移动
	_player.set("frozen", true)

	# 染色：粉色，1.5s 过渡
	if dye_system:
		dye_system.set_dye_instant(Color(0.95, 0.55, 0.72))   # 正宗粉色

	await get_tree().create_timer(0.8).timeout

	# 触发字幕 + 配饰：走 CostumeManager 标准流程，与之前所有 FORCE 一致
	var mgr := get_parent().get_node_or_null("CostumeManager") as Node
	if mgr:
		mgr.call("on_eros_ending", "eros_island")


func _turn_toward_sea() -> void:
	# 玩家朝向：转到面朝 -Z（酒海深处）
	var p_tween := create_tween()
	p_tween.tween_property(_player, "rotation_degrees:y", 0.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# NPC 朝向：从面朝玩家(0°) 转到面朝 -Z(180°)
	if _npc_node:
		var n_tween := create_tween()
		n_tween.tween_property(_npc_node, "rotation_degrees:y", 180.0, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# =============================================================
# Step 2 — 染色系统初始化
# =============================================================

func _setup_dye_system() -> void:
	var ds := load("res://dye_system.gd")
	if ds == null:
		push_warning("[eros] dye_system.gd 加载失败")
		return
	dye_system = ds.new()
	dye_system.name = "DyeSystem"
	add_child(dye_system)
	if _player:
		dye_system.init(_player)
	dye_system.target_color = Color(0.08, 0.18, 0.82)   # 深蓝：喝酒越多越深
	print("[eros] dye_system ready")
