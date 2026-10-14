class_name MapData
extends RefCounted
## The lumber camp: which places exist, where they sit on the board, and which halls
## connect them. Change the map here — the board and the bots read it all.

const ROOM_SIZE := 9.5
const START_ROOM := "Mess Hall"
const EMERGENCY_ROOM := "Mess Hall"

## Room name -> board position (x, z). The board is centered on the origin.
const ROOMS := {
	"Mess Hall": Vector2(0, -12),
	"Tool Shed": Vector2(14, -12),
	"Lookout Tower": Vector2(24, 0),
	"Sawmill": Vector2(14, 12),
	"Log Yard": Vector2(0, 12),
	"Generator": Vector2(-14, 12),
	"Bunkhouse": Vector2(-24, 0),
	"Ranger Station": Vector2(-14, -12),
}

## The chore you do in each place.
const ROOM_TASKS := {
	"Mess Hall": "Wash the dishes",
	"Tool Shed": "Sharpen the axes",
	"Lookout Tower": "Watch for fires",
	"Sawmill": "Saw the planks",
	"Log Yard": "Stack the logs",
	"Generator": "Refuel the generator",
	"Bunkhouse": "Make the bunks",
	"Ranger Station": "Fix the radio",
}

## Dirt paths between places. A ring around the camp plus one shortcut down the middle.
const HALLS := [
	["Mess Hall", "Tool Shed"], ["Tool Shed", "Lookout Tower"], ["Lookout Tower", "Sawmill"],
	["Sawmill", "Log Yard"], ["Log Yard", "Generator"], ["Generator", "Bunkhouse"],
	["Bunkhouse", "Ranger Station"], ["Ranger Station", "Mess Hall"], ["Mess Hall", "Log Yard"],
]

## Hollow logs: secret tunnels only the impostor can crawl through, as their move for the turn.
## (In code they are still called "vents".)
const VENTS := [["Ranger Station", "Generator"], ["Tool Shed", "Sawmill"], ["Bunkhouse", "Lookout Tower"]]


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
