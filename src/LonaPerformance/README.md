# Lona Performance 0.1.13 - Early Access

The first Early Access release combines the previously investigated performance approaches into one addon. Actual stability, compatibility and performance gains in normal gameplay still require manual verification. This release is not a stable-60-FPS guarantee.

Target: LonaRPG B.0.10.7.5.18 and original Windows x86 RGSS301. **FreeCombat is optional.** The addon can be enabled and loaded with FreeCombat disabled or completely absent.

The existing geometry and event-dispatch optimizations apply only to compatible FreeCombat interfaces (versions 0.7.1, 0.7.2, and 0.8.0 through 0.8.11). When FreeCombat is absent, those adapters and their numeric DLL are not loaded. The addon does not claim to accelerate the native game's AI with FreeCombat-specific algorithms.

Experimental GC batching is an independent component for native Scene_Map gameplay as well as supported FreeCombat scenes. It remains off by default. With unsupported/partial FreeCombat interfaces, adapters and GC batching are skipped conservatively without disabling Lona Performance; compatibility state is reported in LonaPerformance.status.

## Included approaches and defaults

| Setting in settings.rb | Default | Purpose |
|---|---|---|
| SCALAR_GEOMETRY | true | Optional FreeCombat adapter: reduce temporary objects in Ruby segment/rectangle math |
| NATIVE_GEOMETRY | true | Optional FreeCombat adapter: native point and swept-circle wall queries |
| EVENT_DISPATCH | true | Optional FreeCombat adapter: reduce controller/single-opponent checks |
| GC_BATCH_FRAMES | 0 (off) | Independent experimental GC on native/supported FreeCombat maps; optional values 16 or 30 |

Each switch can be changed independently. Edit `ModScripts/_Mods/LonaPerformance/settings.rb` while the game is closed, then restart. No additional settings framework is installed.

GC batching pauses during native dialogue/interpreter activity, loss of player control, forced movement, jumps and game pause, and releases its ownership on scene changes/errors. It uses FreeCombat's own suspension/pause checks when the compatible adapter is present. Nested Scene_Map/Scene_FreeCombatMap hooks count only one update.

GC batching delays finalizers and can affect other mods/resources. It is off by default. Its memory guardrails are 32 MiB growth and 768 MiB private process memory, but they cannot prevent an unusually large allocation within one frame. Keep it disabled for the initial manual test.

## Installation

1. Back up the test copy and close the game. Keep the original installation unchanged.
2. Remove the old standalone `ModScripts/60000_RGSSPerformancePatch.rb`, `60010_RGSSCombatPerformance.rb` and `60020_RGSSCombatGCExperiment.rb` from the test copy. Retain backups outside any auto-loaded mod folder. The old `ModScripts/RGSSCombatPerformance/` DLL folder can also be removed after backup.
3. Extract the archive and manually copy its `LonaPerformance/` folder into `ModScripts/_Mods/` in the test copy. Do not copy separate patches alongside it.
4. Enable **Lona Performance - Early Access** in the native mod manager, save the mod list, then completely restart the game. FreeCombat is optional; enable a supported version only if you want its additional optimizations.

The addon installs its hooks after the complete mod-loading phase. Invalid settings or a legacy standalone patch are reported in the native log/mod error state instead of intentionally stacking patches. A missing/incompatible numeric DLL retains the Ruby path. Source-ownership guards can skip unknown overrides; this is conservative handling, not proof of compatibility with all mods.

The DLL is bundled under `LonaPerformance/native/geometry-x86.dll`. It is an authored arithmetic library, not a modified RGSS301.dll. It has no imported CRT/runtime dependency and does not access Ruby object internals or private engine functions. Static wall arrays retain the original replace-by-identity invalidation contract; dynamic routing bodies are repacked for each query.

## Disable or roll back

Close the game, disable Lona Performance in the mod manager and restart. To uninstall, remove only `ModScripts/_Mods/LonaPerformance/` from the test copy after backup. No save conversion is provided or expected; actual save/load compatibility remains a manual test item. To return to an old candidate, keep this addon disabled/removed before restoring its standalone files. Never load both distributions together.

## Verification status

Packaging checks cover addon loading, dependency/legacy guards, configuration, module switches, DLL identity and archive integrity. Earlier isolated RGSS predicate tests and synthetic/game stress captures informed the implementation, but are not manual acceptance of this combined release. In particular, the previous paused-courtyard controls showed a higher pooled P99 despite a similar mean. No universal stability or performance improvement is claimed.

Use [MANUAL_TESTS.md](MANUAL_TESTS.md) to record real gameplay results. Do not enable automatic benchmark bootstraps or profiling during ordinary play; the release contains neither. Code/build provenance is in `SOURCE.md`.

## Credits

AI-assisted development and packaging: Codex. The game and RGSS runtime remain external requirements; FreeCombatPrototype is an optional integration. Each is credited to its respective authors; no game/runtime assets are bundled.
