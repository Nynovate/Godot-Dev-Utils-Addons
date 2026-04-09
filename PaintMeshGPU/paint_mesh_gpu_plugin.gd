@tool
extends EditorPlugin

var _dock: PaintMeshGPUDock = null
var _brush_preview_material: ShaderMaterial = null
var _preview_mesh_instance: MeshInstance3D = null

# Chunk system
const CHUNK_SIZE: float = 32.0
var _chunks: Dictionary = {} # Key: Vector2i (chunk coords), Value: ChunkData

# Chunk data class
class ChunkData:
	var chunk_node: Node3D
	var multimesh_instances: Dictionary = {} # Key: Mesh resource, Value: MultiMeshInstance3D
	var instance_data: Array[InstanceData] = [] # All instances in this chunk
	
	func _init(p_chunk_node: Node3D):
		chunk_node = p_chunk_node

# Instance data class
class InstanceData:
	var mesh: Mesh
	var transform: Transform3D
	var chunk_coord: Vector2i
	
	func _init(p_mesh: Mesh, p_transform: Transform3D, p_chunk_coord: Vector2i):
		mesh = p_mesh
		transform = p_transform
		chunk_coord = p_chunk_coord

const BRUSH_PREVIEW_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

uniform vec3 brush_center;
uniform float brush_radius = 5.0;
uniform vec4 brush_color : source_color = vec4(0.2, 0.8, 1.0, 0.5);
uniform float brush_falloff = 0.9;
uniform float edge_thickness = 0.1;

