@tool
class_name PaintSceneDock
extends Control

enum SpawnAxis {
	SURFACE_NORMAL,
	GLOBAL_X,
	GLOBAL_Y,
	GLOBAL_Z
}

var paint_active: bool
var _mode_button: Button
var spawn_axis: int = SpawnAxis.SURFACE_NORMAL
var _axis_option: OptionButton
var _warning_label: Label
var spawn_scene: PackedScene = null
var _resource_picker: EditorResourcePicker
var random_rotation: float = 0.0
var _rotation_spinbox: SpinBox
var max_tilt: float = 90.0
var _tilt_spinbox: SpinBox

const DISABLE_PAINT_MODE_TEXT: String = "Disable Paint Mode"
const ENABLE_PAINT_MODE_TEXT: String = "Enable Paint Mode"

signal paint_mode_changed(enabled: bool)
signal spawn_axis_changed(axis: int)
signal spawn_scene_changed(scene: PackedScene)

func _ready() -> void:
	custom_minimum_size = Vector2(180, 0)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	_build_mode_section(root_vbox)
	_build_warning_section(root_vbox)
	_build_separator(root_vbox)
	_build_axis_section(root_vbox)
	_build_random_section(root_vbox)
	_build_scene_picker_section(root_vbox)

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

func _on_mode_toggled(pressed: bool) -> void:
	paint_active = pressed
	_mode_button.text = DISABLE_PAINT_MODE_TEXT if pressed else ENABLE_PAINT_MODE_TEXT
	paint_mode_changed.emit(pressed)

func _build_warning_section(parent: VBoxContainer) -> void:
	_warning_label = Label.new()
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0)) # yellow
	_warning_label.text = ""
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(_warning_label)

func _build_scene_picker_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Scene to Paint")

	_resource_picker = EditorResourcePicker.new()
	_resource_picker.base_type = "PackedScene" # Restrict to .tscn files
	_resource_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_picker.resource_changed.connect(_on_scene_changed)
	section.add_child(_resource_picker)

func _on_scene_changed(resource: Resource) -> void:
	if resource is PackedScene or resource == null:
		spawn_scene = resource
		spawn_scene_changed.emit(spawn_scene)
		_update_button_state() # Re-check if we can paint

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
	elif spawn_scene == null:
		warning_text = "Please select a Scene to paint."
	else:
		enable_button = true
		_warning_label.visible = false

	set_painting_enabled(enable_button)
	_warning_label.text = warning_text

func _build_axis_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Spawn Axis")

	_axis_option = OptionButton.new()
	_axis_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_axis_option.add_item("Surface Normal", SpawnAxis.SURFACE_NORMAL)
	_axis_option.add_item("Global X", SpawnAxis.GLOBAL_X)
	_axis_option.add_item("Global Y", SpawnAxis.GLOBAL_Y)
	_axis_option.add_item("Global Z", SpawnAxis.GLOBAL_Z)

	_axis_option.selected = spawn_axis
	_axis_option.item_selected.connect(_on_axis_selected)
	section.add_child(_axis_option)

func _on_axis_selected(index: int) -> void:
	spawn_axis = index
	spawn_axis_changed.emit(index)

func _build_random_section(parent: VBoxContainer) -> void:
	var section := _make_section(parent, "Randomization")
	
	# --- Random Rotation Row ---
	var hbox_rot := HBoxContainer.new()
	section.add_child(hbox_rot)
	
	var lbl_rot := Label.new()
	lbl_rot.text = "Max Y-Rot:"
	lbl_rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_rot.add_child(lbl_rot)
	
	_rotation_spinbox = SpinBox.new()
	_rotation_spinbox.max_value = 360
	_rotation_spinbox.value_changed.connect(func(val): random_rotation = val)
	hbox_rot.add_child(_rotation_spinbox)

	# --- Max Tilt Row ---
	var hbox_tilt := HBoxContainer.new()
	section.add_child(hbox_tilt)
	
	var lbl_tilt := Label.new()
	lbl_tilt.text = "Max Tilt:"
	lbl_tilt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_tilt.add_child(lbl_tilt)
	
	_tilt_spinbox = SpinBox.new()
	_tilt_spinbox.min_value = 0
	_tilt_spinbox.max_value = 180
	_tilt_spinbox.value = 90 # Default allows full surface alignment
	_tilt_spinbox.suffix = "°"
	_tilt_spinbox.value_changed.connect(func(val): max_tilt = val)
	hbox_tilt.add_child(_tilt_spinbox)

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
