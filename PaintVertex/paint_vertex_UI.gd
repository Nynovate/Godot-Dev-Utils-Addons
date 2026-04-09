@tool
class_name PaintVertexDock
extends Control

signal paint_mode_changed(enabled: bool)
signal paint_color_changed(color: Color)
signal erase_color_changed(color: Color)
signal brush_radius_changed(value: float)
signal brush_strength_changed(value: float)

var paint_active := false
var paint_color := Color(0.878, 0.235, 0.235)
var erase_color := Color(0.1, 0.1, 0.1)
var brush_radius := 50.0
var brush_strength := 0.8

var _mode_button: Button
var _paint_picker: ColorPickerButton
var _erase_picker: ColorPickerButton
var _radius_slider: HSlider
var _radius_label: Label
var _strength_slider: HSlider
var _strength_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(180, 0)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	_build_mode_section(root_vbox)
	_build_separator(root_vbox)
	_build_color_section(root_vbox)
	_build_separator(root_vbox)
	_build_brush_section(root_vbox)
	_build_separator(root_vbox)
	_build_hints(root_vbox)


# ── Sections ─────────────────────────────────────────────────────────────────

func set_painting_enabled(enabled: bool) -> void:
	_mode_button.disabled = not enabled
	if not enabled:
		_mode_button.tooltip_text = "Select a MeshInstance3D to paint"
	else:
		_mode_button.tooltip_text = ""


func force_paint_off() -> void:
	if paint_active:
		paint_active = false
		_mode_button.button_pressed = false
		_mode_button.text = "Enable Paint Mode"
		paint_mode_changed.emit(false)

func _build_mode_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent)

	_mode_button = Button.new()
	_mode_button.text = "Enable Paint Mode"
	_mode_button.toggle_mode = true
	_mode_button.button_pressed = false
	_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_button.toggled.connect(_on_mode_toggled)
	section.add_child(_mode_button)


func _build_color_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Colors")

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	section.add_child(hbox)

	var paint_vbox := VBoxContainer.new()
	paint_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(paint_vbox)

	_paint_picker = ColorPickerButton.new()
	_paint_picker.color = paint_color
	_paint_picker.custom_minimum_size = Vector2(48, 36)
	_paint_picker.color_changed.connect(_on_paint_color_changed)
	paint_vbox.add_child(_paint_picker)

	var paint_lbl := Label.new()
	paint_lbl.text = "Paint"
	paint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paint_lbl.add_theme_font_size_override("font_size", 10)
	paint_vbox.add_child(paint_lbl)

	var swap_btn := Button.new()
	swap_btn.text = "⇄"
	swap_btn.tooltip_text = "Swap colors (X)"
	swap_btn.flat = true
	swap_btn.custom_minimum_size = Vector2(28, 28)
	swap_btn.pressed.connect(swap_colors)
	hbox.add_child(swap_btn)

	var erase_vbox := VBoxContainer.new()
	erase_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(erase_vbox)

	_erase_picker = ColorPickerButton.new()
	_erase_picker.color = erase_color
	_erase_picker.custom_minimum_size = Vector2(36, 28)
	_erase_picker.color_changed.connect(_on_erase_color_changed)
	erase_vbox.add_child(_erase_picker)

	var erase_lbl := Label.new()
	erase_lbl.text = "Erase"
	erase_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	erase_lbl.add_theme_font_size_override("font_size", 10)
	erase_vbox.add_child(erase_lbl)


func _build_brush_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Brush")

	# Radius row — assign the returned array first
	var radius_row  := _make_slider_row(section, "Radius")
	_radius_slider   = radius_row[0]
	_radius_label    = radius_row[1]
	_radius_slider.min_value = 0.001
	_radius_slider.max_value = 50.0
	_radius_slider.step = 0.001
	_radius_slider.value = brush_radius
	_radius_label.text = "%.3f" % brush_radius
	_radius_slider.value_changed.connect(_on_radius_changed)

	# Strength row
	var strength_row := _make_slider_row(section, "Strength")
	_strength_slider  = strength_row[0]
	_strength_label   = strength_row[1]
	_strength_slider.min_value = 0.0
	_strength_slider.max_value = 1.0
	_strength_slider.step = 0.01
	_strength_slider.value = brush_strength
	_strength_label.text = "%.0f%%" % (brush_strength * 100.0)
	_strength_slider.value_changed.connect(_on_strength_changed)


func _build_hints(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(margin)

	var hint := Label.new()
	hint.text = "Ctrl+RMB  paint  |  X  swap"
	hint.add_theme_font_size_override("font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	margin.add_child(hint)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_section(parent: VBoxContainer, title: String = "") -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	parent.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	if title != "":
		var lbl := Label.new()
		lbl.text = title.to_upper()
		lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(lbl)

	return vbox


func _make_slider_row(parent: VBoxContainer, label_text: String) -> Array:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(54, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(34, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(val_lbl)

	return [slider, val_lbl]


func _build_separator(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_mode_toggled(pressed: bool) -> void:
	paint_active = pressed
	_mode_button.text = "Disable Paint Mode" if pressed else "Enable Paint Mode"
	paint_mode_changed.emit(pressed)


func _on_paint_color_changed(color: Color) -> void:
	paint_color = color
	paint_color_changed.emit(color)


func _on_erase_color_changed(color: Color) -> void:
	erase_color = color
	erase_color_changed.emit(color)


func _on_radius_changed(value: float) -> void:
	brush_radius = value
	_radius_label.text = "%.3f" % value
	brush_radius_changed.emit(value)


func _on_strength_changed(value: float) -> void:
	brush_strength = value
	_strength_label.text = "%.0f%%" % (value * 100.0)
	brush_strength_changed.emit(value)


# ── Public ────────────────────────────────────────────────────────────────────

func swap_colors() -> void:
	var tmp := paint_color
	paint_color = erase_color
	erase_color = tmp
	_paint_picker.color = paint_color
	_erase_picker.color = erase_color
