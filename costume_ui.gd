extends CanvasLayer

# 服装触发 UI：白屏渐入 → 深褐色文字 → 白屏与文字同步淡出
# 由 costume_manager.gd 的 costume_triggered 信号驱动

const TEXTS := {
	"follow":    "「你也向那束光走去。」",
	"gaze":      "「你曾仰望的存在，也曾仰望远方。」",
	"overtake":  "「你终于站在它的前方，却看见了更远的地方。」",
	"abandon":   "「停下，并不会抹去曾经的方向。」",
	"obsession": "「你已经忘记，最初想去哪里。」",
	# Identity（认同）
	"observe_identity": "「有些相遇不改变方向，却改变了看世界的方式。」",
	"accept_identity":  "「我暂时放下自己的形状，成为另一种可能。」",
	"destroy_identity": "「当一种秩序无法容纳我，我选择留下裂痕。」",
	# Connection（连接）
	"connection_frame":    "「有些连接，值得被记住。」",
	"connection_water":    "「有些连接，不应该被占有。」",
	"connection_scissors": "「有些连接，即使结束，也不会消失。」",
	# Eros（爱欲）
	"eros_island": "「我不再寻找远方，因为远方已经在这里。」",
	"eros_ship":   "「我依然相信，下一次会不一样。」",
	"eros_drift":  "「我把自己交给这片海。」",
	"eros_awake":  "「我发现自己也拥有天空。」",
	# Order（秩序）
	"order_path1": "「秩序建成了，代价是你成为秩序本身。」",
	"order_path2": "「找到编号的那一刻，才发现自己从未与众不同。」",
	"order_path3": "「拒绝被定义的人，终将无人记得。」",
}

const TEXT_COLOR   := Color(0.25, 0.12, 0.05, 1.0)  # 深褐色
const FADE_IN_T    := 1.2   # 白屏渐入时长
const HOLD_T       := 1.8   # 白屏停留时长
const FADE_OUT_T   := 1.5   # 白屏 + 文字同步淡出时长

signal sequence_started(event_name: String)
signal sequence_finished(event_name: String)

var _flash: ColorRect
var _label: Label
var _tween_flash: Tween
var _tween_text:  Tween


func _ready() -> void:

	# 白色全屏遮罩
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	# 文字标签：深褐色，全屏锚点让对齐属性生效
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_label)


# 由 world.gd 连接到 costume_manager 的 costume_triggered 信号
func on_costume_triggered(event_name: String) -> void:

	var text: String = TEXTS.get(event_name, "")
	if text.is_empty():
		return

	# 打断上一个正在播放的动画
	if _tween_flash and _tween_flash.is_running():
		_tween_flash.kill()
	if _tween_text and _tween_text.is_running():
		_tween_text.kill()
	_flash.color.a    = 0.0
	_label.modulate.a = 0.0

	_label.text = text
	sequence_started.emit(event_name)

	# 白屏：渐入 → 停留 → 渐出；结束时发出 sequence_finished
	_tween_flash = create_tween()
	_tween_flash.tween_property(_flash, "color:a", 1.0, FADE_IN_T)
	_tween_flash.tween_interval(HOLD_T)
	_tween_flash.tween_property(_flash, "color:a", 0.0, FADE_OUT_T)
	_tween_flash.tween_callback(func(): sequence_finished.emit(event_name))

	# 文字：与白屏同步渐入 → 停留 → 与白屏同步渐出
	_tween_text = create_tween()
	_tween_text.tween_property(_label, "modulate:a", 1.0, FADE_IN_T)
	_tween_text.tween_interval(HOLD_T)
	_tween_text.tween_property(_label, "modulate:a", 0.0, FADE_OUT_T)