void fragment() {
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
	
	ALBEDO = brush_color.rgb;
	ALPHA = alpha;
}
"""

func _enter_tree() -> void:
	_dock = PaintMeshGPUDock.new()
	_dock.name = "PaintMeshGPU"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	
	_setup_brush_preview()

func _exit_tree() -> void:
	_cleanup_brush_preview()
	remove_control_from_docks(_dock)
	if _dock:
		_dock.queue_free()

func _setup_brush_preview() -> void:
	var shader = Shader.new()
	shader.code = BRUSH_PREVIEW_SHADER
	
	_brush_preview_material = ShaderMaterial.new()
	_brush_preview_material.shader = shader
	_brush_preview_material.set_shader_parameter("brush_center", Vector3.ZERO)
	_brush_preview_material.set_shader_parameter("brush_radius", 5.0)
	_brush_preview_material.set_shader_parameter("brush_color", Color(0.2, 0.8, 1.0, 0.6))

func _cleanup_brush_preview() -> void:
	if _preview_mesh_instance and is_instance_valid(_preview_mesh_instance):
		_preview_mesh_instance.queue_free()
		_preview_mesh_instance = null

func _on_selection_changed() -> void:
	_hide_brush_preview()
	if _dock:
		_dock._update_button_state()

func _handles(object: Object) -> bool:
	return object is MeshInstance3D

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _dock:
		return AFTER_GUI_INPUT_PASS
	
	# Handle mouse movement for brush preview
	if event is InputEventMouseMotion:
		if _dock.paint_active or _dock.erase_mode:
			var result = _perform_raycast(camera, event.position)
			if result:
				_update_brush_preview(result.position, result.normal)
				return AFTER_GUI_INPUT_PASS
			else:
				_hide_brush_preview()
		else:
			_hide_brush_preview()
		return AFTER_GUI_INPUT_PASS
	
	# Handle painting
	if _dock.paint_active and event is InputEventMouseButton and event.shift_pressed and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var result = _perform_raycast(camera, event.position)
		if result:
			_paint_instances(result.position, result.normal)
			return AFTER_GUI_INPUT_STOP
	
	# Handle erasing
	if _dock.erase_mode and event is InputEventMouseButton and event.shift_pressed and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var result = _perform_raycast(camera, event.position)
		if result:
			_erase_instances(result.position)
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _paint_instances(center_pos: Vector3, surface_normal: Vector3) -> void:
	if _dock.mesh_resources.is_empty():
		return
	
	# Calculate number of instances to spawn based on brush density
	var num_instances = int(_dock.brush_density * 10.0)
	
	for i in num_instances:
		# Random position within brush radius
		var random_angle = randf() * TAU
		var random_distance = sqrt(randf()) * _dock.brush_radius
		var offset_2d = Vector2(cos(random_angle), sin(random_angle)) * random_distance
		var spawn_pos = center_pos + Vector3(offset_2d.x, 0, offset_2d.y)
		
		# Raycast down to find actual surface height at this position
		var hit = _raycast_down(spawn_pos + Vector3.UP * 10.0)
		if not hit:
			continue
		
		spawn_pos = hit.position
		
		# Pick random mesh based on density weights
		var selected_mesh = _pick_random_mesh()
		if not selected_mesh:
			continue
		
		# Create transform with randomization
		var instance_transform = _create_randomized_transform(spawn_pos, hit.normal)
		
		# Get chunk coordinate and add instance
		var chunk_coord = _world_to_chunk(spawn_pos)
		_add_instance_to_chunk(chunk_coord, selected_mesh, instance_transform)

func _erase_instances(center_pos: Vector3) -> void:
	# Find all chunks that could be affected by the brush
	var affected_chunks = _get_chunks_in_radius(center_pos, _dock.brush_radius)
	
	for chunk_coord in affected_chunks:
		if not _chunks.has(chunk_coord):
			continue
		
		var chunk = _chunks[chunk_coord] as ChunkData
		var instances_to_remove: Array[int] = []
		
		# Find instances within brush radius
		for i in range(chunk.instance_data.size()):
			var instance = chunk.instance_data[i]
			var dist = center_pos.distance_to(instance.transform.origin)
			if dist <= _dock.brush_radius:
				instances_to_remove.append(i)
		
		# Remove instances in reverse order to maintain indices
		instances_to_remove.reverse()
		for idx in instances_to_remove:
			chunk.instance_data.remove_at(idx)
		
		# Rebuild the chunk's multimeshes
		_rebuild_chunk_multimeshes(chunk)

func _pick_random_mesh() -> Mesh:
	if _dock.mesh_resources.is_empty():
		return null
	
	# Calculate total weight
	var total_weight = 0.0
	for mesh_res in _dock.mesh_resources:
		if mesh_res.mesh:
			total_weight += mesh_res.density
	
	if total_weight <= 0.0:
		return null
	
	# Random selection based on weight
	var random_value = randf() * total_weight
	var current_weight = 0.0
	
	for mesh_res in _dock.mesh_resources:
		if mesh_res.mesh:
			current_weight += mesh_res.density
			if random_value <= current_weight:
				return mesh_res.mesh
	
	# Fallback to first valid mesh
	for mesh_res in _dock.mesh_resources:
		if mesh_res.mesh:
			return mesh_res.mesh
	
	return null

func _create_randomized_transform(position: Vector3, normal: Vector3) -> Transform3D:
	var transform = Transform3D()
	
	# Apply random offset
	var random_offset = Vector3(
		randf_range(_dock.offset_min.x, _dock.offset_max.x),
		randf_range(_dock.offset_min.y, _dock.offset_max.y),
		randf_range(_dock.offset_min.z, _dock.offset_max.z)
	)
	position += random_offset
	
	# Align to surface normal (simplified - pointing up by default)
	var up = normal.normalized()
	var right = up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.01:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward = right.cross(up).normalized()
	
	transform.basis = Basis(right, up, forward)
	
	# Apply random rotation
	var random_rotation = Vector3(
		deg_to_rad(randf_range(_dock.rotation_min.x, _dock.rotation_max.x)),
		deg_to_rad(randf_range(_dock.rotation_min.y, _dock.rotation_max.y)),
		deg_to_rad(randf_range(_dock.rotation_min.z, _dock.rotation_max.z))
	)
	transform.basis = transform.basis.rotated(Vector3.RIGHT, random_rotation.x)
	transform.basis = transform.basis.rotated(Vector3.UP, random_rotation.y)
	transform.basis = transform.basis.rotated(Vector3.BACK, random_rotation.z)
	
	# Apply random scale
	var random_scale = Vector3(
		randf_range(_dock.scale_min.x, _dock.scale_max.x),
		randf_range(_dock.scale_min.y, _dock.scale_max.y),
		randf_range(_dock.scale_min.z, _dock.scale_max.z)
	)
	transform.basis = transform.basis.scaled(random_scale)
	
	transform.origin = position
	return transform

func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / CHUNK_SIZE)),
		int(floor(world_pos.z / CHUNK_SIZE))
	)

func _get_chunks_in_radius(center: Vector3, radius: float) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	var center_chunk = _world_to_chunk(center)
	var chunk_radius = int(ceil(radius / CHUNK_SIZE))
	
	for x in range(-chunk_radius, chunk_radius + 1):
		for z in range(-chunk_radius, chunk_radius + 1):
			chunks.append(center_chunk + Vector2i(x, z))
	
	return chunks

func _raycast_down(from_pos: Vector3) -> Dictionary:
	var root = EditorInterface.get_edited_scene_root()
	if not root or not root.is_inside_tree():
		return {}
		
	var world_3d = root.get_world_3d()
	if not world_3d:
		return {}
		
	var space_state = world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, from_pos + Vector3.DOWN * 20.0)
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)

func _add_instance_to_chunk(chunk_coord: Vector2i, mesh: Mesh, instance_transform: Transform3D) -> void:
	var chunk = _get_or_create_chunk(chunk_coord)
	
	# Create instance data
	var instance = InstanceData.new(mesh, instance_transform, chunk_coord)
	chunk.instance_data.append(instance)
	
	# Get or create MultiMeshInstance3D for this mesh type
	var mmi = _get_or_create_multimesh(chunk, mesh)
	
	# Update the multimesh
	_rebuild_chunk_multimeshes(chunk)

func _get_or_create_chunk(chunk_coord: Vector2i) -> ChunkData:
	if _chunks.has(chunk_coord):
		return _chunks[chunk_coord]
	
	# Create new chunk
	var container = _get_or_create_gpu_instance_container()
	if not container:
		return null
	
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	container.add_child(chunk_node)
	chunk_node.owner = EditorInterface.get_edited_scene_root()
	
	var chunk = ChunkData.new(chunk_node)
	_chunks[chunk_coord] = chunk
	
	return chunk

func _get_or_create_multimesh(chunk: ChunkData, mesh: Mesh) -> MultiMeshInstance3D:
	if chunk.multimesh_instances.has(mesh):
		return chunk.multimesh_instances[mesh]
	
	# Create new MultiMeshInstance3D
	var mmi = MultiMeshInstance3D.new()
	mmi.name = mesh.resource_name if mesh.resource_name else "Mesh"
	
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	
	mmi.multimesh = multimesh
	chunk.chunk_node.add_child(mmi)
	mmi.owner = EditorInterface.get_edited_scene_root()
	
	chunk.multimesh_instances[mesh] = mmi
	
	return mmi

func _rebuild_chunk_multimeshes(chunk: ChunkData) -> void:
	# Group instances by mesh type
	var instances_by_mesh: Dictionary = {}
	
	for instance in chunk.instance_data:
		if not instances_by_mesh.has(instance.mesh):
			instances_by_mesh[instance.mesh] = []
		instances_by_mesh[instance.mesh].append(instance)
	
	# Update each MultiMeshInstance3D
	for mesh in chunk.multimesh_instances.keys():
		var mmi = chunk.multimesh_instances[mesh] as MultiMeshInstance3D
		var instances = instances_by_mesh.get(mesh, [])
		
		if instances.is_empty():
			# Remove empty multimesh
			mmi.queue_free()
			chunk.multimesh_instances.erase(mesh)
			continue
		
		# Update multimesh instance count and transforms
		mmi.multimesh.instance_count = instances.size()
		for i in instances.size():
			mmi.multimesh.set_instance_transform(i, instances[i].transform)

func _update_brush_preview(position: Vector3, normal: Vector3) -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty() or not selected[0] is MeshInstance3D:
		_hide_brush_preview()
		return
	
	var target_mesh = selected[0] as MeshInstance3D
	
	# Create or update preview mesh instance
	if not _preview_mesh_instance or not is_instance_valid(_preview_mesh_instance):
		_preview_mesh_instance = MeshInstance3D.new()
		_preview_mesh_instance.mesh = target_mesh.mesh
		_preview_mesh_instance.material_override = _brush_preview_material
		_preview_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview_mesh_instance.top_level = true
		target_mesh.add_child(_preview_mesh_instance)
	
	# Update shader parameters
	_brush_preview_material.set_shader_parameter("brush_center", position)
	_brush_preview_material.set_shader_parameter("brush_radius", _dock.brush_radius)
	
	# Update color based on mode
	if _dock.erase_mode:
		_brush_preview_material.set_shader_parameter("brush_color", Color(1.0, 0.3, 0.2, 0.6))
	else:
		_brush_preview_material.set_shader_parameter("brush_color", Color(0.2, 0.8, 1.0, 0.6))
	
	# Position the preview mesh to match the target
	_preview_mesh_instance.global_transform = target_mesh.global_transform

func _hide_brush_preview() -> void:
	if _preview_mesh_instance and is_instance_valid(_preview_mesh_instance):
		_preview_mesh_instance.queue_free()
		_preview_mesh_instance = null

func _get_or_create_gpu_instance_container() -> Node3D:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return null
	
	# Try to find existing container
	var container = root.find_child("GPUInstance", false, false)
	
	if not container:
		container = Node3D.new()
		container.name = "GPUInstance"
		root.add_child(container)
		# CRITICAL: Set owner so it appears in the tree and saves
		container.owner = root
	
	return container

func _perform_raycast(camera: Camera3D, mouse_pos: Vector2):
	var space_state = camera.get_world_3d().direct_space_state
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	
	return space_state.intersect_ray(query)
