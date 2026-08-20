extends Node3D

# Identity（认同）场景控制器
# 步骤四：观察行为（停留 3 秒触发 → 镜头推近 8 秒 → 恢复）

enum EncounterState { UNRESOLVED, RESOLVED }
var state: EncounterState = EncounterState.UNRESOLVED

var _npc: Node3D
var _player: Node3D
var _camera: Camera3D
var _camera_origin: Vector3   # 记录摄像机原始位置，用于恢复

# 三个区域
var _area_observe:  Area3D
var _area_accept:   Area3D
var _area_destroy:  Area3D

# 停留计时（三个区域共用 DWELL_REQUIRED，各自独立计时）
const DWELL_REQUIRED := 3.0

var _in_observe    := false
var _observe_dwell := 0.0

var _in_accept     := false
var _accept_dwell  := 0.0

var _in_destroy    := false
var _destroy_dwell := 0.0

# 防止演出中途被重复触发
var _observe_playing := false
var _accept_playing  := false
var _destroy_playing := false

# 认同用的黑屏遮罩（CanvasLayer + ColorRect）
var _fade_layer:   CanvasLayer
var _fade_rect:    ColorRect

# 破坏用的 vignette（叠在同一 CanvasLayer，位于黑屏层之下）
var _vignette_rect: ColorRect
var _vignette_mat:  ShaderMaterial

# 破坏粒子
var _destroy_particles: GPUParticles3D
var _costume_ui:       CanvasLayer   # 复用 Seeking 的白屏+字幕系统
var _costume_wardrobe: Node          # 复用 Seeking 的配饰系统

# 区域局部坐标
const ZONE_Z      :=  3.0
const ZONE_SPREAD :=  4.0
const ZONE_SIZE   := Vector3(3.2, 0.08, 14.0)


func _ready() -> void:
	_create_npc()
	_create_zones()
	_create_fade_overlay()
	_create_particles()
	# 等一帧，确保 player 已加入场景树
	await get_tree().process_frame
	_find_player_refs()


func _find_player_refs() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		push_warning("[identity] player not found")
		return
	_camera = get_viewport().get_camera_3d()
	if _camera:
		_camera_origin = _camera.position
		print("[identity] camera found: ", _camera.name, " origin=", _camera_origin)
	else:
		push_warning("[identity] active Camera3D not found in viewport")

	_costume_ui = get_tree().root.find_child("CostumeUI", true, false) as CanvasLayer
	if _costume_ui == null:
		push_warning("[identity] CostumeUI not found")

	_costume_wardrobe = get_tree().root.find_child("CostumeWardrobe", true, false)
	if _costume_wardrobe == null:
		push_warning("[identity] CostumeWardrobe not found")


# ── 每帧：停留计时 ────────────────────────────────────────────────

func _process(delta: float) -> void:
	if state != EncounterState.UNRESOLVED:
		return

	# 观察停留计时
	if _in_observe and not _observe_playing:
		_observe_dwell += delta
		if _observe_dwell >= DWELL_REQUIRED:
			_observe_playing = true
			_in_observe = false
			_trigger_observe()

	# 认同停留计时
	if _in_accept and not _accept_playing:
		_accept_dwell += delta
		if _accept_dwell >= DWELL_REQUIRED:
			_accept_playing = true
			_in_accept = false
			_trigger_accept()

	# 破坏停留计时 + vignette 驱动
	if _in_destroy and not _destroy_playing:
		_destroy_dwell += delta
		var ratio: float = clamp(_destroy_dwell / (DWELL_REQUIRED * 2.0), 0.0, 1.0)
		_vignette_mat.set_shader_parameter("intensity", ratio)
		if _destroy_dwell >= DWELL_REQUIRED:
			_destroy_playing = true
			_in_destroy = false
			_vignette_mat.set_shader_parameter("intensity", 0.0)
			_trigger_destroy()


# ── NPC ──────────────────────────────────────────────────────────

func _create_npc() -> void:
	_npc = Node3D.new()
	_npc.name = "IdentityNPC"

	var char_scene = load("res://models/player/character_base.fbx").instantiate()
	char_scene.scale = Vector3(3.2, 3.2, 3.2)
	char_scene.rotation_degrees = Vector3(180.0, 180.0, 0.0)
	_npc.add_child(char_scene)

	var anim: AnimationPlayer = char_scene.get_node_or_null("AnimationPlayer")
	if anim:
		anim.add_animation_library("idle", load("res://models/player/character_idle.fbx"))
		anim.play("idle/mixamo_com")
	else:
		push_warning("[identity] AnimationPlayer not found")

	_npc.position = Vector3(0.0, 10.0, 0.0)
	add_child(_npc)


# ── 三个区域 ──────────────────────────────────────────────────────

