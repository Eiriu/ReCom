# Annexation (working title)

An alien-invasion strategy game: Long War 1 seen from the invader's side.
The design lives in the design doc; this repository holds the game.

Current build: **the whole combat core, slices 1.3–1.6.** Battles now have range bands,
terrain, moving and flanking (1.3), overwatch and suppression (1.4), Morale, psionics,
innate abilities, capture and withdrawal (1.5), and a batch runner that checks the spec's
balance targets (1.6). The test screen can fight any matchup from the spec, or a custom
battle you put together.

## Running it

1. Install **Godot 4.7** (standard edition, not .NET) from https://godotengine.org/download.
   Godot is a single program; unzip it and run it, no installer needed.
2. Get this project onto your computer. Easiest: on the GitHub page, click **Code → Download ZIP**
   and unzip it. (Later, GitHub Desktop makes updating easier.)
3. Start Godot. In the Project Manager, click **Import**, pick the `project.godot` file in the
   unzipped folder, then **Import & Edit**.
4. Press **F5** (or the ▶ play button, top right) to run.

## Testing slices 1.3–1.6

The screen fights a battle straight away. The drop-down at the left picks a ready-made
matchup (the spec's balance matchups, a Farmland version for comparison, the old squad battle
and the duel), or **Custom battle…**, which adds pickers for the squads, terrain, stance and
who goes first. **New random battle**, **Seed** and **Copy report** work as before.

Each slice below takes 20–30 minutes, so you can do one per session.

**Slice 1.3 — Battlefield**

- **Check one battle by hand.** Pick *2 Wardens, 2 Striders vs Defender squad · Forest*, seed
  **179**. In four rounds it has crits, two downed soldiers, overwatch shots at a moving
  soldier, suppression, a Shaken Warden retreating and being shot by its suppressor, and a
  withdrawal. Check a few hit chances against the formula and the Morale lines against the
  spec's table. For a flank, try seed **49**: a flank chance is 30 (Forest) + 5 × (Mobility − 5).
- **Range bands.** The line under the rosters says where both sides start (Close in Forest,
  Long in Farmland, Medium in Urban). A move shifts one band and rerolls cover; the report
  shows "(Half → Full cover, rolled 3)". Shots use the *shooter's* band for the range modifier.
- **Farmland and Forest feel different.** Fight a few of each: in Farmland the squads start at
  Long and spend their first turns moving in; in Forest they start at Close and shoot at once.
- **Flanking.** *This check fails at the moment; see "Decisions for you" below.*

**Slice 1.4 — Reactions**

- **Overwatch fires on movement.** A unit that "goes on overwatch" shoots the first enemy that
  moves or tries to flank, marked "↳ … reacts (overwatch)". The moving unit's cover for that
  shot is a separate "Caught moving" roll. The shot has "reaction −15" (none for Wardens,
  who are Steady) and never crits. Overwatch ends when the unit's side starts its next turn.
- **Suppression.** Only the machine gunner suppresses, using its whole turn, aimed at the
  highest-Aim enemy in Full or Half cover. The target's shots show "suppressed −30" (less for
  high Will) until the gunner's next turn, it loses 5 Morale at the start of its turn, and if
  it moves the gunner gets one reaction shot.

**Slice 1.5 — Nerve**

- **Shaken and Broken.** Indented "Morale (…)" lines show every change and why. Below 25 a unit
  is Shaken: it stops shooting, moves for cover or hunkers down if already in Full cover.
  At 0 it is Broken and flees: it survives but is out of the battle.
- **Harrow.** Try *4 Wardens, 1 Harrow vs Strike team · Urban*. Mind spike shows its chance
  as 50 + (Will − Will) / 2; Rally fires when two or more allies are Shaken or Wounded.
- **Vessels and Drones.** Try *6 Vessels, 1 Drone vs Defender squad · Farmland*. Vessel shots
  show "swarm +5 to +15"; Vessels shake easily (that is intended); the Drone repairs badly
  hurt allies twice per battle and never shakes.
- **Capture and withdrawal.** The Result line says why the battle ended. When the invaders hold
  the field, downed soldiers are captured and each dead invader gets a recovery roll (25%,
  Drones 50%). In **Custom battle…**, Cautious withdraws at the first death and All-in never does.

**Slice 1.6 — Batch runner**

    godot --headless --path . --script res://tools/run_batch.gd -- --detail

