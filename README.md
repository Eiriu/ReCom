# Annexation (working title)

An alien-invasion strategy game: Long War 1 seen from the invader's side.
The design lives in the design doc; this repository holds the game.

Current build: **slice 1.2 — squads.** Two Wardens and two Striders fight a Defender squad
of four Regulars (two rifles, a shotgun, a machine gun), shooting only. At the start every
unit rolls its cover: about 15% Full, 25% Half and 60% none (set in `data/terrains.json`,
"test_field"). Units keep that cover all battle until movement arrives in slice 1.3. The
slice 1.1 duel (with its tree) is still available from the drop-down.

## Running it

1. Install **Godot 4.7** (standard edition, not .NET) from https://godotengine.org/download.
   Godot is a single program; unzip it and run it, no installer needed.
2. Get this project onto your computer. Easiest: on the GitHub page, click **Code → Download ZIP**
   and unzip it. (Later, GitHub Desktop makes updating easier.)
3. Start Godot. In the Project Manager, click **Import**, pick the `project.godot` file in the
   unzipped folder, then **Import & Edit**.
4. Press **F5** (or the ▶ play button, top right) to run.

## Testing slice 1.2

The screen fights a squad battle straight away. **New random battle** fights another one.
Type a number into **Seed** and press **Fight this seed** to replay a battle exactly. The
drop-down at the left switches between the squad battle and the old duel.

Check four things (about 30 minutes):

- **Battles always end.** Every battle finishes with a Result line, either because one side
  has nobody left or because round 12 ended.
- **Turn order looks right.** Within each side's turn, faster units act first: Striders
  (Mobility 8) before Wardens (5). The Defender soldiers all have Mobility 6, so they act in
  roster order: Rifle-1, Rifle-2, Shotgun-1, MG-1. Units that are down never act again.
- **Cover is rolled for everyone.** The Cover lines at the top show each unit's roll and
  result (Full on 1–15, Half on 16–40, none above), and shots at that unit use it.
- **Deaths are counted correctly.** The Losses line and the list under it match what
  happened in the rounds above.

Each shot ends with the AI rule that chose it: **finish off** (an enemy it can kill with
one hit, at 50% or better) or **best attack** (the highest expected damage). Shooting ends a
unit's turn, so every unit still shoots once per turn. The second action matters from
slice 1.3, when units can move.

To report a problem, press **Copy report** and paste it into the chat. The seed at the top
lets the battle be replayed exactly.

## Checking a change (small ones too)

A single battle cannot show a small rule or number change, so two tools replay the same
battles before and after. Both use fixed seeds, so the same code always gives the same result.

**1. Did the change move the statistics?**

    godot --headless --path . --script res://tools/compare.gd

Fights 1000 battles per scenario and compares them with the saved baseline
(`tests/baseline.json`), battle by battle. It prints before, after and change for win rates,
losses, battle length and the first-turn advantage, and how many battles ended with a
different winner. `**` means clearly more than chance, `*` probably, blank means chance.
If nothing changed it says "Identical to the baseline". For very small changes use
`-- --count=5000` (the baseline's own seeds are reused for the first 1000).

**2. Which battles moved, and how?**

    godot --headless --path . --script res://tools/golden.gd -- --diff

Replays 12 fixed battles and compares each report with the saved copy in `tests/golden/`.
A small change should alter a few lines in a few battles. If every battle is rewritten
completely, something bigger than intended changed.

**After you have looked at the differences and accept them**, save the new reference points
and commit them with the change:

    godot --headless --path . --script res://tools/compare.gd -- --save --note="what changed"
    godot --headless --path . --script res://tools/golden.gd -- --record

## Changing numbers

All numbers are in the `data/` folder as plain text (JSON). You can edit them in any text
editor, for example to change a weapon's damage in `data/weapons.json`. Run again to see
the effect. Keep the commas and quotes as they are.

## For developers

- `core/` — game logic with no graphics: rules, battle, report. Everything here runs headless.
- `data/` — all tunable numbers.
- `ui/` — screens. They only display what `core/` produces.
- `tools/run_batch.gd` — fights many battles and prints win rates and losses:
  `godot --headless --path . --script res://tools/run_batch.gd -- --count=500 --start=1001`
  (add `--scenario=duel` for the duel)
- `tools/run_battle.gd` — prints a battle without a window:
  `godot --headless --path . --script res://tools/run_battle.gd -- --seed=48213`
- `tools/compare.gd` — before/after batch statistics against `tests/baseline.json` (see above).
- `tools/golden.gd` — replays fixed battles against `tests/golden/` (see above).
- `tests/run_tests.gd` — automated checks:
  `godot --headless --path . --script res://tests/run_tests.gd`

Run `godot --headless --path . --import` once after a fresh clone so Godot registers the
script classes.
