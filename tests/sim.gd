extends SceneTree
## Plays lots of all-bot games to check that every game finishes and the
## balance is fair. Run from the project folder:
##   godot --headless --script res://tests/sim.gd

const GAMES := 1000


func _init() -> void:
	var wins := {"crew": 0, "impostor": 0}
	var reasons := {}
	var total_rounds := 0
	var meetings := 0
	var stuck := 0
	var kills := 0
	var sheriff_wins := 0
	var innocents_shot := 0
	var shots := 0
	for i in GAMES:
		var s := GameState.new()
		s.setup(0, i)
		var steps := 0
		while s.winner == "" and steps < 20000:
			steps += 1
			if not s.pending_meeting.is_empty():
				meetings += 1
				BotBrain.on_meeting(s)
				var votes := {}
				for p in s.players:
					if p.alive:
						votes[p.id] = BotBrain.vote(s, p)
				s.resolve_votes(votes)
				if s.winner == "":
					s.end_meeting()
				continue
			var p := s.current_player()
			s.begin_turn()
			BotBrain.take_turn(s, p)
			s.end_turn()
		if s.winner == "":
			stuck += 1
			continue
		for q in s.players:
			if q.killed_by >= 0:
				kills += 1
				if s.players[q.killed_by].sheriff:
					shots += 1
					if not q.impostor:
						innocents_shot += 1
		if s.sheriff_got_impostor:
			sheriff_wins += 1
		wins[s.winner] += 1
		reasons[s.win_reason] = reasons.get(s.win_reason, 0) + 1
		total_rounds += s.round_num
	var finished := GAMES - stuck
	print("Games: %d   stuck: %d" % [GAMES, stuck])
	print("Crew wins: %d%%   Impostor wins: %d%%" % [100 * wins["crew"] / finished, 100 * wins["impostor"] / finished])
	for reason in reasons:
		print("  %s %d" % [reason, reasons[reason]])
	print("Average rounds: %.1f   meetings per game: %.1f   kills per game: %.1f" % [float(total_rounds) / finished, float(meetings) / GAMES, float(kills) / finished])
	print("Sheriff wins: %d%%   Sheriff shots per game: %.2f (%.2f innocents)" % [
		100 * sheriff_wins / finished, float(shots) / finished, float(innocents_shot) / finished])
	quit(1 if stuck > 0 else 0)
