extends Node3D
## Runs a game on one shared screen: setup → turns (with "pass the screen"
## breaks so nobody peeks) → meetings and secret votes → game over.
## The rules live in GameState and the bots in BotBrain; this script only shows
## things and collects the humans' choices.

const CREW_COLOR := Color(0.45, 0.9, 1.0)
const IMPOSTOR_COLOR := Color(1.0, 0.3, 0.3)
const SHERIFF_COLOR := Color(1.0, 0.8, 0.25)
const DIM_COLOR := Color(0.7, 0.75, 0.85)

var state := GameState.new()
var num_humans := 2
var board: Board

var _top_bar: Control
var _side_panel: Control
var _bottom_panel: Control
var _top_label: Label
var _task_bar: ProgressBar
var _task_count: Label
var _role_label: Label
var _tasks_label: Label
var _notes_label: Label
var _prompt_label: Label
var _buttons: HFlowContainer
var _overlay: ColorRect
var _overlay_box: VBoxContainer

var _player: GameState.Player  ## The human whose turn it is.
var _phase := ""  ## "move" while a human is picking where to go.
var _told_role := {}  ## player id -> true once they've seen their secret role.
var _told_dead := {}  ## player id -> true once they've been told they're a ghost.
var _votes := {}
var _voters: Array[GameState.Player] = []


func _ready() -> void:
	get_viewport().physics_object_picking = true
	board = Board.new()
	add_child(board)
	board.room_clicked.connect(_on_room_clicked)
	_build_hud()
	_show_setup()


# --- Setup ---------------------------------------------------------------------

