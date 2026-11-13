# Supplied mod stack compatibility 0.1.0

Target: LonaRPG B.0.10.7.5.18, RGSS301 / Ruby 1.9.2. The user selected a **new game with all twelve supplied mods**. The independent playable copy is `output/story-mods/Game.exe`; `output/story-lab`, its saves and the original game are preserved. Only GameLona.ini preferences are copied from story-lab. The new copy has no imported saves.

## Delivery

`src/FreeCombatCompatibility/` contains the authored optional bridge. Its README lists exact versions and load order; the machine-readable order is `output/mod-compat-verification/load-order.json`. All twelve supplied mods load before Free Combat 0.8.10, Compatibility 0.1.0, Diagnostics 0.2.1 and Lona Performance 0.1.12. Diagnostics retains its hidden F9 panel and F11 markers; compatibility adds no debug UI.

The native manager uses folder names for GameMods.ini and reads Game.ini Title as the game version. Keep `Temper Trine` as the folder section and `B.0.10.7.5.18` as Title. PassiveStaminaRegen intentionally uses the native legacy loader. RolePlayS metadata is accepted by the native decoder; its original formatting is preserved. Dormant RolePlayS scripts are not enabled.

The ZIP contains only three authored addon files. Supplied scripts/assets and game runtime remain local; redistribution permission was not established. Source references under `mods/` are preserved and checked against the initial 2016-file SHA256 inventory.

## Corrected integration defects

- FCP-051: restore passive stamina regeneration on continuous movement, exactly once per eligible frame, frozen during combat pause; retain earlier update hooks.
- FCP-052: freeze Temper frame-based activity and Stage2/Stage3 ticks during combat pause; retain date calculations and dialog release.
- FCP-053: carry explicit E/Enter interaction intent into Faction Clashes without qualifying attacks or contact as confirmation.
- FCP-054: restore Rest Journal visit and RolePlayS class module contexts after a rejected or failed load.
- FCP-055: route RolePlayS backward dodge through the controlled actor collision/body bridge while preserving facing.
- FCP-056: resolve registered map notes and canonical identities for Rest Journal; maintain separate region rules and visits across RolePlayS filename-based maps.

These changes live in the optional bridge; supplied references and Free Combat core sources are not patched.

## Verification and limits

Native checks use independently generated characters through the real RolePlayS creation screen (default Adventurer). Key input is injected at the physical-polling boundary; this does not establish physical keyboard acceptance.

Evidence is under `output/mod-compat-verification/`. Baseline files reproduce the integration failures. `fixed-seams-mod-compat-verification.txt` records passing stamina, Temper, faction intent, rollback and controlled Musketeer dodge/deletion cases. Cooking items, regeneration states, paused/resumed effects and delayed cure cancellation pass. That phase later stopped in a unique-NPC fixture; it is not claimed as a complete suite.

`warm-save-passed-mod-compat-verification.txt` records real scene quick-save and warm quick-load preserving class, Temper, visit and native progress. Its later map fixture lookup was corrected. `registered-notes-passed-mod-compat-verification.txt` completes 36 checks with no failures, covering cold load, three region note classifications, added-map movement and return. `map-identity-before-mod-compat-verification.txt` reproduces two identity defects; `map-identity-fixed-mod-compat-verification.txt` completes 25 checks with no failures, including transitions between two registered maps and return to town. Completed earlier effects suites were not replayed.

Fixture corrections: native quickSave must dispose the spriteset before marshaling lighting; direct low-level saves produced an invalid Shadow_Overlay fixture and were replaced by the real save path. Extra-map setup identifiers are filenames while live map IDs are numeric. Companions use active native APIs; a dormant RolePlayS dynamic_parameters script was not enabled. The GrayRat template dismissed itself before actor creation in the synthetic story state; this was not treated as a production defect or bypassed.

All six supplied appearance/NPC databases load, but unique NPC quest branches, appearance in every state, every RolePlayS class, full story progression and the cooking minigame UI still need ordinary playtesting. No performance improvement claim is made. Use New Game and the normal class creation screen; do not import pre-RolePlayS saves.

Final blank-save title smoke: 7 checks pass; all sixteen addons load, six bridges install, Diagnostics and native performance hooks report healthy, preserved WASD bindings resolve, and malformed journal contexts are rejected. `mod-title.png` shows the ordinary title screen without a debug overlay. Temporary startup hooks are archived outside both runtimes; `installation.json` records delivered hashes and confirms no saves in the playable copy. All 2016 supplied reference files remain unchanged. Runtime Ruby/DLL files of the three existing addons match story-lab; accompanying release documentation can differ.
