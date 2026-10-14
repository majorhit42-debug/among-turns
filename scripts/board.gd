class_name Board
extends Node3D
## Draws the lumber camp in 3D: places, dirt paths, pine trees, lumberjacks and
## bodies. It only shows what the current viewer is allowed to see — the people
## and bodies in their own place.

signal room_clicked(room: String)

const FLOOR_COLOR := Color(0.50, 0.34, 0.20)  ## Wooden plank floors.
const HALL_COLOR := Color(0.47, 0.38, 0.26)  ## Dirt paths.
const GRASS_COLOR := Color(0.20, 0.36, 0.16)
const MOVE_COLOR := Color(0.55, 0.85, 0.40)  ## Places you can walk to this turn.
const HERE_COLOR := Color(0.95, 0.72, 0.25)  ## The place you're standing in.
const SKIN_COLOR := Color(0.93, 0.74, 0.58)
const BEARD_COLOR := Color(0.36, 0.22, 0.12)
const HANDLE_COLOR := Color(0.55, 0.38, 0.20)
const BLADE_COLOR := Color(0.78, 0.80, 0.84)
const TREE_COUNT := 140

## Spots inside a room where figures stand, front rows first.
const SLOTS := [
	Vector2(-2.8, 1.3), Vector2(0, 1.3), Vector2(2.8, 1.3),
	Vector2(-2.8, 3.7), Vector2(0, 3.7), Vector2(2.8, 3.7),
	Vector2(-2.8, -1.1), Vector2(0, -1.1), Vector2(2.8, -1.1),
	Vector2(-1.4, 2.5), Vector2(1.4, 2.5),
]

var _room_materials := {}  ## room -> StandardMaterial3D
var _task_marks := {}  ## room -> Label3D
var _vent_marks := {}  ## room -> Node3D
var _clickable: Array[String] = []
var _figures: Array[Node3D] = []


func _ready() -> void:
	_build_environment()
	_build_trees()
	for hall in MapData.HALLS:
		_build_hall(hall[0], hall[1])
	for room in MapData.ROOMS:
		_build_room(room)


## Shows the board through `viewer`'s eyes. `viewer` null = show no one (between turns).
## `reveal_all` shows every living player and body (game over).
func show_view(state: GameState, viewer: GameState.Player, moves: Array[String], reveal_all := false) -> void:
	for figure in _figures:
		figure.queue_free()
	_figures.clear()
	_clickable = moves.duplicate()
	for room in MapData.ROOMS:
		var color := FLOOR_COLOR
		if viewer and room == viewer.room:
			color = HERE_COLOR
		elif moves.has(room):
			color = MOVE_COLOR
		_room_materials[room].albedo_color = color
		_task_marks[room].visible = viewer != null and _has_open_task(viewer, room)
		_vent_marks[room].visible = viewer != null and viewer.impostor
	if state.players.is_empty():
		return
	if reveal_all:
		for room in MapData.ROOMS:
			_place_room(state, room, null)
	elif viewer:
		_place_room(state, viewer.room, viewer)


func _place_room(state: GameState, room: String, viewer: GameState.Player) -> void:
	var slot := 0
	for p in state.players_in(room):
		_add_figure(_make_lumberjack(p, false, false), room, slot)
		slot += 1
	if viewer and not viewer.alive and viewer.room == room:
		_add_figure(_make_lumberjack(viewer, false, true), room, slot)
		slot += 1
	for body in state.bodies_in(room):
		_add_figure(_make_lumberjack(state.players[body["victim"]], true, false), room, slot)
		slot += 1


func _add_figure(figure: Node3D, room: String, slot: int) -> void:
	var center: Vector2 = MapData.ROOMS[room]
	var offset: Vector2 = SLOTS[slot % SLOTS.size()]
	figure.position = Vector3(center.x + offset.x, 0.2, center.y + offset.y)
	add_child(figure)
	_figures.append(figure)


func _has_open_task(p: GameState.Player, room: String) -> bool:
	for task in p.tasks:
		if task["room"] == room and not task["done"]:
			return true
	return false