func _show_setup() -> void:
	_hud_visible(false)
	board.show_view(state, null, [])
	_overlay_open("AXE US", Color(1.0, 0.85, 0.55))
	_overlay_box.add_child(_label("Somebody at the lumber camp is not who they seem...", 18, DIM_COLOR, true))
	_overlay_box.add_child(_label("How many real players?", 24, Color.WHITE, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	var count := _label(str(num_humans), 44, Color.WHITE, true)
	count.custom_minimum_size.x = 80
	var info := _label("", 20, DIM_COLOR, true)
	var update := func() -> void:
		count.text = str(num_humans)
		var bots := GameState.PLAYER_COUNT - num_humans
		info.text = "%d real player%s + %d bot%s. One of you (maybe a bot!) is secretly the impostor." % [
			num_humans, "" if num_humans == 1 else "s", bots, "" if bots == 1 else "s"]
	row.add_child(_button("  −  ", func() -> void:
		num_humans = maxi(1, num_humans - 1)
		update.call()))
	row.add_child(count)
	row.add_child(_button("  +  ", func() -> void:
		num_humans = mini(GameState.PLAYER_COUNT, num_humans + 1)
		update.call()))
	_overlay_box.add_child(row)
	_overlay_box.add_child(info)
	update.call()
	_overlay_box.add_child(_label(
		"HOW TO PLAY\n"
		+ "• On your turn, walk to a place next door (or stay), then do one thing.\n"
		+ "• You only see who's at YOUR place. Remember what you saw!\n"
		+ "• Lumberjacks: stay in a place for a turn to do a chore there. Win by finishing all chores or voting out the impostor.\n"
		+ "• Impostor: catch someone alone and take them out. Crawl through hollow logs to sneak across camp. Don't get caught!\n"
		+ "• Sheriff: a lumberjack with 2 bullets. Shoot the impostor to win, but nobody finds out who was shot until 3 players are dead!\n"
		+ "• Find a body? Report it. Then everyone talks it over and votes in secret.", 18, Color.WHITE))
	_overlay_box.add_child(_button("Start game", _start_game))


func _start_game() -> void:
	state.setup(num_humans)
	_told_role.clear()
	_told_dead.clear()
	_overlay_close()
	_advance()


# --- Turn loop -----------------------------------------------------------------

## Plays bot turns until it's a human's turn, a meeting starts, or someone wins.
func _advance() -> void:
	while true:
		if state.winner != "":
			_show_game_over()
			return
		if not state.pending_meeting.is_empty():
			_start_meeting()
			return
		var p := state.current_player()
		state.begin_turn()
		if p.human:
			_hand_over(p)
			return
		BotBrain.take_turn(state, p)
		state.end_turn()


## "Pass the screen" break, so the next player's secrets stay secret.
func _hand_over(p: GameState.Player) -> void:
	_hud_visible(false)
	board.show_view(state, null, [])
	if num_humans == 1:
		_begin_human_turn(p)
		return
	_overlay_open("Pass the screen to %s" % p.name.to_upper(), p.color.lightened(0.2))
	_overlay_box.add_child(_label("Round %d. Everyone else, look away!" % state.round_num, 22, DIM_COLOR, true))
	_overlay_box.add_child(_button("I'm %s — start my turn" % p.name, _begin_human_turn.bind(p)))


func _begin_human_turn(p: GameState.Player) -> void:
	_player = p
	if not _told_role.has(p.id):
		_told_role[p.id] = true
		if p.impostor:
			_overlay_open("You are the IMPOSTOR", IMPOSTOR_COLOR)
			_overlay_box.add_child(_label("Take out lumberjacks when they're alone. You can crawl through hollow logs. Pretend to do chores, and lie in meetings! Watch out: one lumberjack is a secret Sheriff with a gun.", 20, Color.WHITE, true))
		elif p.sheriff:
			_overlay_open("You are the SHERIFF", SHERIFF_COLOR)
			_overlay_box.add_child(_label("You're a lumberjack, with %d bullets for the whole game. You only win if YOU shoot the impostor. Shoot the wrong person and an innocent lumberjack dies.\nYou won't find out if you got the impostor until %d players are dead. If you get killed, you lose." % [GameState.SHERIFF_BULLETS, GameState.SECRET_UNTIL_DEAD], 20, Color.WHITE, true))
		else:
			_overlay_open("You are a LUMBERJACK", CREW_COLOR)
			_overlay_box.add_child(_label("Do your chores (the yellow ! places) and watch who you see where. One of the others is the impostor...", 20, Color.WHITE, true))
		_overlay_box.add_child(_button("Got it", _begin_human_turn.bind(p)))
		return
	if not p.alive and not _told_dead.has(p.id):
		_told_dead[p.id] = true
		var how := "You were voted out of camp."
		if not p.ejected:
			var killer := state.players[p.killed_by]
			how = ("You were shot by %s, the Sheriff!" if killer.sheriff else "You were killed by %s!") % killer.name
		_overlay_open("You're a ghost now", DIM_COLOR)
		_overlay_box.add_child(_label(how + "\nGhosts can still do chores to help the camp, but you can't talk about who did it. Shh!", 20, Color.WHITE, true))
		_overlay_box.add_child(_button("OK", _begin_human_turn.bind(p)))
		return
	_overlay_close()
	_hud_visible(true)
	_show_move_phase()


func _show_move_phase() -> void:
	var p := _player
	_phase = "move"
	_refresh_hud()
	var moves := state.legal_moves(p)
	board.show_view(state, p, moves)
	var here := _who_is_here(p)
	_prompt_label.text = "%s Where do you go? Click a green place, or stay to do a chore here." % here
	_clear_buttons()
	_buttons.add_child(_button("Stay in %s" % p.room, _on_move.bind(p.room)))
	for room in moves:
		if room != p.room:
			var vent := not MapData.neighbors(p.room).has(room)
			_buttons.add_child(_button(("Crawl through the hollow log to %s" if vent else "Go to %s") % room, _on_move.bind(room)))


func _on_room_clicked(room: String) -> void:
	if _phase == "move" and state.legal_moves(_player).has(room):
		_on_move(room)


func _on_move(room: String) -> void:
	if _phase != "move":
		return
	_phase = "act"
	var p := _player
	state.move(p, room)
	_refresh_hud()
	board.show_view(state, p, [])
	var acts := state.actions_for(p)
	var text := _who_is_here(p)
	if p.impostor and state.players_in(p.room).size() > 2:
		text += " Careful: if you kill now, the others will see you!"
	_prompt_label.text = text + (" What do you do?" if not acts.is_empty() else " Nothing to do here.")
	_clear_buttons()
	for act in acts:
		var color := Color.WHITE
		if act["type"] in ["kill", "report"]:
			color = IMPOSTOR_COLOR
		elif act["type"] == "shoot":
			color = SHERIFF_COLOR
		_buttons.add_child(_button(act["label"], _on_action.bind(act), color))
	_buttons.add_child(_button("End turn", _end_human_turn))


func _on_action(act: Dictionary) -> void:
	state.perform(_player, act)
	_end_human_turn()


func _end_human_turn() -> void:
	_phase = ""
	state.end_turn()
	_advance()


func _who_is_here(p: GameState.Player) -> String:
	var names: Array[String] = []
	for other in state.players_in(p.room):
		if other != p:
			names.append(other.name)
	var text := "You're in %s. " % p.room
	text += "You see: %s." % ", ".join(names) if not names.is_empty() else "Nobody else is here."
	for body in state.bodies_in(p.room):
		text += " There's a BODY: %s!" % state.players[body["victim"]].name
	return text


# --- Meetings ------------------------------------------------------------------

func _start_meeting() -> void:
	var meeting := state.pending_meeting
	var statements := BotBrain.on_meeting(state)
	_hud_visible(false)
	board.show_view(state, null, [])
	var caller := state.players[meeting["caller"]]
	if meeting["kind"] == "report":
		_overlay_open("DEAD BODY REPORTED", IMPOSTOR_COLOR, Color(0.12, 0.0, 0.02, 0.95))
		_overlay_box.add_child(_label("%s found %s's body in %s." % [
			caller.name, state.players[meeting["reported"]].name, meeting["room"]], 22, Color.WHITE, true))
	else:
		_overlay_open("CAMP MEETING", IMPOSTOR_COLOR, Color(0.12, 0.0, 0.02, 0.95))
		_overlay_box.add_child(_label("%s rang the camp bell." % caller.name, 22, Color.WHITE, true))
	var dead: Array[String] = []
	for id in meeting["dead"]:
		dead.append(state.players[id].name)
	if not dead.is_empty():
		_overlay_box.add_child(_label("Found dead: %s" % ", ".join(dead), 20, DIM_COLOR, true))
	if not statements.is_empty():
		_overlay_box.add_child(_label("The bots say:", 20, DIM_COLOR))
		for st in statements:
			var speaker := state.players[st["speaker"]]
			_overlay_box.add_child(_label("%s: \"%s\"" % [speaker.name, st["text"]], 19, speaker.color.lightened(0.3)))
	if num_humans > 1:
		_overlay_box.add_child(_label("Now talk it over out loud! Who's acting sus?", 20, Color.WHITE, true))
	_overlay_box.add_child(_button("Start voting", _start_voting))


func _start_voting() -> void:
	_votes.clear()
	_voters.clear()
	for p in state.players:
		if p.alive:
			if p.human:
				_voters.append(p)
			else:
				_votes[p.id] = BotBrain.vote(state, p)
	_next_voter()


func _next_voter() -> void:
	if _voters.is_empty():
		_show_vote_result()
		return
	var voter: GameState.Player = _voters.pop_front()
	if _alive_humans() > 1:
		_overlay_open("Pass the screen to %s to vote" % voter.name.to_upper(), voter.color.lightened(0.2))
		_overlay_box.add_child(_label("Votes are secret. Everyone else, look away!", 20, DIM_COLOR, true))
		_overlay_box.add_child(_button("I'm %s — vote" % voter.name, _show_ballot.bind(voter)))
	else:
		_show_ballot(voter)


func _show_ballot(voter: GameState.Player) -> void:
	_overlay_open("%s, who is the impostor?" % voter.name, voter.color.lightened(0.2))
	if not voter.notes.is_empty():
		_overlay_box.add_child(_label("What you saw:\n" + "\n".join(voter.notes.slice(-5)), 16, DIM_COLOR))
	var grid := GridContainer.new()
	grid.columns = 4
	for p in state.players:
		if p.alive and p != voter:
			var choice := _button(p.name, _cast_vote.bind(voter, p.id), p.color.lightened(0.3))
			choice.custom_minimum_size.x = 170
			grid.add_child(choice)
	_overlay_box.add_child(grid)
	_overlay_box.add_child(_button("Skip vote", _cast_vote.bind(voter, -1)))


func _cast_vote(voter: GameState.Player, target: int) -> void:
	_votes[voter.id] = target
	_next_voter()


func _show_vote_result() -> void:
	var result := state.resolve_votes(_votes)
	var ejected: int = result["ejected"]
	if ejected >= 0:
		var p := state.players[ejected]
		_overlay_open("%s was voted out of camp." % p.name, p.color.lightened(0.2))
		_overlay_box.add_child(_label(
			"%s WAS the impostor!" % p.name if result["was_impostor"] else "%s was NOT the impostor." % p.name,
			26, IMPOSTOR_COLOR if result["was_impostor"] else Color.WHITE, true))
	else:
		_overlay_open("No one was voted out.", Color.WHITE)
	# Who voted for whom — another clue.
	var lines: Array[String] = []
	var tally: Dictionary = result["tally"]
	for target in tally:
		var who: Array[String] = []
		for voter in _votes:
			if _votes[voter] == target:
				who.append(state.players[voter].name)
		var label: String = "Skipped" if target == -1 else state.players[target].name
		lines.append("%s: %d (%s)" % [label, tally[target], ", ".join(who)])
	_overlay_box.add_child(_label("\n".join(lines), 18, DIM_COLOR, true))
	if state.winner != "":
		_overlay_box.add_child(_button("See who won", _show_game_over))
	else:
		_overlay_box.add_child(_button("Back to camp", func() -> void:
			state.end_meeting()
			_overlay_close()
			_advance()))


func _alive_humans() -> int:
	var count := 0
	for p in state.players:
		if p.human and p.alive:
			count += 1
	return count


# --- Game over -----------------------------------------------------------------

func _show_game_over() -> void:
	_hud_visible(false)
	board.show_view(state, null, [], true)
	var crew_won := state.winner == "crew"
	_overlay_open("LUMBERJACKS WIN!" if crew_won else "IMPOSTOR WINS!", CREW_COLOR if crew_won else IMPOSTOR_COLOR,
			Color(0.02, 0.02, 0.07, 0.75))
	_overlay_box.add_child(_label(state.win_reason, 22, Color.WHITE, true))
	var imp := state.impostor()
	_overlay_box.add_child(_label("The impostor was %s%s." % [imp.name, " (a bot)" if not imp.human else ""], 22, imp.color.lightened(0.3), true))
	var sheriff := state.sheriff()
	var sheriff_result := "SHERIFF WINS! %s shot the impostor." if state.sheriff_got_impostor \
			else "The Sheriff was %s. They lose: they didn't shoot the impostor."
	_overlay_box.add_child(_label(sheriff_result % (sheriff.name + (" (a bot)" if not sheriff.human else "")), 22,
			SHERIFF_COLOR if state.sheriff_got_impostor else DIM_COLOR, true))
	var progress := state.task_progress()
	_overlay_box.add_child(_label("Chores done: %d / %d   Rounds: %d" % [progress.x, progress.y, state.round_num], 18, DIM_COLOR, true))
	_overlay_box.add_child(_button("Play again", _show_setup))


# --- HUD -----------------------------------------------------------------------

func _refresh_hud() -> void:
	var p := _player
	var progress := state.task_progress()
	_task_bar.max_value = progress.y
	_task_bar.value = progress.x
	_task_count.text = "%d / %d " % [progress.x, progress.y]
	_top_label.text = "Round %d  —  %s's turn" % [state.round_num, p.name]
	_top_label.add_theme_color_override("font_color", p.color.lightened(0.3))
	var role := "LUMBERJACK"
	var role_color := CREW_COLOR
	if p.impostor:
		role = "IMPOSTOR"
		role_color = IMPOSTOR_COLOR
	elif p.sheriff:
		role = "SHERIFF"
		role_color = SHERIFF_COLOR
	if not p.alive:
		role += " (ghost)"
	elif p.impostor:
		role += "\nKill ready!" if p.kill_cooldown == 0 else "\nKill ready next round"
	elif p.sheriff:
		role += "\nBullets: %d" % p.bullets
		if p.bullets > 0:
			role += " — " + ("ready to shoot!" if p.kill_cooldown == 0 else "reloading")
	_role_label.text = role
	_role_label.add_theme_color_override("font_color", role_color)
	var lines: Array[String] = ["Fake chores (blend in!):" if p.impostor else "Your chores:"]
	for task in p.tasks:
		lines.append("%s %s — %s" % ["[x]" if task["done"] else "[  ]", task["room"], MapData.ROOM_TASKS[task["room"]]])
	_tasks_label.text = "\n".join(lines)
	_notes_label.text = "\n".join(p.notes.slice(-8)) if not p.notes.is_empty() else "Nothing yet."


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := Theme.new()
	theme.default_font_size = 20
	var panel_style := StyleBoxFlat.new()  # Solid dark-wood panels so text reads over the forest.
	panel_style.bg_color = Color(0.13, 0.09, 0.06, 0.94)
	panel_style.set_content_margin_all(8)
	theme.set_stylebox("panel", "PanelContainer", panel_style)

	var root := VBoxContainer.new()
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := PanelContainer.new()
	root.add_child(top)
	_top_bar = top
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top.add_child(top_row)
	_top_label = _label("", 24)
	_top_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_top_label)
	var tasks_title := _label("Camp chores", 18, DIM_COLOR)
	tasks_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	tasks_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(tasks_title)
	_task_bar = ProgressBar.new()
	_task_bar.custom_minimum_size = Vector2(260, 24)
	_task_bar.show_percentage = false
	_task_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_task_bar)
	_task_count = _label("", 18, DIM_COLOR)
	_task_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	top_row.add_child(_task_count)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(middle)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 330
	middle.add_child(side)
	_side_panel = side
	var side_box := VBoxContainer.new()
	side.add_child(side_box)
	_role_label = _label("", 26)
	side_box.add_child(_role_label)
	_tasks_label = _label("", 17)
	side_box.add_child(_tasks_label)
	side_box.add_child(HSeparator.new())
	side_box.add_child(_label("What you've seen:", 17, CREW_COLOR))
	_notes_label = _label("", 15, DIM_COLOR)
	side_box.add_child(_notes_label)

	var bottom := PanelContainer.new()
	root.add_child(bottom)
	_bottom_panel = bottom
	var bottom_box := VBoxContainer.new()
	bottom.add_child(bottom_box)
	_prompt_label = _label("", 20)
	bottom_box.add_child(_prompt_label)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("h_separation", 10)
	bottom_box.add_child(_buttons)

	_overlay = ColorRect.new()
	_overlay.theme = theme
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side_name in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side_name, 24)
	panel.add_child(margin)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 12)
	margin.add_child(_overlay_box)


func _hud_visible(on: bool) -> void:
	_top_bar.visible = on
	_side_panel.visible = on
	_bottom_panel.visible = on


func _overlay_open(title: String, title_color: Color, tint := Color(0.02, 0.02, 0.07, 0.94)) -> void:
	_overlay.color = tint
	_overlay.visible = true
	for child in _overlay_box.get_children():
		child.queue_free()
	_overlay_box.add_child(_label(title, 36, title_color, true))


func _overlay_close() -> void:
	_overlay.visible = false


func _clear_buttons() -> void:
	for child in _buttons.get_children():
		child.queue_free()


func _label(text: String, size := 20, color := Color.WHITE, centered := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _button(text: String, on_press: Callable, color := Color.WHITE) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(on_press)
	return button
