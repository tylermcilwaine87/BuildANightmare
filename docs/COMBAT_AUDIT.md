# Combat audit — 21 Oct 2026 (before the UFC × For Honor rebuild)

Backup of this exact state: `Documents\BuildANightmare-Backups\BuildANightmare_2026-10-21_before-combat-rebuild.zip`
(also git tag `backup-2026-10-21-before-combat-rebuild`).

## How animation works in this game right now (honest summary)

- Every move is a **keyframed pose** (joint angles at set times) written in `HandlerPoses` /
  `NightmarePoses` / `BossPoses`.
  - In a live game they're played by code.
  - Some have been **exported to real KeyframeSequence assets** (`src/shared/Animations/*.rbxm`). In Studio these play through Roblox's **Animator**, and they open and edit in the Animation Editor.
  - **None are published to Roblox yet.** Publishing needs your go-ahead each time; then the ids go into `AnimationDefinitions` and every server plays the assets.
- **What I can and can't do:** I author keyframes by hand, as numbers, and check them by measuring in Studio (where the fist or foot is on the contact frame, how far from the target). I can't use motion capture, Blender or a human animator's eye. So my animations are real, editable assets with measured contact, but they're **hand-keyed**. For the very highest polish, an animator could refine them in the Animation Editor; everything I make is a clean starting point for that.

Legend: **Asset** = exported KeyframeSequence (plays through Animator in Studio). **Code** = keyframed pose not exported yet. **Generic** = no move-specific animation; a shared procedural motion plays. **Contact ✓** = measured in Studio, the striking limb reaches the target on the hit frame.

## Player (Handler)

| Move | Animation | Contact | Target reaction | Verdict |
|---|---|---|---|---|
| Jab / Cross / Hook / Overhand (P P P P) | Asset (Handler.rbxm), Hit markers | ✓ (Stage 1) | Nightmares/enemies: small procedural flinch. Players: **none** | Keep; rebuild into the new stance/footwork + directional system |
| Uppercut | Code | not measured | flinch | Rebuild |
| Head kick, 1-2-3 head kick | Code (rebuilt today) | ✓ head height | flinch | Keep, export |
| Spin kick (K K K) | Code (rebuilt today) | ✓ chest | flinch / knockdown | Keep, export |
| Head Hunter (step back → K) | Code (rebuilt today) | ✓ head height | flinch | Keep, export |
| Leg kick, knee, teep | Code | **not measured** | flinch | Rebuild |
| Superman punch (step back → P) | Code | **not measured** | flinch | Rebuild |
| Drop kick (+ sprint) | Asset | measured earlier | ragdoll | Keep |
| Scythe ×3, blade ×4, whip ×2, spear throw, magnet | Code + weapon physics | **not measured** | flinch | **Not on par** — rebuild later or cut (your call) |
| Dive, step back, side dodges | Asset (dodges) / Code | n/a | n/a | Keep; add slips / ducks / rolls |
| Guard | one static hold pose | n/a | — | **Not on par**: no directions, no parry. Replace |
| Get-ups (front / back) | Code | n/a | — | Keep |
| Being hit (player) | **nothing** except ragdoll on big hits | — | — | **Missing** |
| Run / walk styles | Code | n/a | — | Keep; add a locked-on fighting footwork set |

**Missing entirely:**
- directional guards
- parries
- feints
- posture / stagger
- clinch, grabs, throws, takedowns
- fighting-stance footwork (strafe, circle, back up guarded)
- player hit reactions
- finishers
- the Nightmare Sync meter

**Already there and kept:**
- lock-on (Z)
- stamina (dodge and guard)
- guard break
- perfect-dodge credit
- size / armour-based knockdowns with real ragdolls and get-ups
- server-validated hits

## Nightmares

| Move | Animation | Contact | Verdict |
|---|---|---|---|
| Basic combo (Combo1/2/3) | **Generic** (arm-swing styles) | not measured | **Not on par** — rebuild per body plan |
| Heavy | Asset for Bipeds; **generic** for other bodies | ✓ (Biped) | Extend to every body plan |
| Bite, Charged Bite | Asset: lunge, jaw, clamp, thrash, rip | ✓ jaw on body | Done |
| Rusty Slash (+ left-arm mirror) | Asset | ✓ sweep | Done |
| Frost Ram, Bat Dive, Blink Dash | **Generic** "lunge" | — | Rebuild |
| Scrap Visor Beam, Tentacle Lash, Demon Rend | **Generic** "both arms" | — | Rebuild (tentacle needs a bendable rig) |
| Magnet Pull | **Generic** | — | Rebuild |
| Hammer Slam, Tail Sweep, Energy Overload | **Generic** | — | Rebuild |
| Reinforced Guard, Crystal Barrier | **None** (static) | — | Rebuild |
| Splinter Storm, Thousand-Eye Glare, Bastion Quake, Crystal Cataclysm, Scrap Apocalypse, Void Collapse (ultimates) | **Generic** "ultimate" | — | Rebuild |
| Footwork (step back / sidestep / dash in) | **Generic** hop / lunge | — | Rebuild |
| Hit reactions | Procedural flinch + ragdoll + get-up asset | — | Rebuild into light / medium / heavy |

18 of the 21 Nightmare abilities have no animation of their own.

## Bosses

| Boss | Attacks | Animation |
|---|---|---|
| Scrap Titan | Ground Slam | **Asset** (real leap, lands on the impact frame) |
| | Swipe, Magnet Pull, Scrap Barrage | **Generic** |
| Mirror Warden | Mirror Combo, Prism Beam, Reflected Slam, Shard Storm, Shatter Nova | **All generic** |
| Storm Beast | Claw Swipe, Thunder Pounce, Chain Lightning, Static Nova, Thunderstorm | **All generic** |
| Abyssal Maw | Tentacle Slam, Burrow Erupt, Ink Spit, Abyssal Inhale, Abyss Pools | **All generic** |