# --- Building the ship ---------------------------------------------------------

func _build_environment() -> void:
	var camera := Camera3D.new()
	camera.fov = 46
	camera.h_offset = -9.0  # Nudge the camp right, clear of the side panel.
	camera.v_offset = -1.5
	add_child(camera)
	camera.position = Vector3(0, 54, 19.5)  # Steep, almost top-down view.
	camera.look_at(Vector3.ZERO)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.70)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var grass_mesh := PlaneMesh.new()
	grass_mesh.size = Vector2(160, 110)
	add_child(_mesh_part(grass_mesh, _material(GRASS_COLOR), Vector3(0, -0.25, 0)))


## Pine trees scattered around the camp, never on a place or a path.
## Same seed every time, so the forest doesn't change between games.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var trunk_material := _material(Color(0.40, 0.26, 0.14))
	var needle_materials := [_material(Color(0.10, 0.30, 0.14)), _material(Color(0.14, 0.38, 0.16)), _material(Color(0.08, 0.25, 0.12))]
	var placed := 0
	while placed < TREE_COUNT:
		var spot := Vector2(rng.randf_range(-44, 44), rng.randf_range(-30, 30))
		if not _clear_of_camp(spot):
			continue
		placed += 1
		var tree := Node3D.new()
		var size := rng.randf_range(0.8, 1.4)
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.25
		trunk_mesh.bottom_radius = 0.3
		trunk_mesh.height = 1.0
		tree.add_child(_mesh_part(trunk_mesh, trunk_material, Vector3(0, 0.5, 0)))
		for layer in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.5 - layer * 0.4
			cone.height = 1.6
			tree.add_child(_mesh_part(cone, needle_materials[rng.randi() % needle_materials.size()], Vector3(0, 1.5 + layer * 0.9, 0)))
		tree.scale = Vector3.ONE * size
		tree.position = Vector3(spot.x, -0.2, spot.y)
		add_child(tree)


func _clear_of_camp(spot: Vector2) -> bool:
	var keep_out := MapData.ROOM_SIZE / 2.0 + 1.8
	for room in MapData.ROOMS:
		var center: Vector2 = MapData.ROOMS[room]
		if absf(spot.x - center.x) < keep_out and absf(spot.y - center.y) < keep_out:
			return false
	for hall in MapData.HALLS:
		var a: Vector2 = MapData.ROOMS[hall[0]]
		var b: Vector2 = MapData.ROOMS[hall[1]]
		var t := clampf((spot - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if spot.distance_to(a + (b - a) * t) < 3.0:
			return false
	return true


func _build_room(room: String) -> void:
	var pos: Vector2 = MapData.ROOMS[room]
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOR
	_room_materials[room] = material
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(MapData.ROOM_SIZE, 0.4, MapData.ROOM_SIZE)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = material
	floor_node.position = Vector3(pos.x, 0, pos.y)
	add_child(floor_node)

	var label := _make_label(room, 46, Color.WHITE)
	label.pixel_size = 0.025
	label.position = Vector3(pos.x, 0.5, pos.y - 4.3)
	add_child(label)

	var mark := _make_label("!", 110, Color(1.0, 0.85, 0.1))
	mark.position = Vector3(pos.x + 4.4, 1.0, pos.y - 3.0)
	mark.visible = false
	add_child(mark)
	_task_marks[room] = mark

	var vent := Node3D.new()
	if not MapData.vent_exits(room).is_empty():
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.5
		log_mesh.bottom_radius = 0.5
		log_mesh.height = 2.0
		var hollow_log := _mesh_part(log_mesh, _material(Color(0.36, 0.24, 0.13)), Vector3(0, 0.3, 0))
		hollow_log.rotation_degrees.z = 90
		vent.add_child(hollow_log)
		var hole_mesh := CylinderMesh.new()
		hole_mesh.top_radius = 0.33
		hole_mesh.bottom_radius = 0.33
		hole_mesh.height = 0.05
		var hole := _mesh_part(hole_mesh, _material(Color(0.05, 0.03, 0.02)), Vector3(1.0, 0.3, 0))
		hole.rotation_degrees.z = 90
		vent.add_child(hole)
		var vent_label := _make_label("hollow log", 30, Color(1, 0.45, 0.4))
		vent_label.position.y = 0.6
		vent.add_child(vent_label)
	vent.position = Vector3(pos.x - 3.4, 0.2, pos.y - 3.2)
	vent.visible = false
	add_child(vent)
	_vent_marks[room] = vent

	# Click target covering the room.
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MapData.ROOM_SIZE, 1.0, MapData.ROOM_SIZE)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(pos.x, 0, pos.y)
	area.input_event.connect(_on_room_input.bind(room))
	add_child(area)


func _build_hall(a: String, b: String) -> void:
	var from: Vector2 = MapData.ROOMS[a]
	var to: Vector2 = MapData.ROOMS[b]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 0.3, from.distance_to(to))
	var hall := MeshInstance3D.new()
	hall.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = HALL_COLOR
	hall.material_override = material
	var mid := (from + to) / 2.0
	hall.position = Vector3(mid.x, -0.05, mid.y)
	hall.rotation.y = atan2(to.x - from.x, to.y - from.y)
	add_child(hall)


