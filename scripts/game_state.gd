class_name GameState
extends RefCounted
## All the rules of the game, with no graphics. main.gd draws it and asks humans
## what to do; bot_brain.gd makes the choices for computer players.
##
## A round = every player takes one turn, in seat order. On a turn you move to a
## room next door (or stay), then do one thing: a task (only if you stayed put),
## a kill (impostor), report a body, or call an emergency meeting.

const PLAYER_COUNT := 8
const TASKS_PER_PLAYER := 6
const KILL_COOLDOWN := 1  ## Rounds the impostor must wait after a kill.
const MEMORY_ROUNDS := 2  ## A sighting this many rounds before a murder counts as "near the body".
const MAX_NOTES := 30

const COLOR_NAMES := ["Red", "Blue", "Green", "Yellow", "Orange", "Purple", "Cyan", "Pink"]
const COLORS := [
	Color(0.77, 0.07, 0.07), Color(0.10, 0.25, 0.90), Color(0.07, 0.55, 0.18), Color(0.96, 0.96, 0.34),
	Color(0.94, 0.49, 0.05), Color(0.50, 0.22, 0.80), Color(0.22, 1.0, 0.86), Color(0.93, 0.33, 0.73),
]


class Player:
	var id := 0
	var name := ""
	var color := Color.WHITE
	var human := false
	var impostor := false
	var alive := true
	var ejected := false
	var room := MapData.START_ROOM
	var tasks: Array[Dictionary] = []  ## {room, done}. The impostor's are fake.
	var used_emergency := false
	var kill_cooldown := 0
	var killed_by := -1
	var notes: Array[String] = []  ## What this player has seen, newest last.
	var last_seen := {}  ## player id -> {room, round}
	var saw_kills: Array[Dictionary] = []  ## Kills witnessed since the last meeting.
	var suspicion := {}  ## Bots only: player id -> how suspicious that player seems.

	func tasks_left() -> int:
		var left := 0
		for task in tasks:
			if not task["done"]:
				left += 1
		return left


var players: Array[Player] = []
var bodies: Array[Dictionary] = []  ## {victim, killer, room, round}
var newly_dead: Array[int] = []  ## Died since the last meeting.
var round_num := 1
var turn_index := 0  ## Whose turn it is (index into players).
var moved_this_turn := false
var winner := ""  ## "", "crew" or "impostor"
var win_reason := ""
var pending_meeting := {}  ## Set when someone reports or calls a meeting.
var rng := RandomNumberGenerator.new()


