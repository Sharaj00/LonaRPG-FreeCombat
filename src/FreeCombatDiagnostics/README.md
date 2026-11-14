# Free Combat Playtest Diagnostics 0.2.4

For FreeCombatPrototype 0.8.13 on LonaRPG B.0.10.7.5.18 / Windows RGSS301 / Ruby 1.9.2. Optional local diagnostic tools; no network or save-format changes. Extra equipment is issued only in the disposable test. Enable it in the native mod manager and fully restart. Disable it and restart after playtesting.

Extract the archive and manually place its `FreeCombatDiagnostics/` folder in the game copy's `ModScripts/_Mods/` folder. The archive does not contain the parent folders.

## Optional debug tools

The overlay is hidden on each process start. On a game map, **F9** toggles it. **F6** on the title screen opens the isolated arena; **F7** opens the disposable native-map test; **F8** returns from that test to the title. Movement follows the game bindings; F5 resets the isolated F6 arena (A remains available for WASD). Tab/PgUp/PgDn issue test equipment only in the disposable map test. Save/load/delete paths are blocked in that test. These tools are absent when Diagnostics is disabled. Native F10 remains owned by the game.

## During a run

Recording starts automatically. Press **F11** once immediately after a problem to mark it with current map, fractional position, equipment and up to 24 nearby actors/objects. The game does not pause or open a diagnostic menu. Record a short description of the problem and approximate time separately. F10 remains the game's own debug console.

Reports are in `UserData/FreeCombatDiagnostics/diagnostics.jsonl` inside the game copy you launched. Keep `diagnostics.jsonl`, `.jsonl.1` and `.jsonl.2` together. These files form a rolling journal across sessions (three files, at most about 4 MiB each). Copy them after the run before repeated later runs rotate old evidence. JSON Lines can be parsed independently, even if the final line was interrupted by a crash. No save contents or screenshots are included. Logs contain local script paths, exception messages and gameplay identifiers.

The journal includes:

- Combat action attempts and pause changes share the bounded journal (no separate combat.log).
- Session start with runtime/combat/optimization versions, the actual enabled addon load order, adaptive compatibility status, companion collision setting and enabled hooks/GC settings.
- Map entry and user markers, including nearby object/projectile/controller membership for trap and fire investigation.
- Five-second or 600-frame summaries: wall/graphics/start-interval mean, P95, P99, maximum, GC-count delta, map/actor/effect/route counts. Includes combat-overlay and map-sprite timings in 0.2.0. Stage totals/calls/maxima are inclusive; do not add nested stages as independent costs.
- Every slow frame is counted at a 50 ms threshold; up to 12 samples per window include stage attribution. Up to six fire/trap effect samples per window are retained; the full event count is recorded. No per-target tracing or GC profiler is enabled.
- Exceptions crossing scene-main/update or native-save boundaries, their stack and context; errors are rethrown to preserve the game's handler and save rollback. Save results include basenames, not save data.

## Limits

This adds a small measurement cost. Timing is wall time; Graphics includes rendering and frame pacing, and intervals include OS/background/focus pauses. It is not a GPU profiler or proof that all elapsed time belongs to the addon. I/O happens at summaries/markers/errors, not every frame or sensor target. Logging I/O failure disables the recorder for the process rather than blocking gameplay; `FreeCombatDiagnostics.error` exposes the reason.

Events swallowed entirely inside native scripts, native engine crashes, forced process termination and permanent hangs cannot all be caught. Periodic summaries preceding the last five seconds remain on disk; shutdown of a scene flushes the current window. This recorder does not fix lamp/trap interaction or claim to resolve gameplay stutter. Those reports remain under investigation.
