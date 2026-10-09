# Annexation (working title)

An alien-invasion strategy game: Long War 1 seen from the invader's side.
The design lives in the design doc; this repository holds the game.

Current build: **slice 1.1 — the duel.** One Warden fights one Regular soldier, shooting
only, with one tree on the field. The seed decides who shoots first and who stands behind
the tree (Half cover). The game prints a battle report.

## Running it

1. Install **Godot 4.7** (standard edition, not .NET) from https://godotengine.org/download.
   Godot is a single program; unzip it and run it, no installer needed.
2. Get this project onto your computer. Easiest: on the GitHub page, click **Code → Download ZIP**
   and unzip it. (Later, GitHub Desktop makes updating easier.)
3. Start Godot. In the Project Manager, click **Import**, pick the `project.godot` file in the
   unzipped folder, then **Import & Edit**.
4. Press **F5** (or the ▶ play button, top right) to run.

## Testing slice 1.1

The screen runs a battle straight away. **New random battle** fights another one.
Type a number into **Seed** and press **Fight this seed** to replay a battle exactly.

Check three things:

- **The report is readable.** You can follow who shot whom and why the battle ended.
- **Hit chances match the formula.** Each shot shows its working in brackets, e.g.
  `75% [Aim 65, range +10]`, and the roll that decided it. A shot hits when the roll is
  at or under the chance.
- **Same seed, same fight.** Note a seed, fight some others, then type it back in. The
  report must be identical.

To report a problem, press **Copy report** and paste it into the chat. The seed at the top
lets the battle be replayed exactly.

## Changing numbers

All numbers are in the `data/` folder as plain text (JSON). You can edit them in any text
editor, for example to change a weapon's damage in `data/weapons.json`. Run again to see
the effect. Keep the commas and quotes as they are.

## For developers

- `core/` — game logic with no graphics: rules, battle, report. Everything here runs headless.
- `data/` — all tunable numbers.
- `ui/` — screens. They only display what `core/` produces.
- `tools/run_batch.gd` — fights many duels and prints win rates:
  `godot --headless --path . --script res://tools/run_batch.gd -- --count=500 --start=1001`
- `tools/run_battle.gd` — prints a battle without a window:
  `godot --headless --path . --script res://tools/run_battle.gd -- --seed=48213`
- `tests/run_tests.gd` — automated checks:
  `godot --headless --path . --script res://tests/run_tests.gd`

Run `godot --headless --path . --import` once after a fresh clone so Godot registers the
script classes.
