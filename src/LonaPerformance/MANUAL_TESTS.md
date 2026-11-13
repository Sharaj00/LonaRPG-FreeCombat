# Manual acceptance - 0.1.10 Early Access

Status: **Pending**. Record each result as not tested / passed / failed, with settings, location, duration and any logs. Previous automated checks do not mark these items passed.

- [ ] Standalone installation: FreeCombat absent/disabled; ordinary new game, map transitions, menus and optional GC. FreeCombat geometry/dispatch should be inactive.
- [ ] Optional integration: compatible FreeCombat detected; unsupported versions/interfaces skipped without disabling Lona Performance.
- [ ] Native mod manager detects the addon, saves activation, and disabling/restarting removes its effect.
- [ ] Default settings: startup, F6/F7, entering/exiting free combat, pause/resume and native overworld travel.
- [ ] Courtyard and both tavern floors: collisions, doors, stairs and local/scripted transfers.
- [ ] Mass combat: hostile NPCs approach, navigate obstacles, attack, take damage, die and leave the registry normally.
- [ ] Melee/ranged attacks, effects, summons, companion commands and crowd collisions retain expected behavior.
- [ ] Menus, dialogues, capture/release and scripted events do not leave actors or GC in the wrong state.
- [ ] Long sessions and repeated map transitions: memory use, crashes, visible glitches and rare frame stalls.
- [ ] Compare addon disabled/enabled under the same conditions; include frame-time tails, not only average FPS.
- [ ] Check the previously observed paused-courtyard P99 concern.
- [ ] Toggle scalar, native and dispatch optimizations independently, restarting after each change.
- [ ] Ordinary save/load outside the protected F7 test mode, using disposable save copies only.
- [ ] Other installed addons: record exact versions and loading order.
- [ ] Optional separate GC experiment only after default acceptance: test 16/30 independently, memory growth, pause/menus/transfers and resource cleanup. Keep disabled if behavior or tail latency worsens.

Early Access feedback should distinguish a crash, behavior difference, visual issue, average slowdown and isolated long frames. Retain the original installation as the reference.
