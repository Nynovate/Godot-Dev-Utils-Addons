@tool
class_name PaintVertexDock
extends Control

signal paint_mode_changed(enabled: bool)
signal paint_color_changed(color: Color)
signal erase_color_changed(color: Color)
signal brush_radius_changed(value: float)
signal brush_strength_changed(value: float)
signal live_preview_toggled(enabled: bool)

var paint_active := false
var paint_color := Color(0.878, 0.235, 0.235)
var erase_color := Color(0.1, 0.1, 0.1)
var brush_radius := 5.0
var brush_strength := 0.8
var live_preview := false

var _mode_button: Button
var _live_preview_button: Button
var _warning_label: Label
var _paint_picker: ColorPickerButton
var _erase_picker: ColorPickerButton
var _radius_slider: HSlider
var _radius_spinbox: SpinBox
var _strength_slider: HSlider
var _strength_spinbox: SpinBox

const DISABLE_PAINT_MODE_TEXT: String = "Disable Paint Mode"
const ENABLE_PAINT_MODE_TEXT: String = "Enable Paint Mode"


func _ready() -> void:
	custom_minimum_size = Vector2(220, 0)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root_vbox)

	_build_mode_section(root_vbox)
	_build_warning_section(root_vbox)
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
		_mode_button.text = ENABLE_PAINT_MODE_TEXT
		paint_mode_changed.emit(false)


func update_warning_state(mesh_instance: MeshInstance3D, is_valid: bool) -> void:
	var warning_text = ""
	_warning_label.visible = true
	
	if mesh_instance == null:
		warning_text = "No MeshInstance3D selected."
	elif not is_valid:
		warning_text = "MeshInstance3D must have a StaticBody3D child for raycasting."
	else:
		_warning_label.visible = false
	
	_warning_label.text = warning_text


func _build_mode_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent)

	_mode_button = Button.new()
	_mode_button.text = ENABLE_PAINT_MODE_TEXT
	_mode_button.toggle_mode = true
	_mode_button.button_pressed = false
	_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_button.toggled.connect(_on_mode_toggled)
	section.add_child(_mode_button)
	
	_live_preview_button = Button.new()
	_live_preview_button.text = "Live Preview: OFF"
	_live_preview_button.toggle_mode = true
	_live_preview_button.button_pressed = false
	_live_preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_preview_button.toggled.connect(_on_live_preview_toggled)
	section.add_child(_live_preview_button)


func _build_warning_section(parent: VBoxContainer) -> void:
	_warning_label = Label.new()
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0)) # yellow
	_warning_label.text = ""
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_warning_label.visible = false
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	parent.add_child(margin)
	margin.add_child(_warning_label)


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

	# Radius row with slider and spinbox
	var radius_hbox := HBoxContainer.new()
	radius_hbox.add_theme_constant_override("separation", 6)
	section.add_child(radius_hbox)
	
	var radius_label := Label.new()
	radius_label.text = "Radius:"
	radius_label.custom_minimum_size.x = 60
	radius_label.add_theme_font_size_override("font_size", 11)
	radius_hbox.add_child(radius_label)
	
	_radius_slider = HSlider.new()
	_radius_slider.min_value = 0.5
	_radius_slider.max_value = 50.0
	_radius_slider.step = 0.5
	_radius_slider.value = brush_radius
	_radius_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radius_slider.value_changed.connect(_on_radius_changed)
	radius_hbox.add_child(_radius_slider)
	
	_radius_spinbox = SpinBox.new()
	_radius_spinbox.min_value = 0.5
	_radius_spinbox.max_value = 50.0
	_radius_spinbox.step = 0.5
	_radius_spinbox.value = brush_radius
	_radius_spinbox.custom_minimum_size.x = 70
	_radius_spinbox.value_changed.connect(_on_radius_spinbox_changed)
	radius_hbox.add_child(_radius_spinbox)

	# Strength row with slider and spinbox
	var strength_hbox := HBoxContainer.new()
	strength_hbox.add_theme_constant_override("separation", 6)
	section.add_child(strength_hbox)
	
	var strength_label := Label.new()
	strength_label.text = "Strength:"
	strength_label.custom_minimum_size.x = 60
	strength_label.add_theme_font_size_override("font_size", 11)
	strength_hbox.add_child(strength_label)
	
	_strength_slider = HSlider.new()
	_strength_slider.min_value = 0.0
	_strength_slider.max_value = 1.0
	_strength_slider.step = 0.01
	_strength_slider.value = brush_strength
	_strength_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strength_slider.value_changed.connect(_on_strength_changed)
	strength_hbox.add_child(_strength_slider)
	
	_strength_spinbox = SpinBox.new()
	_strength_spinbox.min_value = 0.0
	_strength_spinbox.max_value = 1.0
	_strength_spinbox.step = 0.01
	_strength_spinbox.value = brush_strength
	_strength_spinbox.custom_minimum_size.x = 70
	_strength_spinbox.value_changed.connect(_on_strength_spinbox_changed)
	strength_hbox.add_child(_strength_spinbox)


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


func _build_separator(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_mode_toggled(pressed: bool) -> void:
	paint_active = pressed
	_mode_button.text = DISABLE_PAINT_MODE_TEXT if pressed else ENABLE_PAINT_MODE_TEXT
	paint_mode_changed.emit(pressed)


func _on_live_preview_toggled(pressed: bool) -> void:
	live_preview = pressed
	_live_preview_button.text = "Live Preview: ON" if pressed else "Live Preview: OFF"
	live_preview_toggled.emit(pressed)


func _on_paint_color_changed(color: Color) -> void:
	paint_color = color
	paint_color_changed.emit(color)


func _on_erase_color_changed(color: Color) -> void:
	erase_color = color
	erase_color_changed.emit(color)


func _on_radius_changed(value: float) -> void:
	brush_radius = value
	_radius_spinbox.value = value  # Sync spinbox with slider
	brush_radius_changed.emit(value)


func _on_radius_spinbox_changed(value: float) -> void:
	brush_radius = value
	_radius_slider.value = value  # Sync slider with spinbox
	brush_radius_changed.emit(value)


func _on_strength_changed(value: float) -> void:
	brush_strength = value
	_strength_spinbox.value = value  # Sync spinbox with slider
	brush_strength_changed.emit(value)


func _on_strength_spinbox_changed(value: float) -> void:
	brush_strength = value
	_strength_slider.value = value  # Sync slider with spinbox
	brush_strength_changed.emit(value)


# ── Public ────────────────────────────────────────────────────────────────────

func swap_colors() -> void:
	var tmp := paint_color
	paint_color = erase_color
	erase_color = tmp
	_paint_picker.color = paint_color
	_erase_picker.color = erase_color
