class_name BotBrain
extends RefCounted
## How the computer players think.
## Crewmate bots walk to their tasks, report bodies, and remember who they saw.
## The impostor bot wanders, kills anyone it finds alone, and lies in meetings.
## The Sheriff bot is a crew bot that shoots its top suspect when it finds them.

const VOTE_THRESHOLD := 4.0  ## A crew bot votes for someone only if they're at least this suspicious.
const CERTAIN := 100.0  ## Suspicion for "I saw them do it".
const SHOOT_THRESHOLD := 2.0  ## The Sheriff bot shoots anyone at least this suspicious.


static func take_turn(s: GameState, p: GameState.Player) -> void:
	if p.impostor:
		_impostor_turn(s, p)
	elif _try_shoot(s, p):
		return
	else:
		_crew_turn(s, p)


## Sheriff only: shoot the top suspect if they're in the room and suspicious enough.
static func _try_shoot(s: GameState, p: GameState.Player) -> bool:
	if not s.can_shoot(p):
		return false
	var suspect := _top_suspect(s, p)
	if suspect < 0 or p.suspicion[suspect] < SHOOT_THRESHOLD:
		return false
	var target := s.players[suspect]
	if not target.alive or target.room != p.room:
		return false
	s.shoot(p, target)
	return true


static func _crew_turn(s: GameState, p: GameState.Player) -> void:
	if p.alive and not s.bodies_in(p.room).is_empty():
		s.call_meeting(p, "report")
		return
	# Sure who did it? Head to the emergency button.
	if p.alive and not p.used_emergency and _top_suspect_score(s, p) >= CERTAIN:
		if p.room == MapData.EMERGENCY_ROOM:
			s.call_meeting(p, "emergency")
			return
		_move_and_check(s, p, MapData.next_step(p.room, MapData.EMERGENCY_ROOM))
		return
	var target := _nearest_task_room(p)
	# A Sheriff with a suspect goes hunting where it last saw them.
	var hunt := _sheriff_hunt_room(s, p)
	if hunt != "" and hunt != p.room:
		_move_and_check(s, p, MapData.next_step(p.room, hunt))
		return
	if target == p.room:
		s.do_task(p)
	elif target != "":
		_move_and_check(s, p, MapData.next_step(p.room, target))
	else:
		_move_and_check(s, p, _random_move(s, p.room))


static func _sheriff_hunt_room(s: GameState, p: GameState.Player) -> String:
	if not s.can_shoot(p):
		return ""
	var suspect := _top_suspect(s, p)
	if suspect < 0 or p.suspicion[suspect] < SHOOT_THRESHOLD or not p.last_seen.has(suspect):
		return ""
	return p.last_seen[suspect]["room"]


static func _move_and_check(s: GameState, p: GameState.Player, room: String) -> void:
	s.move(p, room)
	if _try_shoot(s, p):
		return
	if p.alive and not s.bodies_in(p.room).is_empty():
		s.call_meeting(p, "report")
	elif p.alive and p.room == MapData.EMERGENCY_ROOM and not p.used_emergency \
			and _top_suspect_score(s, p) >= CERTAIN:
		s.call_meeting(p, "emergency")


static func _impostor_turn(s: GameState, p: GameState.Player) -> void:
	if not p.alive:
		return  # A shot impostor's ghost just haunts quietly.
	var victim := _lone_victim(s, p)
	if victim:
		s.kill(p, victim)
		return
	# Waiting for the kill cooldown? Sometimes stand still and "do a task" to blend in.
	var near_body := not s.bodies_in(p.room).is_empty()
	if not near_body and p.kill_cooldown > 0 and s.has_task_here(p) and s.rng.randf() < 0.5:
		s.do_task(p)
		return
	s.move(p, _impostor_destination(s, p))
	victim = _lone_victim(s, p)
	if victim:
		s.kill(p, victim)


## Hunt: jump to a room (by hall or vent) where exactly one crewmate is standing.
## The impostor bot cheats a little here — it "senses" lone crewmates — because
## a bot that only remembers what it saw almost never finds anyone alone.
static func _impostor_destination(s: GameState, p: GameState.Player) -> String:
	var options := s.legal_moves(p)
	options.erase(p.room)
	if p.kill_cooldown == 0:
		var hunting: Array[String] = []
		for room in options:
			if s.players_in(room).size() == 1:
				hunting.append(room)
		if not hunting.is_empty():
			return hunting[s.rng.randi_range(0, hunting.size() - 1)]
	return options[s.rng.randi_range(0, options.size() - 1)]


## The only other living player in the room, if the impostor can kill right now.
static func _lone_victim(s: GameState, p: GameState.Player) -> GameState.Player:
	if p.kill_cooldown > 0:
		return null
	var here := s.players_in(p.room)
	if here.size() == 2:
		return here[0] if here[1] == p else here[1]
	return null


