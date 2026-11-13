# Changelog

## 0.1.13

- Accept Free Combat 0.8.11 directional attack/projectile correction with existing capability guards. Numeric modules, DLL and GC-off defaults are unchanged.

## 0.1.12

- Accept Free Combat 0.8.10 native movement-binding fix in all compatibility guards. Numeric code/DLL and GC-off defaults are unchanged.

## 0.1.11

- Accept Free Combat 0.8.9 after optional debug tools moved to Diagnostics. Numeric code/DLL and GC-off defaults are unchanged.

## 0.1.10 - Early Access - 2026-11-13

- Accept FCP0.8.8 map/scene compatibility fixes with existing capability guards. Numeric code/DLL and GC-off defaults are unchanged.

## 0.1.9 - Early Access - 2026-11-13

- Accept FCP0.8.7 save-lifecycle fixes with existing source/arity guards. Math/DLL and GC-off defaults are unchanged.

## 0.1.8 - Early Access - 2026-11-13

- Accept FCP0.8.6 movement consequences with existing source/arity guards. Math/DLL and GC-off defaults are unchanged.

## 0.1.7 - Early Access - 2026-11-13

- Accept FCP0.8.5 skill-hold cancellation with existing source/arity guards. Math/DLL and GC-off defaults are unchanged.

## 0.1.6 - Early Access - 2026-11-13

- Accept FCP0.8.4 persistence fixes with existing source/arity guards. Math/DLL and GC-off defaults are unchanged.

## 0.1.5 - Early Access - 2026-11-13

- Accept FCP0.8.3 pause changes with existing source/arity guards. Math/DLL and GC-off defaults are unchanged.

- Removed FreeCombat from required dependencies; compatible versions remain optional adapters.
- Skip unavailable/unsupported FreeCombat interfaces without disabling the base addon or loading its numeric DLL.
- Made experimental GC available on native maps, with dialogue/control/pause guards and no double-counting inherited scene updates. GC remains off by default.
- Manual gameplay stability and performance verification remain pending.

## 0.1.4 - Early Access - 2026-11-13

- Accept FCP0.8.2 story-state fixes with existing guards. Math/DLL and default-off GC are unchanged.

## 0.1.3 - Early Access - 2026-11-13

- Accept FreeCombatPrototype 0.8.1 with source/arity guards intact; optimization algorithms, native DLL and default-off GC are unchanged.
- Verify the combined story-fix candidate in native RGSS; universal FPS and long-session stability remain unconfirmed.

## 0.1.2 - Early Access - 2026-11-13

- Accept FreeCombatPrototype 0.8.0 story mode in guarded preflight and implementation checks.
- Keep the geometry implementation, DLL and default-off GC unchanged.
- Native story startup and cold-load integration checked; long gameplay/performance acceptance remains pending.

## 0.1.1 - Early Access - 2026-11-13

- Explicitly support FreeCombatPrototype 0.7.2 while retaining 0.7.1. Keep source/arity ownership guards and the same authored geometry DLL.
- Reject unsupported versions during preflight before applying hooks. GC batching remains off by default.
- Validate seven native-loader cases on 0.7.2 and default backward loading on 0.7.1. Long manual acceptance and universal performance/stability gains remain pending.

## 0.1.0 - Early Access - 2026-11-13

- First unified addon distribution with native mod metadata and a single settings file.
- Combined scalar geometry, native x86 geometry, redundant-event-dispatch reduction and optional GC batching.
- Kept each approach independently configurable; GC batching defaults to off.
- Added deferred installation, dependency/legacy checks and a manual acceptance checklist.
- Stability, save/mod compatibility and real performance gains remain subject to manual testing.
