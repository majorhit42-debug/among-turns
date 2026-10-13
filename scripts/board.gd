class_name Board
extends Node3D
## Draws the ship in 3D: rooms, halls, crewmates and bodies. It only shows what
## the current viewer is allowed to see — the people and bodies in their own room.

signal room_clicked(room: String)

const FLOOR_COLOR := Color(0.30, 0.34, 0.42)
const HALL_COLOR := Color(0.20, 0.23, 0.29)
const MOVE_COLOR := Color(0.28, 0.58, 0.40)  ## Rooms you can walk to this turn.
const HERE_COLOR := Color(0.66, 0.58, 0.26)  ## The room you're standing in.
const VISOR_COLOR := Color(0.62, 0.86, 0.96)

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
		_add_figure(_make_crewmate(p, false, false), room, slot)
		slot += 1
	if viewer and not viewer.alive and viewer.room == room:
		_add_figure(_make_crewmate(viewer, false, true), room, slot)
		slot += 1
	for body in state.bodies_in(room):
		_add_figure(_make_crewmate(state.players[body["victim"]], true, false), room, slot)
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
	camera.h_offset = -9.0  # Nudge the ship right, clear of the side panel.
	camera.v_offset = -1.5
	add_child(camera)
	camera.position = Vector3(0, 54, 19.5)  # Steep, almost top-down view.
	camera.look_at(Vector3.ZERO)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.68, 0.80)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


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

	var label := _make_label(room, 56, Color.WHITE)
	label.pixel_size = 0.025
	label.position = Vector3(pos.x, 0.5, pos.y - 4.3)
	add_child(label)

	var mark := _make_label("!", 110, Color(1.0, 0.85, 0.1))
	mark.position = Vector3(pos.x + 3.9, 1.0, pos.y - 3.6)
	mark.visible = false
	add_child(mark)
	_task_marks[room] = mark

	var vent := Node3D.new()
	if not MapData.vent_exits(room).is_empty():
		var grate_mesh := BoxMesh.new()
		grate_mesh.size = Vector3(1.4, 0.1, 1.0)
		var grate := MeshInstance3D.new()
		grate.mesh = grate_mesh
		var grate_material := StandardMaterial3D.new()
		grate_material.albedo_color = Color(0.08, 0.08, 0.1)
		grate.material_override = grate_material
		vent.add_child(grate)
		var vent_label := _make_label("vent", 36, Color(1, 0.4, 0.4))
		vent_label.position.y = 0.6
		vent.add_child(vent_label)
	vent.position = Vector3(pos.x - 3.7, 0.25, pos.y - 3.4)
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


func _make_crewmate(p: GameState.Player, dead: bool, ghost: bool) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()  # Lets a body lie down without moving its name tag.
	root.add_child(pivot)
	var material := StandardMaterial3D.new()
	material.albedo_color = p.color.darkened(0.35) if dead else p.color
	if ghost:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.35

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.55
	body_mesh.height = 1.6
	pivot.add_child(_mesh_part(body_mesh, material, Vector3(0, 0.8, 0)))

	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.7, 0.8, 0.35)
	pivot.add_child(_mesh_part(pack_mesh, material, Vector3(0, 0.75, -0.55)))

	var visor_mesh := CapsuleMesh.new()
	visor_mesh.radius = 0.2
	visor_mesh.height = 0.8
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = VISOR_COLOR
	visor_material.roughness = 0.15
	var visor := _mesh_part(visor_mesh, visor_material, Vector3(0, 1.1, 0.42))
	visor.rotation_degrees.z = 90
	pivot.add_child(visor)

	if dead:
		pivot.rotation_degrees.x = -90
		pivot.position = Vector3(0, 0.55, 0.6)
	var tag := _make_label(p.name + (" (dead)" if dead else ""), 40, p.color.lightened(0.35))
	tag.pixel_size = 0.02
	tag.position.y = 1.4 if dead else 2.3
	root.add_child(tag)
	return root


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
