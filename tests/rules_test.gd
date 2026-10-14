extends SceneTree
## Checks tricky rules directly. Run from the project folder:
##   godot --headless --script res://tests/rules_test.gd

var failures := 0


func _init() -> void:
	_test_shot_impostor_stays_secret()
	_test_late_shot_ends_game()
	_test_shot_impostor_and_tasks_done()
	print("rules_test: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


## Sheriff shoots the impostor first: game keeps going until 3 players are dead.
func _test_shot_impostor_stays_secret() -> void:
	var s := _game()
	var sheriff := s.sheriff()
	var imp := s.impostor()
	s.shoot(sheriff, imp)
	_check(s.winner == "", "impostor shot as 1st death should stay secret")
	_kill_innocent(s, sheriff)
	_check(s.winner == "", "2 deaths should still be secret")
	_eject_innocent(s)
	_check(s.winner == "crew" and s.sheriff_got_impostor, "3rd death should reveal the Sheriff's win")


## Once 3 are dead, shooting the impostor ends the game right away.
func _test_late_shot_ends_game() -> void:
	var s := _game()
	for i in 3:
		_eject_innocent(s)
	_check(s.winner == "", "3 innocents dead, impostor alive: game goes on")
	s.shoot(s.sheriff(), s.impostor())
	_check(s.winner == "crew" and s.sheriff_got_impostor, "shot after 3 deaths should end the game")


## Crew finishes tasks after the impostor was secretly shot: crew AND Sheriff win.
func _test_shot_impostor_and_tasks_done() -> void:
	var s := _game()
	s.shoot(s.sheriff(), s.impostor())
	for p in s.players:
		if not p.impostor:
			for task in p.tasks:
				task["done"] = true
	s.check_win()
	_check(s.winner == "crew" and s.sheriff_got_impostor, "tasks done after secret shot: crew + Sheriff win")


func _game() -> GameState:
	var s := GameState.new()
	s.setup(0, 1)
	return s


func _kill_innocent(s: GameState, not_this: GameState.Player) -> void:
	for p in s.players:
		if p.alive and not p.impostor and not p.sheriff and p != not_this:
			p.alive = false
			s.check_win()
			return


func _eject_innocent(s: GameState) -> void:
	for p in s.players:
		if p.alive and not p.impostor and not p.sheriff:
			s.resolve_votes({0: p.id})
			return


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)