19 of 20 boss attacks have no animation of their own, and no boss has combos, guards, parries or feints.

## Totals

- Player: 13 moves are measured or assets; about 20 still need rebuilding or adding.
- Nightmares: 3 of 21 abilities done; the basic combo, footwork and reactions are generic.
- Bosses: 1 of 20 attacks done.
- The For Honor layer (directional guard, parry, feint, posture, stance footwork) doesn't exist yet.

## Order of work (the brief's stages)

1. ~~Audit~~ (this document)
2. ~~**One complete, polished punch combination**~~ (done, see **Stage 2 result** below):
   - the fighting stance and locked-on footwork
   - jab → cross → hook flowing without resetting to idle
   - left / right / high directional guard, with a parry
   - physical hit reactions on the target by direction and strength
   - real assets, measured contact
   - shown working **before** anything is expanded
3. For Honor mechanics across the board: feints, guard breaks, counters, posture.
4. Real combos.
5. Every Nightmare ability, one at a time.
6. All four bosses.
7. Polish, balance, test against moving enemies and players.

## Stage 2 result: one complete punch combination (21 Oct 2026)

Test it in the **Sparring Ring** next to the Training Arena: step inside the ropes, put your
fists up, lock on with **Z**. Flick the mouse **left / right / up** to choose your guard (and
the side you punch from); **LMB** punches. Right stick on a gamepad; three guard buttons on phones.

### What's in it

| Piece | Where | How it was proven in Studio |
|---|---|---|
| Fighting stance (lock on + fists = InStance), guard held High / Left / Right | `StanceController`, `HandlerAnimator.applyStance`, poses `GuardHigh/Left/Right` | Front-view frames: each guard puts the right glove(s) at the head on the right side |
| Footwork: forward / back / left / right step loops under the guard, never crossing the feet | `FightStep*` poses, blended by movement direction | Joint trace while strafing right: right hip cycles 0°→16°→0° and the knee to −40° every 0.5 s (the FightStepRight keys), back to the stance at rest |
| Punches by guard side: High = jab → cross, Left = lead hook, Right = rear hook (new) | `MeleeDefinitions.ResolveStance`, `RearHook` pose | Server log: jab, cross, hook and rear hook all accepted and landing on the side they should (`side=High/Right/Left`) |
| Contact | Hook / RearHook `Contact = 2.65`, `Lunge = 2.2` | Frame trace of the glove vs the sparring fighter's head: **6 of 7** unparried hooks touch the head (0.00–0.05 studs) on the impact frame (0.17 s). Before the fix 3 of 4 stopped 0.4–1.0 short |
| Directional defence: block = guard on that side; **parry** = guard moved there ≤ 0.22 s before impact (or re-committed); guard break when stamina runs out | `FightRules`, `CombatService:Defend`, `HandlerService.SetGuardDir` | 4 of 4 jabs into the fighter's high guard → `Blocked` (chip damage). Its hooks on your open side land; a timed guard change parried every side hook (`Parried side=Right/Right/Left`). The fighter parried one of my rear hooks |
| Reactions: block, parry, parried (attacker knocked off line), blocked recoil, hit high / left / right (light + heavy), stagger | poses `Block*`, `Parry*`, `Parried`, `BlockedRecoil`, `Hit*`, `Stagger` | Scrubbed frame by frame; each reads correctly (head snaps the right way, arms fly open on heavy hits) |
| Flow: strikes chain without going back to idle; the guard returns smoothly | snapshot blend in `HandlerAnimator` | Elbow trace through a jab: the guard comes back 132°→90° over 0.15 s. The one-frame drop to idle at the start and the dip at the end are gone |
| Sparring partner: blocks, reads, parries, throws its own combos with tells (red sigil side), non-lethal | `FighterService` | Live rounds; 0 script errors (client + server log) |
| Duel camera: over your right shoulder when close, so you can see your opponent | `Config.LockOn.Duel*` | Before: the fighter was hidden behind your body. After: both fighters in frame |
| Your Nightmare waits outside the ropes, on your left while you're in stance (out of the camera) | `NightmareAIService.Follow` | Seen in frame |

### Animation assets

`src/shared/Animations/Handler.rbxm` (17 KB) now holds **30** KeyframeSequences, rebuilt from
the tuned code: Jab, Cross, Hook, Overhand, DropKick, DodgeLeft, DodgeRight, **RearHook,
GuardHigh, GuardLeft, GuardRight, FightStepForward/Back/Left/Right** (legs only), **BlockHigh/Left/Right,
ParryHigh/Left/Right, Parried, BlockedRecoil, HitHighLight, HitHigh, HitLeftLight, HitLeft,
HitRightLight, HitRight, Stagger**. They open in the Animation Editor.

### Honest limits

- The animations are **hand-keyed and measured**, not motion-captured, and **not published**. Until they're published (your go-ahead, one at a time), a live server plays the identical code keys.
- Reactions and the held stance always run from the code keys; the assets are their editable twins.
- Head kick, spin kick and Head Hunter are still code-only. Their Whoosh markers fall between keys, so exporting them would change measured moves; that's for Stage 3.
- A hook can still miss by 0.5–1 stud if the target's head is mid-reaction (turning). Nothing re-aims the arm at a moving head yet.
- Not built yet (later stages): feints, posture, combos beyond jab-cross / hooks, kicks in stance, clinch, finishers, the Nightmare Sync meter, Nightmare and boss styles.