func _make_lumberjack(p: GameState.Player, dead: bool, ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()  # Lets a body lie down without moving its name tag.
	root.add_child(pivot)
	var shirt := _material(p.color.darkened(0.35) if dead else p.color)
	var skin := _material(SKIN_COLOR)
	var beard := _material(BEARD_COLOR)
	var handle := _material(HANDLE_COLOR)
	var blade := _material(BLADE_COLOR)
	if ghost:
		for m in [shirt, skin, beard, handle, blade]:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35

	var body_mesh := CapsuleMesh.new()  # Shirt in the player's color.
	body_mesh.radius = 0.5
	body_mesh.height = 1.4
	pivot.add_child(_mesh_part(body_mesh, shirt, Vector3(0, 0.7, 0)))

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.36
	head_mesh.height = 0.72
	pivot.add_child(_mesh_part(head_mesh, skin, Vector3(0, 1.62, 0)))

	var beard_mesh := BoxMesh.new()
	beard_mesh.size = Vector3(0.5, 0.3, 0.2)
	pivot.add_child(_mesh_part(beard_mesh, beard, Vector3(0, 1.45, 0.25)))

	var hat_mesh := SphereMesh.new()  # Beanie, a shade darker than the shirt.
	hat_mesh.radius = 0.38
	hat_mesh.height = 0.5
	hat_mesh.is_hemisphere = true
	var hat_material := _material(p.color.darkened(0.25))
	if ghost:
		hat_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hat_material.albedo_color.a = 0.35
	pivot.add_child(_mesh_part(hat_mesh, hat_material, Vector3(0, 1.78, 0)))

	# The axe, held at the right side, blade up.
	var axe := Node3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.06
	handle_mesh.bottom_radius = 0.06
	handle_mesh.height = 1.5
	axe.add_child(_mesh_part(handle_mesh, handle, Vector3.ZERO))
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.5, 0.4, 0.08)
	axe.add_child(_mesh_part(blade_mesh, blade, Vector3(0.25, 0.55, 0)))
	axe.position = Vector3(0.7, 1.0, 0.2)
	axe.rotation_degrees.z = -15
	pivot.add_child(axe)

	if dead:
		pivot.rotation_degrees.x = -90
		pivot.position = Vector3(0, 0.5, 0.6)
	var tag := _make_label(p.name + (" (dead)" if dead else ""), 40, p.color.lightened(0.35))
	tag.pixel_size = 0.02
	tag.position.y = 1.4 if dead else 2.5
	root.add_child(tag)
	return root


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _mesh_part(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	return part


func _make_label(text: String, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.015
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	return label


func _on_room_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int, room: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and _clickable.has(room):
		room_clicked.emit(room)
