@tool
class_name PaintMeshGPUDock
extends Control

# Mesh resource with density weight
class MeshResource:
	var mesh: Mesh
	var density: float = 1.0
	
	func _init(p_mesh: Mesh = null, p_density: float = 1.0):
		mesh = p_mesh
		density = p_density

# Paint mode
var paint_active: bool = false
var erase_mode: bool = false

# UI Components
var _mode_button: Button
var _erase_button: Button
var _warning_label: Label
var _mesh_list_container: VBoxContainer
var _add_mesh_button: Button

# Mesh resources
var mesh_resources: Array[MeshResource] = []

# Brush settings
var brush_radius: float = 5.0
var brush_density: float = 1.0
var _radius_slider: HSlider
var _radius_value_label: Label
var _density_slider: HSlider
var _density_value_label: Label

# Randomization settings
var offset_min: Vector3 = Vector3.ZERO
var offset_max: Vector3 = Vector3.ZERO
var rotation_min: Vector3 = Vector3.ZERO
var rotation_max: Vector3 = Vector3(0, 360, 0)
var scale_min: Vector3 = Vector3.ONE
var scale_max: Vector3 = Vector3.ONE

var _offset_min_x: SpinBox
var _offset_min_y: SpinBox
var _offset_min_z: SpinBox
var _offset_max_x: SpinBox
var _offset_max_y: SpinBox
var _offset_max_z: SpinBox
var _rotation_min_x: SpinBox
var _rotation_min_y: SpinBox
var _rotation_min_z: SpinBox
var _rotation_max_x: SpinBox
var _rotation_max_y: SpinBox
var _rotation_max_z: SpinBox
var _scale_min_x: SpinBox
var _scale_min_y: SpinBox
var _scale_min_z: SpinBox
var _scale_max_x: SpinBox
var _scale_max_y: SpinBox
var _scale_max_z: SpinBox

const DISABLE_PAINT_MODE_TEXT: String = "Disable Paint Mode"
const ENABLE_PAINT_MODE_TEXT: String = "Enable Paint Mode"

signal paint_mode_changed(enabled: bool)
signal erase_mode_changed(enabled: bool)
signal mesh_resources_changed()

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
	_build_mesh_resources_section(root_vbox)
	_build_separator(root_vbox)
	_build_brush_settings_section(root_vbox)
	_build_separator(root_vbox)
	_build_randomization_section(root_vbox)

	# Initial check
	_update_button_state()

func _build_separator(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())

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

func _build_mode_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent)

	_mode_button = Button.new()
	_mode_button.text = ENABLE_PAINT_MODE_TEXT
	_mode_button.toggle_mode = true
	_mode_button.button_pressed = false
	_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_button.toggled.connect(_on_mode_toggled)
	section.add_child(_mode_button)
	
	_erase_button = Button.new()
	_erase_button.text = "Erase Mode"
	_erase_button.toggle_mode = true
	_erase_button.button_pressed = false
	_erase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_erase_button.toggled.connect(_on_erase_toggled)
	section.add_child(_erase_button)

func _on_mode_toggled(pressed: bool) -> void:
	paint_active = pressed
	_mode_button.text = DISABLE_PAINT_MODE_TEXT if pressed else ENABLE_PAINT_MODE_TEXT
	if pressed and erase_mode:
		_erase_button.button_pressed = false
		erase_mode = false
	paint_mode_changed.emit(pressed)

func _on_erase_toggled(pressed: bool) -> void:
	erase_mode = pressed
	if pressed and paint_active:
		_mode_button.button_pressed = false
		paint_active = false
	erase_mode_changed.emit(pressed)

func _build_warning_section(parent: VBoxContainer) -> void:
	_warning_label = Label.new()
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0)) # yellow
	_warning_label.text = ""
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(_warning_label)

func _update_button_state() -> void:
	var selected = get_selected_node()
	var warning_text = ""
	var enable_button = false
	_warning_label.visible = true

	if not selected:
		warning_text = "No node selected."
	elif not selected is MeshInstance3D:
		warning_text = "Selected node is not a MeshInstance3D."
	elif not _has_static_body_child(selected):
		warning_text = "MeshInstance3D must have a StaticBody3D child for raycasting."
	elif mesh_resources.is_empty():
		warning_text = "Please add at least one mesh resource."
	else:
		enable_button = true
		_warning_label.visible = false

	set_painting_enabled(enable_button)
	_warning_label.text = warning_text

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
	
