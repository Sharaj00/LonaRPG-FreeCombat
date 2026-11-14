# Beta 0.8.13 verification

Target: LonaRPG B.0.10.7.5.18, original Windows x86 RGSS301 / Ruby 1.9.2. Components: FreeCombat 0.8.13, Diagnostics 0.2.4, LonaPerformance 0.1.15. Only private runners and independent test saves were used.

- Baseline real skeleton curved arrow: diagonal landing [4,3]; reproduced defect.
- Corrected real skeleton skill launch: 3 checks, zero failures. Ordinary LongBowNormal movement samples remain cardinal.
- Real native curved-event constructors for an elite skeleton outside the continuous registry and for the player: 100 checks, zero failures, covering quadrants, ties, zero displacement, integer grid keys, native rounded distance and jump arc. Unrelated skill data is rejected.
- Native recruited companion with optimizer enabled: 13 checks, zero failures. Default blocking, optional bidirectional passage, route clearance and actual player displacement, wall and unrelated-NPC blocking, unchanged through flag/combat participation, restoring collision, and deleted-body identity cleanup.
- General RGSS runner: 148 passed; movement binding checks: 17 passed. Arena image inspected.
- Final component versions with the supported full mod set: 26 native title-loader checks, zero failures; all six adapters and geometry/event optimization hooks active. Experimental GC remains disabled.

The runtime behavior was checked before the metadata-only release version changes; the final title-loader run covers those version guards. Full story completion, every skill/class and prolonged gameplay remain manual acceptance. No universal performance claim is made. Proprietary game templates, third-party mod files, private saves and raw runtime logs are excluded from publication.
