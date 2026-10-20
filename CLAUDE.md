# Annexation — working notes for Claude

Solo game: Long War 1 mirrored from the alien invader's side. Godot 4.7, GDScript.
Claude writes the code; Nick playtests and reports with seeds. Nick is not an experienced
programmer: explain setup and testing steps plainly.

## Source of truth

The design doc (main tab) and its **Combat core spec** tab:
https://claude.ai/code/artifact/f3e129ee-378f-436b-9ea8-98d66da8c787
Read the relevant section before changing rules. If code and doc disagree, flag it rather
than silently picking one.

## Rules for the code

- **Logic separate from screens.** `core/` has no nodes or graphics and must run headless.
  `ui/` only displays results from `core/`.
- **Numbers live in `data/*.json`.** No balance values hard-coded in scripts. JSON numbers
  load as floats: convert with `int()`.
- **All randomness goes through `Dice`**, in a fixed order, so seed + squads = same battle.
  Never call `randi()`/`randf()` in `core/`.
- **One rulebook.** `CombatRules` is shared by the simulation and the future tactical grid.
- **Original names only.** No Firaxis/Long War names, assets or text.
- Push back on scope that doesn't serve the current roadmap slice.

## Workflow

- Work in build slices from the spec (1.1 duel, 1.2 squads, …). Each slice must be checkable
  by Nick in under an hour (he has 2–5 hours a week) and ends with a short checklist in the
  README.
- Before pushing: `godot --headless --path . --import`, then
  `godot --headless --path . --script res://tests/run_tests.gd` must pass. Add tests for
  every new rule.
- **Small changes need numbers, not feelings.** After any change to `core/` or `data/`, run
  `tools/compare.gd` and `tools/golden.gd` (see README, "Checking a change") and report what
  moved: the flagged rows, how many winners changed, how many golden battles changed. Say so
  plainly when the change is within chance. If the result is "identical", the change had no
  effect on any battle; say that too. Only save a new baseline or record new golden copies
  after Nick has accepted the differences, and commit them together with the change.
- Use a fresh, context-free reviewer for a batch of several small changes, or for anything that
  touches `CombatRules`, `Dice` or the order of dice rolls (these can silently break seed replay).
  Pure data-number changes are covered by `compare.gd` and need no reviewer.