(about 30 seconds; the headless commands need Godot on your command line — I can run them for
you instead). It prints the spec's balance table with each result marked ok, LOW or HIGH, and
with `--detail` the flank, withdrawal and action counts per matchup.

To report a problem, press **Copy report** and paste it into the chat. The seed at the top
lets the battle be replayed exactly.

## Decisions for you

The rules are all in, but these questions need your answer before balance tuning:

1. **Flanking is too rare, or too common.** The spec scores a flank as "chance it works × the
   flanked shot", so a failed flank counts as a wasted turn. But a unit that fails a flank
   still gets its shot, and then flanking is almost never chosen: Striders try 0.2 times
   per battle in Forest. Counting the shot after a failed flank
   (`"flank_counts_fallback_shot": true` in `data/combat.json`) makes flanking strictly
   better than shooting, so *every* unit flanks first, Wardens most of all. The real cost of a
   flank, losing good cover and drawing overwatch, is in neither score.
2. **Battles are short and decided by withdrawal.** A squad of four withdraws after losing two
   while the enemy still has four. That ends most battles in round 2–3; the target is 4–8.
   Without withdrawal, battles run to round 12, where the attacked side holds the field, and
   the invaders almost never win.
3. **Units wait a lot.** "Best attack" needs an expected 1.5 damage. Shots into Full or Half
   cover, and at Veterans, score below that, so units go on overwatch instead. A threshold
   of 1.0 brings two matchups inside their targets.
4. **4 Wardens vs Strike team at a Crash site** wins under 1% (target 10–20%) whatever the
   other settings are: four against six Veterans is very hard.
5. **Hit and run** (Strider) is built as "can still move after shooting, but shoots once per
   turn and does not go on overwatch after shooting". The spec's wording would allow two
   shots a turn.
6. **First turn.** The spec says the attacking side goes first, so the balance matchups always
   start with the invaders. The old squad battle and the duel still roll for it, as you asked.
7. **Who gets Mind spiked and suppressed.** The spec says "highest Aim", so the Harrow and the
   machine gunner keep picking the same unit even when it is already Shaken and hunkered.
   Using Aim after penalties, or skipping Shaken targets, would fix that.
8. **"For a plain move, use the terrain's average cover."** The spec says this for scoring a
   move-then-shoot plan, but the mover's own cover doesn't change its shot, so I score the
   target's current cover. Tell me if you meant something else.
9. **Overkill in the AI's scoring.** The spec counts full average damage. Slice 1.2 capped it at
   the target's remaining Health, which made units ignore nearly dead enemies, so I've
   followed the spec. The old behaviour is `"cap_damage_at_health": true`.

## Checking a change (small ones too)

A single battle cannot show a small rule or number change, so two tools replay the same
battles before and after. Both use fixed seeds, so the same code always gives the same result.

**1. Did the change move the statistics?**

    godot --headless --path . --script res://tools/compare.gd

Fights 1000 battles per scenario (about 30 seconds) and compares them with the saved baseline
(`tests/baseline.json`), battle by battle. It prints before, after and change for win rates,
losses, battle length and the first-turn advantage, and how many battles ended with a
different winner. `**` means clearly more than chance, `*` probably, blank means chance.
If nothing changed it says "Identical to the baseline". For very small changes use
`-- --count=5000` (the baseline's own seeds are reused for the first 1000).

**2. Which battles moved, and how?**

    godot --headless --path . --script res://tools/golden.gd -- --diff

Replays fixed battles (two per matchup, plus extra squad and duel seeds) and compares each
report with the saved copy in `tests/golden/`.
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
- `data/matchups.json` — the ready-made battles and their win-rate targets.
- `tools/run_batch.gd` — the balance table (slice 1.6): `-- --count=2000`, `--matchup=mixed_forest`,
  `--all` (test-only matchups too), `--detail`.
- `tools/run_battle.gd` — prints a battle without a window:
  `godot --headless --path . --script res://tools/run_battle.gd -- --seed=179 --scenario=mixed_forest`
  (scenario ids: `duel` plus the keys in `data/matchups.json`; add `--summary` for the short report)
- `tools/compare.gd` — before/after batch statistics against `tests/baseline.json` (see above).
- `tools/golden.gd` — replays fixed battles against `tests/golden/` (see above).
- `tests/run_tests.gd` — automated checks:
  `godot --headless --path . --script res://tests/run_tests.gd`

Run `godot --headless --path . --import` once after a fresh clone so Godot registers the
script classes.
