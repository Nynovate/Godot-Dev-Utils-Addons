@tool
extends EditorPlugin

var _dock: PaintSceneDock = null
var spawned_rids = []

func _enter_tree() -> void:
	_dock = PaintSceneDock.new()
	_dock.name = "PaintScene"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)

func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	if _dock:
		_dock.queue_free()

func _on_selection_changed() -> void:
	if _dock:
		_dock._update_button_state()

func _handles(object: Object) -> bool:
	return object is MeshInstance3D

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _dock or not _dock.paint_active or not _dock.spawn_scene:
		return AFTER_GUI_INPUT_PASS

	# Right Click + Shift to paint
	if event is InputEventMouseButton and event.shift_pressed and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var result = _perform_raycast(camera, event.position)
		if result:
			_spawn_object(result.position, result.normal)
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS

func _get_or_create_paint_container() -> Node3D:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return null
	
	# Try to find existing container
	var container = root.find_child("ScenePainted", false, false)
	
	if not container:
		container = Node3D.new()
		container.name = "ScenePainted"
		root.add_child(container)
		# CRITICAL: Set owner so it appears in the tree and saves
		container.owner = root
	
	return container

func _perform_raycast(camera: Camera3D, mouse_pos: Vector2):
	var space_state = camera.get_world_3d().direct_space_state
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = spawned_rids
	query.collide_with_bodies = true
	
	return space_state.intersect_ray(query)

func _spawn_object(pos: Vector3, normal: Vector3) -> void:
	var container = _get_or_create_paint_container()
	if not container:
		return

	var new_node = _dock.spawn_scene.instantiate()
	
	# 1. Setup the node properties BEFORE adding it to the tree
	var unique_id = str(Time.get_ticks_usec()).right(6)
	new_node.name = "instance_" + unique_id
	new_node.global_position = pos
	_align_object(new_node, normal)
	
	# Apply random rotation if needed
	if _dock.random_rotation > 0:
		var random_rad = deg_to_rad(randf_range(0, _dock.random_rotation))
		new_node.rotate_object_local(Vector3.UP, random_rad)

	# 2. Use UndoRedo to handle the addition
	var ur = get_undo_redo()
	ur.create_action("Paint Scene Object")
	
	# Add the node
	ur.add_do_method(container, "add_child", new_node)
	# Set the owner (must happen after add_child)
	ur.add_do_reference(new_node) # Ensures the node isn't leaked if undone
	ur.add_do_method(new_node, "set_owner", EditorInterface.get_edited_scene_root())
	
	# Undo logic: remove the node
	ur.add_undo_method(container, "remove_child", new_node)
	
	ur.commit_action()

func _align_object(node: Node3D, normal: Vector3) -> void:
	match _dock.spawn_axis:
		0: # SURFACE_NORMAL
			var target_normal = normal
			var world_up = Vector3.UP
			
			# Calculate the angle between the surface and world up
			var angle_rad = world_up.angle_to(normal)
			var angle_deg = rad_to_deg(angle_rad)
			
			# If the tilt is too steep, blend back toward world up
			if angle_deg > _dock.max_tilt:
				if _dock.max_tilt <= 0.01:
					target_normal = world_up
				else:
					# Calculate how much to interpolate (0.0 to 1.0)
					var weight = _dock.max_tilt / angle_deg
					# Spherically interpolate the vectors to maintain length
					target_normal = world_up.slerp(normal, weight).normalized()

			# Construct Basis with the (potentially clamped) normal
			var v_up = target_normal
			var v_right: Vector3
			
			if abs(v_up.z) < 0.9:
				v_right = v_up.cross(Vector3.BACK).normalized()
			else:
				v_right = v_up.cross(Vector3.RIGHT).normalized()
				
			var v_forward = v_right.cross(v_up).normalized()
			node.basis = Basis(v_right, v_up, v_forward)
			
		# ... (rest of match cases) ...