func _build_mesh_resources_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Mesh Resources")
	
	_mesh_list_container = VBoxContainer.new()
	_mesh_list_container.add_theme_constant_override("separation", 4)
	section.add_child(_mesh_list_container)
	
	_add_mesh_button = Button.new()
	_add_mesh_button.text = "+ Add Mesh"
	_add_mesh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_mesh_button.pressed.connect(_on_add_mesh_pressed)
	section.add_child(_add_mesh_button)

func _on_add_mesh_pressed() -> void:
	var new_resource = MeshResource.new()
	mesh_resources.append(new_resource)
	_rebuild_mesh_list()
	mesh_resources_changed.emit()

func _rebuild_mesh_list() -> void:
	# Clear existing UI
	for child in _mesh_list_container.get_children():
		child.queue_free()
	
	# Rebuild list
	for i in mesh_resources.size():
		_add_mesh_item(i)
	
	_update_button_state()

func _add_mesh_item(index: int) -> void:
	var mesh_res = mesh_resources[index]
	
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _create_panel_style())
	_mesh_list_container.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	# Header with remove button
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var label = Label.new()
	label.text = "Mesh " + str(index + 1)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	
	var remove_btn = Button.new()
	remove_btn.text = "×"
	remove_btn.custom_minimum_size = Vector2(24, 24)
	remove_btn.pressed.connect(func(): _remove_mesh(index))
	header.add_child(remove_btn)
	
	# Mesh picker
	var picker = EditorResourcePicker.new()
	picker.base_type = "Mesh"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.edited_resource = mesh_res.mesh
	picker.resource_changed.connect(func(resource): _on_mesh_changed(index, resource))
	vbox.add_child(picker)
	
	# Density slider
	var density_hbox = HBoxContainer.new()
	vbox.add_child(density_hbox)
	
	var density_label = Label.new()
	density_label.text = "Density:"
	density_label.custom_minimum_size.x = 60
	density_hbox.add_child(density_label)
	
	var density_slider = HSlider.new()
	density_slider.min_value = 0.1
	density_slider.max_value = 10.0
	density_slider.step = 0.1
	density_slider.value = mesh_res.density
	density_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	density_slider.value_changed.connect(func(val): _on_density_changed(index, val))
	density_hbox.add_child(density_slider)
	
	var density_val_label = Label.new()
	density_val_label.text = "%.1f" % mesh_res.density
	density_val_label.custom_minimum_size.x = 30
	density_hbox.add_child(density_val_label)
	density_slider.value_changed.connect(func(val): density_val_label.text = "%.1f" % val)

func _create_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.3)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style

func _on_mesh_changed(index: int, resource: Resource) -> void:
	if index < mesh_resources.size():
		mesh_resources[index].mesh = resource as Mesh
		mesh_resources_changed.emit()
		_update_button_state()

func _on_density_changed(index: int, value: float) -> void:
	if index < mesh_resources.size():
		mesh_resources[index].density = value
		mesh_resources_changed.emit()

func _remove_mesh(index: int) -> void:
	if index < mesh_resources.size():
		mesh_resources.remove_at(index)
		_rebuild_mesh_list()
		mesh_resources_changed.emit()

func _build_brush_settings_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Brush Settings")
	
	# Radius
	var radius_hbox = HBoxContainer.new()
	section.add_child(radius_hbox)
	
	var radius_label = Label.new()
	radius_label.text = "Radius:"
	radius_label.custom_minimum_size.x = 60
	radius_hbox.add_child(radius_label)
	
	_radius_slider = HSlider.new()
	_radius_slider.min_value = 0.5
	_radius_slider.max_value = 50.0
	_radius_slider.step = 0.5
	_radius_slider.value = brush_radius
	_radius_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radius_slider.value_changed.connect(func(val): brush_radius = val)
	radius_hbox.add_child(_radius_slider)
	
	_radius_value_label = Label.new()
	_radius_value_label.text = "%.1f" % brush_radius
	_radius_value_label.custom_minimum_size.x = 40
	radius_hbox.add_child(_radius_value_label)
	_radius_slider.value_changed.connect(func(val): _radius_value_label.text = "%.1f" % val)
	
	# Density
	var density_hbox = HBoxContainer.new()
	section.add_child(density_hbox)
	
	var density_label = Label.new()
	density_label.text = "Density:"
	density_label.custom_minimum_size.x = 60
	density_hbox.add_child(density_label)
	
	_density_slider = HSlider.new()
	_density_slider.min_value = 0.1
	_density_slider.max_value = 5.0
	_density_slider.step = 0.1
	_density_slider.value = brush_density
	_density_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_density_slider.value_changed.connect(func(val): brush_density = val)
	density_hbox.add_child(_density_slider)
	
	_density_value_label = Label.new()
	_density_value_label.text = "%.1f" % brush_density
	_density_value_label.custom_minimum_size.x = 40
	density_hbox.add_child(_density_value_label)
	_density_slider.value_changed.connect(func(val): _density_value_label.text = "%.1f" % val)

