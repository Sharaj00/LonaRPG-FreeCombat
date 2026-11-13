# Built-in adaptive compatibility (0.8.12)

Changes prepared for public Beta 0.8.12 on top of 0.8.11. The maintained project is not a Git checkout; published snapshots under output/releases are immutable references for this work.

## Runtime boundary

FreeCombatPrototype/compatibility.rb owns the six existing integration bridges. The global FreeCombatCompatibility helper namespace is retained for existing consumers, but no separate mod is required. The core entry registers the adapters; a guarded SceneManager.run hook applies them once after addon loading, before native scenes start. LonaPerformance already uses this startup boundary. Diagnostics initializes its journal on the first scene and records adapter status alongside performance status.

Only enabled, successfully loaded mods activate an adapter. Known versions: RolePlayS 0.7.9.3, Temper Trine 1.5.2, Faction Clashes 0.3.22 and Rest Journal 3.5. PassiveStaminaRegen has legacy metadata, so the captured native update source is checked instead. Unknown versions or missing interfaces are skipped with an explicit status reason. All interface checks that precede the actor wrappers run before their aliases are changed. Diagnostic tools remain in Diagnostics; the core does not add a debug UI or independent log file.

The adapters retain passive STA recovery, Temper frame pause, explicit Faction Clashes interaction intent, external load-context rollback, RolePlayS backward dodge and registered-map journal rules. The rollback bridge works with RolePlayS or Rest Journal individually. The registered-map bridge requires both. Missing mods are never automatically enabled.

## Obsolete standalone addon

Core metadata declares `before` for FreeCombatCompatibility, Diagnostics and LonaPerformance. At core load, a still-enabled standalone Compatibility is disabled in the native manager's in-memory state with a replacement explanation, before its entry executes. No third-party source or user save is deleted. The original standalone source is retained under src/FreeCombatCompatibility as historical source; future aggregate development packages omit it. A physically absent standalone folder and a remaining enabled old folder are separate native test cases.

## Automatic load order (0.8.12)

Core-owned load_order.rb runs at the beginning of the FreeCombat entry, before its method aliases are captured. It plans the enabled known IDs in the verified stack order, respecting native `before` rules and enabled dependencies. Folder names are resolved through mod.path, so Temper Trine / temper_trine is handled correctly. No third-party metadata or original loader is modified.

The relative order of unmanaged and disabled addons is preserved. Their positions may move when required by known-mod precedence or explicit metadata constraints. Disabled addons are not enabled; unknown versions are still checked independently by the adaptive bridges. There is no promise that arbitrary unknown mods become compatible merely through ordering.

If the order is already correct, the planner performs no write or restart. If correction is needed, it backs up the current INI to UserData/GameMods.ini.free-combat-order.bak, writes only LoadOrder values, notifies the player and stops startup. Restart the game once. This avoids executing a partially reordered session after some scripts have already run. The next startup uses the native loader normally; repeated ordering changes are not required. No save is loaded or modified by the planner.

Native save_ini is deliberately not used because it also persists runtime enabled/error flags. A failed INI write restores the original bytes. Contradictory constraints stop startup with a conflict explanation, without writing an alternative order. Existing native dependency validation can also reject an invalid mod set before the FreeCombat entry runs; it is not bypassed. The native manager's before edges for the core tools remain in metadata as a minimal early safeguard.

Diagnostics session_start records the actual enabled and loaded addon IDs in load order. The isolated planner checks cover randomized permutations, dependencies, preservation of unmanaged relative order, cyclic constraints, no-op behavior, flags/custom settings, save non-interference and write-failure restoration. Native tests use an early private message hook to record the restart notice; no such hook ships with the addon.

## Persistence and packaging

No save-schema migration is introduced by moving the adapters. The test uses only independently generated private saves, including real scene quickSave/quickLoad and failed-load rollback. RolePlayS still requires a new game when added to an existing setup; the merge does not remove that upstream boundary. User save migration is not inferred from the private fixture.

The release builder writes versioned archives under output/releases/. Existing public Beta archives and repository snapshots are preserved. New core packages include compatibility.rb, and the separate Compatibility package is removed from the aggregate builder. Old individual builders remain historical tools, not a current dependency.

Native evidence: output/integrated-compatibility-verification/. Full-story acceptance and unsupported third-party versions remain outside the result.

## Recorded results

Native matrix: 11 cases / 187 assertions, zero failures. Base and full sets, five individual mods, obsolete standalone in the wrong relative position, an unsupported version, a missing interface and incorrect passive ordering were exercised. The full set includes cold load, six functional bridge checks, real quickSave/quickLoad and failure rollback. See summary.json and per-case logs in the evidence directory.

Mandatory project runner: 148 general RGSS checks and 17 movement-binding checks pass; arena.bmp was inspected. The playable output/story-mods copy now contains the tested core/Diagnostics files, without a standalone Compatibility folder or startup test hooks. UserData hashes before and after installation match. The old addon and UserData are backed up; installation.json records the paths and hashes. No user save was loaded for testing. No commit, push or public release was performed.

Automatic ordering acceptance: 212 isolated RGSS assertions plus 68 native checks across shuffled full set, reverse base order and PassiveStaminaRegen initially after the core. Each incorrect input converged after one restart; the second startup performed no correction. Native before/after INIs confirm unchanged enable flags/custom settings, preserved relative order of two unrelated fixtures and a disabled fixture, and an enabled dependency loaded first. The full native scenario includes all six adapters and real quick-save/load. Evidence: output/load-order-verification/.

Final acceptance: a further full-set title-only smoke passes 22 checks without repeating gameplay, and the required general RGSS 148 / movement-binding 17 checks pass. The entry applies ordering only when the native ModManager exists, preserving the isolated runner. Temporary hooks and fictitious mods are archived outside auto-load paths. The local story-mods copy contains final tested code; its UserData hashes are unchanged. These results were collected before publication.

Final release stack: FreeCombat 0.8.12, Diagnostics 0.2.3 and LonaPerformance 0.1.14 pass 26 native loader checks. ZIP executable bytes match the tested runner.
