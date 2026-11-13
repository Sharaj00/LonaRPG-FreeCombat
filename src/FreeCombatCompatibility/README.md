# Free Combat Mod Compatibility 0.1.1

Local compatibility bridges for FreeCombatPrototype 0.8.11 and the supplied mod
set on LonaRPG B.0.10.7.5.18 / Windows RGSS301 / Ruby 1.9.2.

Start a **new game** with RolePlay-S. Its character-class selection and actor
stats are part of the save format; this addon does not migrate pre-RolePlay-S
saves. Choose the class through RolePlay-S's ordinary creation screen.

## Load order

1. RolePlayS 0.7.9.3.
2. The six supplied NPC/portrait mods: GrayRat, LoliMama, Milo, Musketeer,
   DedGirl and OrkindSlayerGirl (all 1.0).
3. LonaRpgCoockingExpanded 0.5.0.
4. Temper Trine 1.5.2.
5. LonaRPG_FactionClashes 0.3.22.
6. LonaRPG_RestJournal 3.5.
7. PassiveStaminaRegen (supplied legacy script, no declared version).
8. FreeCombatPrototype 0.8.11.
9. FreeCombatCompatibility 0.1.1.
10. FreeCombatDiagnostics 0.2.1 and Lona Performance 0.1.12.

Restart after changing mods. The native manager stores settings by folder name;
Temper Trine's folder is `Temper Trine`, while its internal ID is `temper_trine`.
Keep the original Game.ini version title: the native manager reads it as the
game version. Do not replace it with a custom window label.

## Bridges

- Passive stamina recovers in continuous movement and native/suspended paths,
  once per eligible frame. Combat pause freezes it. The captured passive update
  wrapper is removed only when its exact source location matches; earlier
  native/mod update hooks remain intact.
- Temper's frame-based Stage2/Stage3/activity ticks pause with combat. Native
  date-based rest/decay and dialog-pause release retain their behavior.
- Faction Clashes receives explicit E/Enter interaction intent. Attacks and
  touch triggers do not count as reward/service conversation intent while the
  continuous controller is active. Its configured action-key requirement and
  native overworld behavior remain available.
- Failed or rejected loads restore Rest Journal's visit and RolePlay-S's class
  context alongside Free Combat's native-world rollback.
- RolePlay-S backward dodge uses Free Combat's collision/body bridge for
  controlled actors executing a native effect; ordinary native jumps retain
  their original behavior and direction.
- Rest Journal resolves registered extra-map notes and canonical map identities.
  The added RolePlay-S regions receive their wild-map rules and retain separate
  visits instead of sharing the numeric conversion of a filename.

This addon has no test levels, debug keys, overlay or separate log writer.
Free Combat Diagnostics owns the optional F9 panel and F11 issue markers.

## Scope and evidence

See `docs/mod-compatibility-0.1.0.md` in the project and the local
`output/mod-compat-verification/` evidence. The supplied mod folders are retained
as references. Their scripts/assets and game runtime are not included in this
addon ZIP. No upstream redistribution license was established.

Verification uses independently generated characters and saves. It does not
establish a complete story route, every RolePlay-S class, every unique NPC quest
state, cooking-minigame input or third-party performance gains. Continue ordinary
playtesting with Diagnostics enabled and mark problems with F11.

Version 0.1.1 updates the required Free Combat version to 0.8.11. Bridge behavior is unchanged. See docs/combat-directions-0.8.11.md for the directional combat fixes and upgrade evidence.
