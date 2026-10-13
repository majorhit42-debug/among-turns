# Among Turns — CLAUDE.md

> **Working title.** Axel gets to name it — change `config/name` in `project.godot`, the title in `scripts/main.gd` (`_show_setup`), and this file.

## Project Overview

A **turn-based Among Us for one shared screen**. 8 crewmates (1 impostor) on a small ship of 8 rooms. Real players pass the screen between turns; bots fill the empty seats. 1–8 humans.

**Live URL:** https://among-turns.vercel.app/
**Repository:** https://github.com/majorhit42-debug/among-turns

A father-son project — Todd and Axel. We build by chatting with Claude Code directly in this window (no separate prompt files).

## Tech Stack

- **Engine:** Godot 4.6, GDScript (no C# — it can't export to web)
- **Renderer:** Compatibility (WebGL 2) — required for web export. Don't switch to Forward+/Mobile.
- **Look:** 3D, fixed top-down camera, everything built from simple shapes in code (no imported models yet)
- **Hosting:** Vercel serves `builds/web/`. Connected to GitHub: every push to `main` redeploys.

## How the game works

- **A round** = every player takes one turn, in seat order (Red, Blue, Green, …).
- **A turn** = move to a room next door (or stay), then do one thing:
  - **Task** — only if you *stayed put* this turn and have a task in that room
  - **Kill** (impostor) — anyone in the room; kill cooldown 1 round; no kills in round 1
  - **Report body** — starts a meeting
  - **Emergency meeting** — in Cafeteria, once per player per game
- **Vents** (impostor only) count as a move: Medbay↔Electrical, Weapons↔Shields, Engine↔Navigation.
- **Hidden info:** you only see who's in *your* room. Each player keeps a private "What you've seen" log.
- **Meetings:** all bodies are found and removed; bots make statements; humans argue out loud; everyone votes in secret (pass the screen); most votes is ejected, tie/skip = nobody. Then everyone returns to Cafeteria.
- **Win:** crew finish all tasks (ghosts keep doing tasks) or vote out the impostor; impostor wins when crew alive ≤ impostors alive.

## Bots (`scripts/bot_brain.gd`)

- **Crew bots** walk to their nearest task, report bodies they see, remember who they saw where, and add suspicion: +100 for seeing a kill, +2 for being seen near a body, plus what others say in meetings. If someone accuses *them*, they know it's a lie (+3 on the accuser). They vote at suspicion ≥ 4.
- **Impostor bot** kills anyone it finds alone. **It cheats a little:** it can sense rooms with exactly one crewmate. Without that it almost never found anyone alone (impostor won ~5%). It fake-tasks while on cooldown, accuses random players in 45% of meetings, and votes with the crowd.

## File Structure

```
among-turns/
├── project.godot / export_presets.cfg / vercel.json
├── scenes/main.tscn        # Just a Node3D running main.gd — everything else is built in code
├── scripts/
│   ├── map_data.gd         # Rooms, positions, halls, vents, task names. Edit the map here.
│   ├── game_state.gd       # ALL the rules, no graphics. Player inner class.
│   ├── bot_brain.gd        # Bot turns, meeting statements, votes
│   ├── board.gd            # 3D ship, crewmates, bodies; shows only what the viewer can see
│   └── main.gd             # Screen flow + UI: setup → hand-over → turn → meeting → vote → game over
└── tests/
    ├── sim.gd              # Plays 1000 all-bot games: checks none get stuck, prints balance
    └── screenshots.gd      # Drives the real game and saves a PNG of every screen
```

## Rules for working on this project

- **Keep rules in `game_state.gd` and out of `main.gd`.** That's what lets the simulator test them.
- **After changing rules or bots, run the simulator** and keep bot-only games roughly 50–65% crew wins:
  `godot --headless --script res://tests/sim.gd`
  Current baseline: 58% crew / 41% impostor, ~15 rounds, ~5 kills, ~2 meetings per game.
- **After UI changes, check the screenshots:**
  `godot --script res://tests/screenshots.gd -- <folder>`
- **Never leak secrets on the shared screen.** Between turns (hand-over, meetings, bot turns) the board shows nobody. Only the active human's own room is shown during their turn.
- Every HUD container that covers the board uses `mouse_filter = IGNORE`, so room clicks reach the 3D board.
- **To update the live site:** re-export with `godot --headless --export-release among-turns builds/web/index.html`, commit `builds/web/`, and push. Vercel only serves the files; it doesn't build the game.

## Roadmap / ideas

- **Humans speak in meetings:** "I saw X kill!" / "X is sus" buttons that bots listen to. Right now bots ignore what humans say out loud.
- Axel names the game
- Sabotage (lights out = you can't see who's in your room; reactor countdown)
- Animations: walk between rooms, kill animation, ejection scene
- Player-chosen colors and names, hats
- 2 impostors for 10-player games
- Sound
