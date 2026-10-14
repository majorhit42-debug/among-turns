extends SceneTree
## Drives the real game and saves screenshots of each screen, to check the layout.
##   godot --script res://tests/screenshots.gd -- <output folder>

var out := "user://"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _shot("1_setup")
	main.state.setup(2, 7)
	for q in main.state.players:
		q.sheriff = q.id == 0 and not q.impostor
		q.bullets = GameState.SHERIFF_BULLETS if q.sheriff else 0
	main._told_role.clear()
	main._overlay_close()
	main._advance()
	await _shot("2_handover")
	main._begin_human_turn(main.state.current_player())
	await _shot("3_role")
	main._begin_human_turn(main.state.current_player())
	await _shot("4_move")
	var p = main.state.current_player()
	main._on_move(MapData.neighbors(p.room)[0])
	await _shot("5_act")
	main.state.call_meeting(p, "emergency")
	main._start_meeting()
	await _shot("6_meeting")
	main._start_voting()
	main._show_ballot(main.state.players[0])
	await _shot("7_ballot")
	main.state.sheriff_got_impostor = true
	main.state.winner = "crew"
	main.state.win_reason = "The Sheriff shot the impostor!"
	main._show_game_over()
	await _shot("9_sheriff_wins")
	main.state.sheriff_got_impostor = false
	main.state.winner = "impostor"
	main.state.win_reason = "The impostor got everyone!"
	main._show_game_over()
	await _shot("8_game_over")
	# Close-up of the characters at the game-over reveal.
	main._overlay_close()
	var cam := Camera3D.new()
	main.board.add_child(cam)
	cam.position = Vector3(-1, 7, -4)
	cam.look_at(Vector3(0, 0.8, -11))
	cam.make_current()
	await _shot("10_closeup")
	quit()


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