func _create_zones() -> void:
	_area_observe = _make_zone(
		"ZoneObserve",
		Vector3(-ZONE_SPREAD, 0.0, ZONE_Z),
		Color(0.88, 0.88, 0.86),
		"Observe"
	)
	_area_accept = _make_zone(
		"ZoneAccept",
		Vector3(0.0, 0.0, ZONE_Z),
		Color(0.90, 0.72, 0.74),
		"Accept"
	)
	_area_destroy = _make_zone(
		"ZoneDestroy",
		Vector3(ZONE_SPREAD, 0.0, ZONE_Z),
		Color(0.58, 0.57, 0.56),
		"Destroy"
	)

	_add_prop_magnifier(_area_observe)
	_add_prop_statue(_area_accept)
	_add_prop_stick(_area_destroy)

	_area_observe.body_entered.connect(_on_observe_entered)
	_area_observe.body_exited.connect(_on_observe_exited)
	_area_accept.body_entered.connect(_on_accept_entered)
	_area_accept.body_exited.connect(_on_accept_exited)
	_area_destroy.body_entered.connect(_on_destroy_entered)
	_area_destroy.body_exited.connect(_on_destroy_exited)


func _make_zone(zone_name: String, local_pos: Vector3, color: Color, label_text: String) -> Area3D:
	var area := Area3D.new()
	area.name = zone_name
	area.position = local_pos

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ZONE_SIZE.x, 2.0, ZONE_SIZE.z)
	col.shape = box
	col.position.y = 1.0
	area.add_child(col)

	var mesh := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size  = ZONE_SIZE
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.85
	mesh.material_override = mat
	mesh.position.y = 0.04
	area.add_child(mesh)

	var label := Label3D.new()
	label.text               = label_text
	label.font_size          = 72
	label.pixel_size         = 0.01
	label.modulate           = Color(1.0, 1.0, 1.0, 0.22)
	label.billboard          = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided       = true
	label.rotation_degrees.x = -90.0
	label.position           = Vector3(0.0, 0.12, 1.0)
	area.add_child(label)

	add_child(area)
	return area


# ── 道具 ─────────────────────────────────────────────────────────

func _add_prop_magnifier(parent: Node3D) -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, 0.0, -0.5)
	var handle := MeshInstance3D.new()
	var cyl    := CylinderMesh.new()
	cyl.top_radius = 0.04; cyl.bottom_radius = 0.04; cyl.height = 0.6
	handle.mesh = cyl
	handle.position = Vector3(0.0, 0.3, 0.0)
	handle.rotation_degrees.z = 30.0
	_apply_mat(handle, Color(0.70, 0.65, 0.55))
	root.add_child(handle)
	var lens := MeshInstance3D.new()
	var sph  := SphereMesh.new()
	sph.radius = 0.22; sph.height = 0.10
	lens.mesh = sph
	lens.position = Vector3(0.18, 0.7, 0.0)
	_apply_mat(lens, Color(0.75, 0.82, 0.88, 0.6))
	root.add_child(lens)
	parent.add_child(root)

func _add_prop_statue(parent: Node3D) -> void:
	var statue := MeshInstance3D.new()
	var cap    := CapsuleMesh.new()
	cap.radius = 0.12; cap.height = 0.55
	statue.mesh = cap
	statue.position = Vector3(0.0, 0.28, -0.3)
	statue.rotation_degrees.z = 180.0
	_apply_mat(statue, Color(0.72, 0.60, 0.50))
	parent.add_child(statue)

func _add_prop_stick(parent: Node3D) -> void:
	var stick := MeshInstance3D.new()
	var cyl   := CylinderMesh.new()
	cyl.top_radius = 0.04; cyl.bottom_radius = 0.05; cyl.height = 0.75
	stick.mesh = cyl
	stick.position = Vector3(0.0, 0.38, -0.3)
	stick.rotation_degrees.z = 12.0
	_apply_mat(stick, Color(0.50, 0.42, 0.35))
	parent.add_child(stick)

func _apply_mat(mi: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.9
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat


# ── 区域信号 ─────────────────────────────────────────────────────

func _on_observe_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or state != EncounterState.UNRESOLVED:
		return
	_in_observe = true
	_observe_dwell = 0.0

func _on_observe_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_in_observe = false
	_observe_dwell = 0.0

func _on_accept_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or state != EncounterState.UNRESOLVED:
		return
	_in_accept = true
	_accept_dwell = 0.0
	print("[identity] accept zone entered")

func _on_accept_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_in_accept = false
	_accept_dwell = 0.0

func _on_destroy_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or state != EncounterState.UNRESOLVED:
		return
	_in_destroy = true
	_destroy_dwell = 0.0
	print("[identity] destroy zone entered")

func _on_destroy_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_in_destroy = false
	_destroy_dwell = 0.0
	_vignette_mat.set_shader_parameter("intensity", 0.0)   # 离开立刻清除 vignette


# ── 黑屏遮罩 ─────────────────────────────────────────────────────

func _create_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()

	# vignette（先加，层级在黑屏之下）
	var vig_shader := Shader.new()
	vig_shader.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float v = smoothstep(0.25, 0.72, dist) * intensity;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}
