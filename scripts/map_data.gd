class_name MapData
extends RefCounted
## The ship: which rooms exist, where they sit on the board, and which halls
## connect them. Change the map here — the board and the bots read it all.

const ROOM_SIZE := 9.5
const START_ROOM := "Cafeteria"
const EMERGENCY_ROOM := "Cafeteria"

## Room name -> board position (x, z). The board is centered on the origin.
const ROOMS := {
	"Cafeteria": Vector2(0, -12),
	"Weapons": Vector2(14, -12),
	"Navigation": Vector2(24, 0),
	"Shields": Vector2(14, 12),
	"Storage": Vector2(0, 12),
	"Electrical": Vector2(-14, 12),
	"Engine": Vector2(-24, 0),
	"Medbay": Vector2(-14, -12),
}

## The task you do in each room.
const ROOM_TASKS := {
	"Cafeteria": "Empty the garbage",
	"Weapons": "Clear asteroids",
	"Navigation": "Chart the course",
	"Shields": "Prime the shields",
	"Storage": "Fuel the cans",
	"Electrical": "Fix the wiring",
	"Engine": "Align the engine",
	"Medbay": "Submit a scan",
}

## Halls between rooms. A ring around the ship plus one shortcut down the middle.
const HALLS := [
	["Cafeteria", "Weapons"], ["Weapons", "Navigation"], ["Navigation", "Shields"],
	["Shields", "Storage"], ["Storage", "Electrical"], ["Electrical", "Engine"],
	["Engine", "Medbay"], ["Medbay", "Cafeteria"], ["Cafeteria", "Storage"],
]

## Vents: secret tunnels only the impostor can use, as their move for the turn.
const VENTS := [["Medbay", "Electrical"], ["Weapons", "Shields"], ["Engine", "Navigation"]]


static func room_names() -> Array[String]:
	var names: Array[String] = []
	for room in ROOMS:
		names.append(room)
	return names


static func neighbors(room: String) -> Array[String]:
	var out: Array[String] = []
	for hall in HALLS:
		if hall[0] == room:
			out.append(hall[1])
		elif hall[1] == room:
			out.append(hall[0])
	return out


static func vent_exits(room: String) -> Array[String]:
	var out: Array[String] = []
	for vent in VENTS:
		if vent[0] == room:
			out.append(vent[1])
		elif vent[1] == room:
			out.append(vent[0])
	return out


## Number of moves from `room` to every other room.
static func distances_from(room: String) -> Dictionary:
	var dist := {room: 0}
	var queue: Array[String] = [room]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next in neighbors(current):
			if not dist.has(next):
				dist[next] = dist[current] + 1
				queue.append(next)
	return dist


## The room next to `from` that is one step closer to `to` (or `from` if already there).
static func next_step(from: String, to: String) -> String:
	var dist := distances_from(to)
	var best := from
	for next in neighbors(from):
		if dist[next] < dist[best]:
			best = next
	return best
