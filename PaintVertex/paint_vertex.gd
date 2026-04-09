@tool
extends EditorPlugin

var _dock: PaintVertexDock
var _active_mesh: MeshInstance3D = null
var _overlay_material: ShaderMaterial = null
var _preview_mesh_instance: MeshInstance3D = null

const OVERLAY_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

uniform vec3 brush_center;
uniform float brush_radius = 5.0;
uniform vec4 brush_color : source_color = vec4(0.2, 0.8, 1.0, 0.5);
uniform float brush_falloff = 0.9;
uniform float edge_thickness = 0.1;
uniform bool show_vertex_colors = false;

void fragment() {
	vec3 base_color = show_vertex_colors ? COLOR.rgb : vec3(0.0);
	
	// Calculate world position
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Distance from brush center (only XZ plane for typical terrain painting)
	float dist = length(world_pos.xz - brush_center.xz);
	
	// Circle with soft edge
	float circle = smoothstep(brush_radius, brush_radius * brush_falloff, dist);
	
	// Outer edge ring
	float edge = smoothstep(brush_radius - edge_thickness, brush_radius, dist) 
	           - smoothstep(brush_radius, brush_radius + edge_thickness, dist);
	
	// Combine circle fill and edge
	float alpha = max(circle * brush_color.a * 0.3, edge * brush_color.a);
	
	if (show_vertex_colors) {
		// Show vertex colors with brush overlay
		ALBEDO = mix(base_color, brush_color.rgb, alpha);
		ALPHA = 1.0; // Fully opaque when showing vertex colors
	} else {
		// Just show brush circle
		ALBEDO = brush_color.rgb;
		ALPHA = alpha;
	}
}
"""


func _get_plugin_name() -> String:
	return "Vertex Painter"


func _handles(object: Object) -> bool:
	return true

func _enter_tree() -> void:
	_dock = preload("res://addons/PaintVertex/paint_vertex_UI.gd").new() as PaintVertexDock
	_dock.name = "PaintVertex"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	_dock.paint_mode_changed.connect(_on_paint_mode_changed)
	_dock.brush_radius_changed.connect(_on_brush_radius_changed)
	_dock.brush_strength_changed.connect(_on_brush_strength_changed)
	_dock.live_preview_toggled.connect(_on_live_preview_toggled)

	# Listen to selection changes
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_dock.set_painting_enabled(false)  # disabled by default until a mesh is selected
	
	_setup_overlay_material()


func _exit_tree() -> void:
	var sel := get_editor_interface().get_selection()
	if sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)
	_cleanup_overlay()
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

func _setup_overlay_material() -> void:
	var shader = Shader.new()
	shader.code = OVERLAY_SHADER
	
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = shader
	_overlay_material.set_shader_parameter("brush_center", Vector3.ZERO)
	_overlay_material.set_shader_parameter("brush_radius", 5.0)
	_overlay_material.set_shader_parameter("brush_color", Color(0.2, 0.8, 1.0, 0.6))
	_overlay_material.set_shader_parameter("show_vertex_colors", false)

func _save_mesh(mesh_instance: MeshInstance3D) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return

	var path := mesh.resource_path

	# Force save as .res if it's an OBJ
	if path.ends_with(".obj"):
		path = path.get_basename() + ".res"
		mesh.resource_path = path

	var err := ResourceSaver.save(mesh, path)
	if err != OK:
		push_error("VertexPainter: failed to save mesh at " + path)

func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	var has_valid_mesh := false
	var found_mesh: MeshInstance3D = null

	for node in selected:
		if node is MeshInstance3D:
			found_mesh = node
			# Check if it has a StaticBody3D child
			if _has_static_body_child(found_mesh):
				has_valid_mesh = true
			break

	_dock.update_warning_state(found_mesh, has_valid_mesh)
	_dock.set_painting_enabled(has_valid_mesh)

	if not has_valid_mesh:
		_cleanup_overlay()
		_dock.force_paint_off()
	elif _dock.paint_active and found_mesh != _active_mesh:
		# Switched to a different mesh while painting — swap material
		_cleanup_overlay()
		_apply_overlay_material(found_mesh)


# ── Viewport input ────────────────────────────────────────────────────────────

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _dock or not _dock.paint_active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Hover — update brush position preview
	if event is InputEventMouseMotion:
		_update_brush_preview(viewport_camera, event.position)
		# Only consume if painting
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT and event.ctrl_pressed:
			_do_paint(viewport_camera, event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and event.ctrl_pressed:
			_do_paint(viewport_camera, event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


# ── Material overlay ─────────────────────────────────────────────────────────────

func _apply_overlay_material(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	if mesh_instance.mesh.get_surface_count() == 0:
		return

	if _active_mesh == mesh_instance and _preview_mesh_instance != null:
		return

	if _active_mesh != null and _active_mesh != mesh_instance:
		_cleanup_overlay()

	_active_mesh = mesh_instance
	
	# Create or update preview mesh instance
	if not _preview_mesh_instance or not is_instance_valid(_preview_mesh_instance):
		_preview_mesh_instance = MeshInstance3D.new()
		_preview_mesh_instance.mesh = mesh_instance.mesh
		_preview_mesh_instance.material_override = _overlay_material
		_preview_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview_mesh_instance.top_level = true
		mesh_instance.add_child(_preview_mesh_instance)
	
	# Position the preview mesh to match the target
	_preview_mesh_instance.global_transform = mesh_instance.global_transform
	
	# Update shader parameters
	_overlay_material.set_shader_parameter("brush_radius", _dock.brush_radius)
	_overlay_material.set_shader_parameter("brush_color", _dock.paint_color)
	_overlay_material.set_shader_parameter("show_vertex_colors", _dock.live_preview)


func _cleanup_overlay() -> void:
	if _preview_mesh_instance and is_instance_valid(_preview_mesh_instance):
		_preview_mesh_instance.queue_free()
		_preview_mesh_instance = null
	_active_mesh = null


# ── Brush preview update ──────────────────────────────────────────────────────

func _update_brush_preview(camera: Camera3D, mouse_pos: Vector2) -> void:
	var origin    := camera.project_ray_origin(mouse_pos)
	var direction := camera.project_ray_normal(mouse_pos)
	var ray_end   := origin + direction * 4096.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = false

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_position := result["position"] as Vector3
	var hit_object   := result["collider"] as Node
	var mesh_instance := _find_mesh_instance(hit_object)

	if mesh_instance == null:
		return

	_apply_overlay_material(mesh_instance)

	if _overlay_material:
		_overlay_material.set_shader_parameter("brush_center", hit_position)
		_overlay_material.set_shader_parameter("brush_radius", _dock.brush_radius)
		_overlay_material.set_shader_parameter("brush_color", _dock.paint_color)


# ── Raycasting ────────────────────────────────────────────────────────────────

func _find_mesh_instance(hit_object: Node) -> MeshInstance3D:
	if hit_object is MeshInstance3D:
		return hit_object
	var parent := hit_object.get_parent()
	if parent is MeshInstance3D:
		return parent
	for child in parent.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _do_paint(camera: Camera3D, mouse_pos: Vector2) -> void:
	var origin    := camera.project_ray_origin(mouse_pos)
	var direction := camera.project_ray_normal(mouse_pos)
	var ray_end   := origin + direction * 4096.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = false

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_position := result["position"] as Vector3
	var hit_object   := result["collider"] as Node
	var mesh_instance := _find_mesh_instance(hit_object)

	if mesh_instance == null:
		return

	if not mesh_instance.mesh is ArrayMesh:
		return

	var array_mesh := mesh_instance.mesh as ArrayMesh
	if array_mesh.get_surface_count() == 0:
		return

	var surface_arrays := array_mesh.surface_get_arrays(0)
	var vertices       := surface_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array

	var colors := PackedColorArray()
	var existing = surface_arrays[Mesh.ARRAY_COLOR]
	if existing != null and existing is PackedColorArray:
		colors = existing as PackedColorArray
	if colors.size() != vertices.size():
		colors.resize(vertices.size())
		for i in range(colors.size()):
			colors[i] = Color.WHITE

	var strength     := _dock.brush_strength
	var target_color := _dock.paint_color
	var local_hit    := mesh_instance.to_local(hit_position)
	var radius       := _dock.brush_radius

	var painted := 0
	for i in range(vertices.size()):
		var dist := vertices[i].distance_to(local_hit)
		if dist <= radius:
			var falloff := 1.0 - (dist / radius)
			var blend   := strength * falloff
			colors[i]   = colors[i].lerp(target_color, blend)
			painted     += 1

	if painted == 0:
		return

	# Write back to mesh
	surface_arrays[Mesh.ARRAY_COLOR] = colors
	var flags := array_mesh.surface_get_format(0)
	flags |= Mesh.ARRAY_FORMAT_COLOR
	array_mesh.clear_surfaces()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays, [], {}, flags)

	# Re-apply overlay material since clear_surfaces() might affect it
	if _preview_mesh_instance != null and _active_mesh != null:
		_preview_mesh_instance.mesh = array_mesh
	
	_save_mesh(mesh_instance)


# ── Dock signal handlers ──────────────────────────────────────────────────────

func _on_paint_mode_changed(enabled: bool) -> void:
	if enabled:
		# Grab the currently selected MeshInstance3D and apply overlay immediately
		var selected := get_editor_interface().get_selection().get_selected_nodes()
		for node in selected:
			if node is MeshInstance3D and _has_static_body_child(node):
				_apply_overlay_material(node)
				break
	else:
		_cleanup_overlay()


func _on_brush_radius_changed(value: float) -> void:
	if _overlay_material:
		_overlay_material.set_shader_parameter("brush_radius", value)


func _on_brush_strength_changed(value: float) -> void:
	pass


func _on_live_preview_toggled(enabled: bool) -> void:
	if _overlay_material:
		_overlay_material.set_shader_parameter("show_vertex_colors", enabled)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _has_static_body_child(mesh: MeshInstance3D) -> bool:
	for child in mesh.get_children():
		if child is StaticBody3D:
			return true
	return false
