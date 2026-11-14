# Skeleton arrows and optional companion passage (Beta 0.8.13)

Changes delivered in Beta 0.8.13, following Beta 0.8.12.

## Companion setting

Close the game and edit ModScripts/_Mods/FreeCombatPrototype/settings.rb. Set COMPANION_COLLISION = false to let the player and recruited followers pass through one another on continuous-control maps; restart afterward. The default true preserves blocking. Preserve this settings file when updating, like LonaPerformance/settings.rb.

A passable companion must be a live registered follower whose native actor master is the player. Friendly bystanders, enemies and other NPC pairs remain solid. Walls and scripted/native movement rules remain unchanged. Collision avoidance and path routing use the same pair predicate; actor bodies, hit detection and damage participation remain intact. No actor through flag is changed. Registry identity lookup is removed when the actor is deleted/replaced.

## Skeleton arrow defect

UndeadBow and UndeadEliteBow have LongBowNormal and NpcCurvedArrow. Normal arrows use Game_PorjectileCharacter and the continuous projectile initializer, already cardinal. The curved arrow uses a user-redirected SkillDummy event with a native jump_to(target.x,target.y), bypassing that initializer. The earlier initializer-only check did not cover this path.

The baseline real skeleton launch moves the curved event by [4,3]. The new bridge snaps this projectile-effect jump to one axis, retaining the native rounded distance and jump arc. The landing coordinates stay integers for the native tile hash. Scope is limited to owned skill data with projectile_type 2 and a user-redirected effect; character movement, normal projectiles and unrelated jumps are left to their existing paths. For native casters outside the continuous NPC registry, the active map bridge also handles this effect without taking over the caster's movement.

Private evidence is in output/skeleton-companion-verification/. Actual skill launches use an independently generated SavQuick; no player save is tested. Extended checks construct native curved events for an elite skeleton and the player across directional quadrants and ties. Companion checks use real native recruitment and continuous bodies with the optimizer enabled.

Known boundary: companion passage is for the continuous player/follower pair. It does not globally disable actor collision or rewrite native story routes, overworld movement, combat targeting or faction rules. Native jump arcs remain subject to the game's own animation and page lifecycle.

## Verification

The required private RGSS runner passes 148 general checks and 17 movement-binding checks; arena.bmp was inspected. Native controlled skeleton launch: 3 passed, companion passage: 13 passed, extended elite/player curved constructors: 100 passed, all with zero failures. Ordinary arrow movement samples remain cardinal. These tests are focused engine checks, not a complete story playthrough.
