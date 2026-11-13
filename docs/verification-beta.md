# Public Beta verification

LonaRPG B.0.10.7.5.18 / Windows x86 RGSS301 / Ruby 1.9.2. FCP 0.8.11, Diagnostics 0.2.2, Compatibility 0.1.1, LonaPerformance 0.1.13 with experimental GC off.

- Direction regressions: baseline 22 pass / 82 fail; corrected source 104 pass / 0 fail, using native skill sensors and the production projectile initializer in a private full-mod runner.
- Mandatory isolated RGSS checks: 148 pass; movement binding checks: 17 pass. Arena bitmap inspected.
- Final native title smoke: 8 pass / 0 fail. All sixteen selected addons load, six compatibility bridges install, Diagnostics reports healthy, native geometry and event-dispatch hooks are active, and updated metadata is accepted.
- Every executable Ruby source, addon metadata and numeric DLL in the public ZIPs matches the final native test runtime byte for byte. ZIP integrity and explicit file allowlists checked. Temporary startup hooks removed.
- Earlier bounded integration checks cover new Adventurer creation, companion lifecycle, effects pause/resume, quick save/warm load/cold load, region notes and separate visits across registered maps. A short user playtest reported no critical problems.

This does not establish a complete story route, every class/skill/NPC quest state, physical input acceptance or universal performance gains. Public beta testing is intended to collect that evidence. Private runtimes, game binaries, third-party mod files, saves and raw user logs are not published.

Packaging revision 2: all four archives now contain only the addon folder, to be copied manually into ModScripts/_Mods/. Archive extraction and ZIP integrity verified. Executable source, metadata and DLL bytes match the initial tested release; only installation documentation and its derived checksum manifest changed. No gameplay retest was needed. The release tag remains unchanged.

## Beta 0.8.12

Built-in adapters: 11 native cases / 187 checks. Automatic ordering: 212 isolated RGSS assertions, three native scenarios / 68 checks, and a full-set loader smoke. Required general runner: 148 checks; binding checks: 17. Final component versions pass 26 native loader checks, including built-in compatibility version and active performance hooks. Existing full-story and performance limitations remain. See integrated-compatibility.md for scope and failure guards.