static func _nearest_task_room(p: GameState.Player) -> String:
	var dist := MapData.distances_from(p.room)
	var best := ""
	for task in p.tasks:
		if not task["done"] and (best == "" or dist[task["room"]] < dist[best]):
			best = task["room"]
	return best


static func _random_move(s: GameState, room: String) -> String:
	var options := MapData.neighbors(room)
	return options[s.rng.randi_range(0, options.size() - 1)]


# --- Meetings ------------------------------------------------------------------

## Updates every bot's suspicions, makes the bots' statements, and returns them.
## Each statement: {speaker, text, accuses (-1 = nobody), strength}.
static func on_meeting(s: GameState) -> Array[Dictionary]:
	var meeting := s.pending_meeting
	# 1. Crew bots think about what they saw.
	for p in s.players:
		if p.human or not p.alive or p.impostor:
			continue
		for k in p.saw_kills:
			_suspect(p, k["killer"], CERTAIN)
		for body in meeting["bodies"]:
			for id in p.last_seen:
				var seen: Dictionary = p.last_seen[id]
				if seen["room"] == body["room"] and body["round"] - seen["round"] <= GameState.MEMORY_ROUNDS \
						and seen["round"] <= body["round"] and s.players[id].alive:
					_suspect(p, id, 2.0)
	# 2. Every living bot says something.
	var statements: Array[Dictionary] = []
	for p in s.players:
		if not p.human and p.alive:
			statements.append(_impostor_statement(s, p) if p.impostor else _crew_statement(s, p))
	# 3. Crew bots listen. If someone accuses YOU, you know they're lying.
	for st in statements:
		if st["accuses"] < 0:
			continue
		for p in s.players:
			if p.human or not p.alive or p.impostor or p.id == st["speaker"]:
				continue
			if st["accuses"] == p.id:
				_suspect(p, st["speaker"], 3.0)
			else:
				_suspect(p, st["accuses"], st["strength"])
	meeting["statements"] = statements
	return statements


static func _crew_statement(s: GameState, p: GameState.Player) -> Dictionary:
	if not p.saw_kills.is_empty():
		var k: Dictionary = p.saw_kills[-1]
		return _say(p, "I SAW %s kill %s in %s!" % [s.players[k["killer"]].name, s.players[k["victim"]].name, k["room"]], k["killer"], CERTAIN)
	var suspect := _top_suspect(s, p)
	if suspect >= 0 and p.suspicion[suspect] >= VOTE_THRESHOLD:
		var seen: Dictionary = p.last_seen.get(suspect, {"room": "somewhere", "round": 0})
		return _say(p, "%s was in %s in round %d, near the body. Sus!" % [s.players[suspect].name, seen["room"], seen["round"]], suspect, 2.0)
	return _say(p, "I was doing chores at %s. I didn't see anything weird." % p.room, -1, 0.0)


## The impostor sometimes blames someone, otherwise acts innocent.
static func _impostor_statement(s: GameState, p: GameState.Player) -> Dictionary:
	var crew: Array[GameState.Player] = []
	for other in s.players:
		if other.alive and other != p:
			crew.append(other)
	if not crew.is_empty() and s.rng.randf() < 0.45:
		var target := crew[s.rng.randi_range(0, crew.size() - 1)]
		var room: String = s.pending_meeting["room"]
		return _say(p, "I saw %s hanging around %s. Sus!" % [target.name, room], target.id, 2.0)
	var rooms := MapData.room_names()
	return _say(p, "I was doing chores at %s. I didn't see anything weird." % rooms[s.rng.randi_range(0, rooms.size() - 1)], -1, 0.0)


static func vote(s: GameState, p: GameState.Player) -> int:
	if p.impostor:
		# Go along with the crowd: vote for whoever the bots blamed most.
		var blamed := {}
		for st in s.pending_meeting["statements"]:
			var target: int = st["accuses"]
			if target >= 0 and target != p.id and s.players[target].alive:
				blamed[target] = blamed.get(target, 0.0) + st["strength"]
		var best := -1
		for target in blamed:
			if best < 0 or blamed[target] > blamed[best]:
				best = target
		return best
	var suspect := _top_suspect(s, p)
	if suspect >= 0 and p.suspicion[suspect] >= VOTE_THRESHOLD:
		return suspect
	return -1


static func _top_suspect(s: GameState, p: GameState.Player) -> int:
	var best := -1
	for id in p.suspicion:
		if id != p.id and s.players[id].alive and (best < 0 or p.suspicion[id] > p.suspicion[best]):
			best = id
	return best


static func _top_suspect_score(s: GameState, p: GameState.Player) -> float:
	var best := _top_suspect(s, p)
	return p.suspicion[best] if best >= 0 else 0.0


static func _suspect(p: GameState.Player, id: int, amount: float) -> void:
	p.suspicion[id] = p.suspicion.get(id, 0.0) + amount


static func _say(p: GameState.Player, text: String, accuses: int, strength: float) -> Dictionary:
	return {"speaker": p.id, "text": text, "accuses": accuses, "strength": strength}
