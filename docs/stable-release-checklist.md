# Functional acceptance for the first stable release

Current candidate: FCP 0.8.11 on LonaRPG B.0.10.7.5.18 / Windows RGSS301, with optional Compatibility 0.1.1, Diagnostics 0.2.1 and LP 0.1.12 (experimental GC off). The selected twelve-mod stack has focused integration evidence in docs/mod-compatibility-0.1.0.md. A short user playtest reported no critical issues; a complete ordinary story route remains pending. This is not full-game acceptance.

## Priority 1: Story control and outcomes

Exercise native entry and exit for forced scenes/routes, camera targets, capture/restraint, release, incapacitation, defeat and death. Include transitions between native and continuous control and save/load where native rules permit. No stuck controls, skipped outcome events, duplicated combat updates, lost progression or continued player attacks while native control is disabled. Existing bounded restraint/route checks are useful evidence, not coverage of every story state.

## Priority 2: Environment and temporal behavior

Check the interaction of pause, menus and cutscenes with NPCs, traps, persistent fire, missiles, charging/recovery and status durations. Test effect expiry/cleanup on map changes and load. Preserve native resource and time consequences for steps, running/crouching, rest, dangerous tiles, touch events and day changes. Treat inconsistent behavior as a hypothesis until reproduced; do not patch native scripts speculatively.

## Priority 3: Remaining skill families

Cover unverified distinct execution paths: shield/block/parry, wide or multi-target attacks, musket reload, defensive spells, persistent summons and their lifetimes. Include interruption, insufficient resources, equipment changes and save/load only when meaningful. Do not replay completed unique-NPC or summon-command suites without an affected shared seam. Missing upstream effects are documented limitations, not permission to invent game mechanics.

## Priority 4: Persistence and companions

Run repeated manual/autosave/load cycles across maps, rest/day changes, active effects and companions. Verify native hardcore/Doom restrictions and intended death-save deletion without touching a player's real saves. Test forward migration from a supported prior addon version. No vanilla/uninstall/downgrade compatibility promise: current saves require the addon enabled. Ensure no duplicated companions/effects or persisted runtime controllers.

## Priority 5: End-to-end acceptance

Complete at least one story route from an ordinary New Game to an ending with the release candidate, native saves and diagnostics. No F7 progression, test gear, debug teleports or manual save edits to bypass a blocker. Record the route, candidate version and remaining defects. One route supports that route only; other story branches must remain explicitly unverified until exercised. Any save loss, crash, progression lock or repeatable addon-induced severe stall blocks stable release.

## Release boundaries

Publish the supported game version and tested mod combination, ordinary story controls, upgrade/backup instructions, known limits and save dependency. Retain an isolated F7 test mode. Broad third-party-mod compatibility, gamepad support, engine replacement and new gameplay features are not automatically part of this release. Keep GC experiments off by default.

Remaining Graphics.update stalls are not proven to be exclusively game-engine faults. Record them for later attribution; do not require an arbitrary stable60FPS promise to finish functional work, and do not dismiss newly reproduced addon regressions as engine issues.

This is an acceptance/implementation queue, not new verification evidence. Known baseline evidence: general148, lamp/object/HUD regressions4, cold-load/save15 and recorder10. Next functional batch starts with story control/outcome transitions and fixes only reproduced gaps.
