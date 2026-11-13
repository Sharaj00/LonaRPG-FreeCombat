# Combat directions 0.8.11

Target: LonaRPG B.0.10.7.5.18 / RGSS301 / Ruby 1.9.2. The user reported close rear hits with a club, sword and spear, then explicitly requested four-direction shooting for both NPCs and the player.

## Cause and correction

The native forward hit masks include the attacker cell. Continuous hit geometry expands every positive cell by the victim radius, allowing a close rear victim to intersect that cell. For Battle_Sensor masks with forward cells and no explicit rear cells, reject victim centers behind the attack axis. Preserve non-battle perception, single-cell effects, circular attacks and intentional backward attacks. Front/side mask geometry otherwise remains unchanged; melee aim and movement retain their continuous directions.

Projectile initialization previously normalized both arbitrary aim and a native target vector into free-angle velocity. Snap the final vector to its dominant cardinal axis before setting sprite direction and velocity. Exact diagonal ties use the vertical axis, matching native facing. Player and NPC owners use the same rule; speed, range, wall collision and damage payload are unchanged.

## Focused native evidence

`tests/combat_direction_probe.rb` runs only in output/mod-compat-lab using its independently generated combined-mod SavQuick, never a player save. The real native skill sensor mine_number calls reach the live effects bridge and controlled Musketeer body. Club, short sword and wooden spear are tested against close front/rear centers across four axes and diagonal facing. Circular and explicit backward sensors retain rear hits. Production projectile initialization is exercised for player/NPC owners, inherited aim/native targeted shots, eight off-axis vectors and an exact tie. Synthetic projectile tokens isolate velocity and visible direction; this is not a full physical-input archery playtest.

Baseline 0.8.10: 22 passed, 82 failed. Fixed geometry: 104 passed, zero failed. Evidence: output/combat-direction-0.8.11-verification/. Previously completed unrelated story/effect suites were not replayed. The shared geometry change also requires the project lab verification before delivery.

Compatibility 0.1.1 changes only its version and exact FCP dependency to 0.8.11. The six integration bridges are unchanged. Full story branches, physical shooting input and every projectile skill remain manual acceptance work.
