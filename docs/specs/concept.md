# Pebbix — Concept & v1 Scope

## Positioning

The bubble-shooter genre is saturated with level-pack free-to-play titles (Bubble Witch, Angry Birds POP) that compete on content volume — a treadmill a solo project cannot win.
This game competes on **precision and pressure** instead: a skill-based arcade bubble shooter where the player always sees exactly where the shot will land, and the fun comes from executing bank shots under a descending ceiling.

## Core loop

Aim with assistance that retires as pressure rises → shoot → pop 3+ matches → drop floating clusters for bonus → ceiling descends on an accelerating cadence → survive and chase score.

## Differentiators (the 승부처)

1. **Honest learning, earned mastery.** The early full trajectory preview includes wall reflections and never lies because the engine is deterministic (same input, same result). After the player has learned the shot language, the preview shortens and then disappears as an intentional mastery test rather than adding random fuzz.
2. **Bank-shot economy.** Shots that bounce off a wall before landing score a multiplier. Drops (floating clusters) score more than pops. The scoring system pays for skill, not grind.
3. **Pressure, not levels.** One endless mode with a ceiling that descends every N shots and speeds up. Session = 2–5 minutes, score-chasing replayability. No level content treadmill.
4. **Game feel.** Flame effects budget goes into pop particles, drop gravity, squash-and-stretch on snap — the "juice" that separates a toy from a game.

## Fun factors, ranked

1. The _thock_ of a 3-match after a two-wall bank shot the player called in advance.
2. Cascade drops — cutting one stem bubble and watching seven fall.
3. Near-miss ceiling tension — clearing the screen one row before the fail line.

## v1 scope (Definition of Done)

- Circle-rendered bubbles, one fixed starting board, drag/touch aim.
- Wall reflection, hex-grid snap, 3+ same-color pop, floating-cluster drop.
- Fail line + restart. Score with bank/drop bonuses.
- Same shot input always lands in the same cell; any visible aim guide matches the actual result.
- Aim assistance withdraws one capability at a time as ceiling pressure rises: the landing ring, then the reflected path (the guide stops at the first reflection), then the guide itself; the tiers and thresholds are owned by `2026-08-10-vertical-budget-and-run-variety.md`.
- Match/floating searches covered by unit tests; board vs touch coordinates stay aligned at any screen size.

Out of scope for v1: level editor, boosters, ads/IAP, skins, stage select. Art and audio polish come only after the core loop is proven fun.

## Architecture (decided — see CLAUDE.md)

Flutter app shell + Flame rendering + pure-Dart deterministic domain (`lib/game/domain/`). Hex axial coordinates. No Forge2D. Trajectory precomputed by solver; Flame only animates the computed path.