## Seats 0..num_humans-1 are humans, the rest are bots. Anyone can be the impostor.
func setup(num_humans: int, seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	players.clear()
	bodies.clear()
	newly_dead.clear()
	round_num = 1
	turn_index = 0
	winner = ""
	win_reason = ""
	pending_meeting = {}
	var impostor_seat := rng.randi_range(0, PLAYER_COUNT - 1)
	for i in PLAYER_COUNT:
		var p := Player.new()
		p.id = i
		p.name = COLOR_NAMES[i]
		p.color = COLORS[i]
		p.human = i < num_humans
		p.impostor = i == impostor_seat
		p.kill_cooldown = 1  # No kills in round 1.
		var rooms := _shuffled(MapData.room_names())
		for t in TASKS_PER_PLAYER:
			p.tasks.append({"room": rooms[t], "done": false})
		players.append(p)


# --- Turns -------------------------------------------------------------------

func current_player() -> Player:
	return players[turn_index]


func begin_turn() -> void:
	moved_this_turn = false
	observe(current_player())


func end_turn() -> void:
	if winner != "" or not pending_meeting.is_empty():
		return  # The meeting (or game over) decides what happens next.
	turn_index += 1
	if turn_index >= players.size():
		round_num += 1
		turn_index = 0
		for p in players:
			if p.impostor and p.kill_cooldown > 0:
				p.kill_cooldown -= 1


func legal_moves(p: Player) -> Array[String]:
	var moves: Array[String] = [p.room]
	moves.append_array(MapData.neighbors(p.room))
	if p.impostor and p.alive:
		for room in MapData.vent_exits(p.room):
			if not moves.has(room):
				moves.append(room)
	return moves


func move(p: Player, room: String) -> void:
	if room == p.room:
		return
	p.room = room
	moved_this_turn = true
	observe(p)


## Records who `p` can see right now into their memory and notes.
func observe(p: Player) -> void:
	if not p.alive:
		return
	var seen: Array[String] = []
	for other in players_in(p.room):
		if other != p:
			p.last_seen[other.id] = {"room": p.room, "round": round_num}
			seen.append(other.name)
	var text := "R%d %s: %s" % [round_num, p.room, ", ".join(seen) if not seen.is_empty() else "nobody"]
	for body in bodies_in(p.room):
		text += " — BODY of %s!" % players[body["victim"]].name
	add_note(p, text)


func add_note(p: Player, text: String) -> void:
	p.notes.append(text)
	if p.notes.size() > MAX_NOTES:
		p.notes.pop_front()


# --- Looking around ------------------------------------------------------------

## Living players in a room.
func players_in(room: String) -> Array[Player]:
	var out: Array[Player] = []
	for p in players:
		if p.alive and p.room == room:
			out.append(p)
	return out


func bodies_in(room: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for body in bodies:
		if body["room"] == room:
			out.append(body)
	return out


func has_task_here(p: Player) -> bool:
	for task in p.tasks:
		if task["room"] == p.room and not task["done"]:
			return true
	return false


func impostor() -> Player:
	for p in players:
		if p.impostor:
			return p
	return null


## x = crew tasks done, y = crew tasks total. Ghost crewmates' tasks still count.
func task_progress() -> Vector2i:
	var done := 0
	var total := 0
	for p in players:
		if p.impostor:
			continue
		total += p.tasks.size()
		done += p.tasks.size() - p.tasks_left()
	return Vector2i(done, total)


# --- Actions -------------------------------------------------------------------

## What `p` can do after moving. Each entry: {type, label, target?}.
func actions_for(p: Player) -> Array[Dictionary]:
	var acts: Array[Dictionary] = []
	if not moved_this_turn and has_task_here(p):
		var task_name: String = MapData.ROOM_TASKS[p.room]
		acts.append({"type": "task", "label": ("Fake task: " if p.impostor else "Task: ") + task_name})
	if not p.alive:
		return acts  # Ghosts can only do tasks.
	if not bodies_in(p.room).is_empty():
		acts.append({"type": "report", "label": "REPORT BODY"})
	if p.impostor and p.kill_cooldown == 0:
		for other in players_in(p.room):
			if other != p:
				acts.append({"type": "kill", "target": other.id, "label": "KILL " + other.name})
	if p.room == MapData.EMERGENCY_ROOM and not p.used_emergency:
		acts.append({"type": "emergency", "label": "Emergency meeting"})
	return acts


func perform(p: Player, act: Dictionary) -> void:
	match act["type"]:
		"task":
			do_task(p)
		"kill":
			kill(p, players[act["target"]])
		"report":
			call_meeting(p, "report")
		"emergency":
			call_meeting(p, "emergency")


func do_task(p: Player) -> void:
	for task in p.tasks:
		if task["room"] == p.room and not task["done"]:
			task["done"] = true
			add_note(p, "R%d %s: did a task" % [round_num, p.room])
			break
	check_win()


func kill(killer: Player, victim: Player) -> void:
	victim.alive = false
	victim.killed_by = killer.id
	bodies.append({"victim": victim.id, "killer": killer.id, "room": killer.room, "round": round_num})
	newly_dead.append(victim.id)
	killer.kill_cooldown = KILL_COOLDOWN
	for witness in players_in(killer.room):
		if witness != killer:
			witness.saw_kills.append({"killer": killer.id, "victim": victim.id, "room": killer.room, "round": round_num})
			add_note(witness, "R%d %s: SAW %s KILL %s!!" % [round_num, killer.room, killer.name, victim.name])
	check_win()


## Starts a meeting. Every body on the ship is found and cleaned up.
func call_meeting(caller: Player, kind: String) -> void:
	var reported := -1
	if kind == "report":
		reported = bodies_in(caller.room)[0]["victim"]
	else:
		caller.used_emergency = true
	pending_meeting = {
		"caller": caller.id,
		"kind": kind,
		"room": caller.room,
		"reported": reported,
		"bodies": bodies.duplicate(true),
		"dead": newly_dead.duplicate(),
		"statements": [],
	}
	bodies.clear()


## votes: voter id -> target id (-1 = skip). Returns {tally, ejected, was_impostor}.
## The most votes gets ejected; a tie, or skip winning, ejects nobody.
func resolve_votes(votes: Dictionary) -> Dictionary:
	var tally := {}
	for voter in votes:
		var target: int = votes[voter]
		tally[target] = tally.get(target, 0) + 1
	var ejected := -1
	var best_count: int = tally.get(-1, 0)
	var tie := false
	for target in tally:
		if target == -1:
			continue
		if tally[target] > best_count:
			ejected = target
			best_count = tally[target]
			tie = false
		elif tally[target] == best_count:
			tie = true
	if tie:
		ejected = -1
	var was_impostor := false
	if ejected >= 0:
		var p := players[ejected]
		p.alive = false
		p.ejected = true
		was_impostor = p.impostor
	check_win()
	return {"tally": tally, "ejected": ejected, "was_impostor": was_impostor}


## After the vote: everyone still alive goes back to the Cafeteria and a new round starts.
func end_meeting() -> void:
	pending_meeting = {}
	newly_dead.clear()
	round_num += 1
	turn_index = 0
	for p in players:
		p.saw_kills.clear()
		if p.alive:
			p.room = MapData.START_ROOM
			add_note(p, "R%d: meeting over, back to %s" % [round_num, MapData.START_ROOM])
		if p.impostor:
			p.kill_cooldown = maxi(p.kill_cooldown, 1)


func check_win() -> void:
	if winner != "":
		return
	var crew_alive := 0
	var impostors_alive := 0
	for p in players:
		if p.alive:
			if p.impostor:
				impostors_alive += 1
			else:
				crew_alive += 1
	var progress := task_progress()
	if impostors_alive == 0:
		winner = "crew"
		win_reason = "The impostor was voted out!"
	elif crew_alive <= impostors_alive:
		winner = "impostor"
		win_reason = "The impostor got everyone!"
	elif progress.x >= progress.y:
		winner = "crew"
		win_reason = "All tasks are done!"


func _shuffled(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp = out[i]
		out[i] = out[j]
		out[j] = temp
	return out