"""
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = vig_shader
	_vignette_rect = ColorRect.new()
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.material = _vignette_mat
	_fade_layer.add_child(_vignette_rect)

	# 黑屏（后加，覆盖在 vignette 之上）
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)

	add_child(_fade_layer)


func _create_particles() -> void:
	_destroy_particles = GPUParticles3D.new()
	_destroy_particles.amount       = 50
	_destroy_particles.lifetime     = 5.0
	_destroy_particles.one_shot     = true
	_destroy_particles.explosiveness = 0.95
	_destroy_particles.emitting     = false

	var pm := ParticleProcessMaterial.new()
	pm.direction           = Vector3(0, 1, 0)
	pm.spread              = 180.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.5
	pm.gravity             = Vector3(0, -1.5, 0)
	pm.scale_min           = 0.15
	pm.scale_max           = 0.4
	_destroy_particles.process_material = pm

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.3)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.05, 0.05, 0.05)   # 黑色
	mesh_mat.roughness = 0.8
	mesh.surface_set_material(0, mesh_mat)
	_destroy_particles.draw_pass_1 = mesh

	# 挂到 NPC 身体中段（头部附近，玩家视野内）
	_destroy_particles.position = Vector3(0.0, 5.0, 0.0)
	add_child(_destroy_particles)


# alpha 从 from 渐变到 to，持续 duration 秒
func _fade(from: float, to: float, duration: float) -> void:
	_fade_rect.color.a = from
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", to, duration)
	await tw.finished


# ── 行为 B：认同 ──────────────────────────────────────────────────

func _trigger_accept() -> void:
	if _player == null or _camera == null:
		return

	print("[identity] accept: start")
	_player.set("frozen", true)

	# 记录翻转前的摄像机旋转，用于精确恢复
	var origin_rot := _camera.rotation

	# 淡黑
	await _fade(0.0, 1.0, 0.5)
	# 黑屏期间瞬间翻转：绕 Z 轴 roll 180°，视线方向不变，画面上下颠倒
	_camera.rotation.z = PI
	# 淡入，玩家看到倒转的世界
	await _fade(1.0, 0.0, 0.6)

	# 定格 6 秒：frozen 锁移动，摄像机旋转仍可自由转动
	await get_tree().create_timer(6.0).timeout

	# 再次淡黑
	await _fade(0.0, 1.0, 0.5)
	# 黑屏期间恢复
	_camera.rotation = origin_rot
	# 淡入
	await _fade(1.0, 0.0, 0.6)

	_player.set("frozen", false)
	if _costume_ui:
		_costume_ui.on_costume_triggered("accept_identity")
	if _costume_wardrobe:
		_costume_wardrobe.on_costume_triggered("accept_identity")
	resolve_encounter()


# ── 行为 A：观察 ──────────────────────────────────────────────────

func _trigger_observe() -> void:
	if _player == null or _camera == null:
		return

	print("[identity] observe: start")
	_player.set("frozen", true)

	# NPC 头部世界坐标：pivot 在 Y=10，scale 3.2 × 高约 1.8m → 头在 pivot 下约 5.2m
	# Y=180 让正脸朝 +Z，所以正脸前方 = +Z 方向偏移
	var face_world := _npc.global_position + Vector3(0.0, -5.2, 0.0)
	var cam_target := face_world + Vector3(0.0, 0.5, 6.0)   # 正脸前方 6m，略偏上

	# 记录原始全局状态
	var origin_pos := _camera.global_position
	var origin_rot := _camera.global_rotation

	# 慢慢推近（1.5s）
	var tw_in := create_tween()
	tw_in.tween_property(_camera, "global_position", cam_target, 1.5)
	await tw_in.finished
	_camera.look_at(face_world, Vector3.UP)

	# 定格 6 秒
	await get_tree().create_timer(6.0).timeout

	# 慢慢恢复（1.5s，同步还原位置和旋转）
	var tw_out := create_tween().set_parallel(true)
	tw_out.tween_property(_camera, "global_position", origin_pos, 1.5)
	tw_out.tween_property(_camera, "global_rotation", origin_rot, 1.5)
	await tw_out.finished

	_player.set("frozen", false)
	if _costume_ui:
		_costume_ui.on_costume_triggered("observe_identity")
	if _costume_wardrobe:
		_costume_wardrobe.on_costume_triggered("observe_identity")
	resolve_encounter()


# ── 行为 C：破坏 ──────────────────────────────────────────────────

func _trigger_destroy() -> void:
	if _player == null:
		return

	print("[identity] destroy: start")

	# NPC 消失 + 粒子散开
	_npc.visible = false
	_destroy_particles.emitting = true

	# 等待粒子散开
	await get_tree().create_timer(4.5).timeout

	# NPC 复原
	_npc.visible = true

	if _costume_ui:
		_costume_ui.on_costume_triggered("destroy_identity")
	if _costume_wardrobe:
		_costume_wardrobe.on_costume_triggered("destroy_identity")
	resolve_encounter()


# ── 结束：关闭三个区域 ────────────────────────────────────────────

func resolve_encounter() -> void:
	state = EncounterState.RESOLVED
	_area_observe.monitoring = false
	_area_accept.monitoring  = false
	_area_destroy.monitoring = false
	print("[identity] encounter resolved")
