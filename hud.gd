extends CanvasLayer
## Heads-up display: score line, HP and boost bars, boss bar, damage flash, centre messages, toasts.

var _info: Label
var _center: Label
var _hint: Label
var _extra: Label
var _toast: Label
var _flash: ColorRect
var _toast_t := 0.0
var _bars: Dictionary = {}   # name -> {fill: ColorRect, w: float}


func _ready() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_info = _label(22)
	_info.position = Vector2(20, 12)
	_bar("hp", Vector2(20, 48), Vector2(300, 16))
	_bar("shield", Vector2(20, 66), Vector2(300, 6))
	_bar("gauge", Vector2(20, 76), Vector2(300, 8))
	_extra = _label(18)
	_extra.position = Vector2(20, 90)
	_bar("boss", Vector2(340, 12), Vector2(600, 14))

	_center = _label(34)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_toast = _label(28)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast.offset_top = 140

	_hint = _label(15)
	_hint.position = Vector2(20, 692)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.text = "WASD move   aim with mouse   LMB / SPACE fire   hold RMB / C lock-on (release to launch)   B bomb   SHIFT boost   CTRL brake   Q/E roll (reflects shots)   F loop   P pause"


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _bar(key: String, pos: Vector2, size: Vector2) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = pos
	bg.size = size
	add_child(bg)
	var fill := ColorRect.new()
	fill.position = pos
	fill.size = size
	add_child(fill)
	_bars[key] = {"bg": bg, "fill": fill, "w": size.x}


func _set_bar(key: String, ratio: float, color: Color) -> void:
	var b: Dictionary = _bars[key]
	var fill: ColorRect = b["fill"]
	fill.size.x = float(b["w"]) * clampf(ratio, 0.0, 1.0)
	fill.color = color


func update(d: Dictionary) -> void:
	_info.text = "%s    SCORE %d    HI %d    %d%%" % [d["level"], d["score"], d["high"], d["progress"]]
	var hp_ratio: float = d["hp"]
	_set_bar("hp", hp_ratio, Color.from_hsv(0.33 * hp_ratio, 0.8, 0.95))
	var sh: float = d["shield"]
	_bars["shield"]["bg"].visible = sh > 0.0
	_bars["shield"]["fill"].visible = sh > 0.0
	_set_bar("shield", sh, Color(0.35, 0.65, 1.0))
	_extra.text = d["extra"]
	_set_bar("gauge", d["gauge"], Color(1.0, 0.55, 0.15) if d["locked"] else Color(0.3, 0.8, 1.0))
	var boss_ratio: float = d["boss"]
	_bars["boss"]["bg"].visible = boss_ratio >= 0.0
	_bars["boss"]["fill"].visible = boss_ratio >= 0.0
	if boss_ratio >= 0.0:
		_set_bar("boss", boss_ratio, Color(0.9, 0.2, 0.7))
	_center.text = d["message"]
	_hint.visible = d["state"] != "title"


func damage_flash() -> void:
	_flash.color.a = 0.4


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.6


func _process(delta: float) -> void:
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.4)
	_toast_t -= delta
	if _toast_t <= 0.0:
		_toast.text = ""
	else:
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