func _build_randomization_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Randomization")
	
	# Offset
	_build_vector3_range(section, "Offset", 
		offset_min, offset_max,
		-10.0, 10.0, 0.1,
		func(min_val, max_val): 
			offset_min = min_val
			offset_max = max_val
	)
	
	# Rotation
	_build_vector3_range(section, "Rotation", 
		rotation_min, rotation_max,
		0.0, 360.0, 1.0,
		func(min_val, max_val): 
			rotation_min = min_val
			rotation_max = max_val
	)
	
	# Scale
	_build_vector3_range(section, "Scale", 
		scale_min, scale_max,
		0.1, 5.0, 0.1,
		func(min_val, max_val): 
			scale_min = min_val
			scale_max = max_val
	)

func _build_vector3_range(parent: VBoxContainer, label_text: String, 
	initial_min: Vector3, initial_max: Vector3,
	range_min: float, range_max: float, step: float,
	callback: Callable) -> void:
	
	var title_label = Label.new()
	title_label.text = label_text + ":"
	title_label.add_theme_font_size_override("font_size", 11)
	parent.add_child(title_label)
	
	# Min row
	var min_hbox = HBoxContainer.new()
	min_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(min_hbox)
	
	var min_label = Label.new()
	min_label.text = "Min:"
	min_label.custom_minimum_size.x = 35
	min_hbox.add_child(min_label)
	
	var min_x = _create_spinbox(range_min, range_max, step, initial_min.x)
	var min_y = _create_spinbox(range_min, range_max, step, initial_min.y)
	var min_z = _create_spinbox(range_min, range_max, step, initial_min.z)
	
	min_hbox.add_child(min_x)
	min_hbox.add_child(min_y)
	min_hbox.add_child(min_z)
	
	# Max row
	var max_hbox = HBoxContainer.new()
	max_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(max_hbox)
	
	var max_label = Label.new()
	max_label.text = "Max:"
	max_label.custom_minimum_size.x = 35
	max_hbox.add_child(max_label)
	
	var max_x = _create_spinbox(range_min, range_max, step, initial_max.x)
	var max_y = _create_spinbox(range_min, range_max, step, initial_max.y)
	var max_z = _create_spinbox(range_min, range_max, step, initial_max.z)
	
	max_hbox.add_child(max_x)
	max_hbox.add_child(max_y)
	max_hbox.add_child(max_z)
	
	# Connect callbacks
	var update = func(_val):
		callback.call(
			Vector3(min_x.value, min_y.value, min_z.value),
			Vector3(max_x.value, max_y.value, max_z.value)
		)
	
	min_x.value_changed.connect(update)
	min_y.value_changed.connect(update)
	min_z.value_changed.connect(update)
	max_x.value_changed.connect(update)
	max_y.value_changed.connect(update)
	max_z.value_changed.connect(update)

func _create_spinbox(p_min: float, p_max: float, p_step: float, p_value: float) -> SpinBox:
	var spinbox = SpinBox.new()
	spinbox.min_value = p_min
	spinbox.max_value = p_max
	spinbox.step = p_step
	spinbox.value = p_value
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.custom_minimum_size.x = 50
	return spinbox
	
func get_selected_node() -> Node:
	# Use EditorInterface to access the editor's selection state
	var selection = EditorInterface.get_selection().get_selected_nodes()
	if selection.size() > 0:
		return selection[0] # Return the first selected node
	return null

func _has_static_body_child(mesh: MeshInstance3D) -> bool:
	for child in mesh.get_children():
		if child is StaticBody3D:
			return true
	return false
