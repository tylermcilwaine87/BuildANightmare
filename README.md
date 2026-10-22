# BUILD A NIGHTMARE — v0.11.0 (the Nightmare Gym + a real Bite)

## The Nightmare Gym: AFK training (v0.11.0)

A real place in the world. **The lift** stands on the east side of the Forge, between the Mirror gate and the Colosseum: freight doors, hazard stripes, "NIGHTMARE GYM · SUBLEVEL B2". Walk up and press **E**.

- **The way in:** the camera glides to the doors and they grind open. It pushes into the black lift shaft, where the server moves you and your Nightmare. You come out of the gym's own lift looking down the hall, the camera sweeps over it, then settles on your bay as your Nightmare walks in from the lift to its bag. **The way out** is the same in reverse: back into the gym's lift, out of the Forge's doors (they close behind you), and the camera returns to you.
- **The hall** (an underground monster gym):
  - **Bays:** six training bays, each with a gantry and heavy bag, a mirror, a mat, your Handler's bench, a reward screen and a reward crate.
  - **Centre aisle:** reinforced, with a Nightmare-sized bench press, a dumbbell rack, a 500 kg dumbbell, a cable machine, reinforced dummies and the "Titan Bell".
  - **Walls:** lockers, banners and trophy cabinets.
  - **Display cases** showing each top tier's real odds.
  - **A live statistics wall:** Nightmares training, rewards earned here, and the last big drop.
  - **Overhead and air:** trusses, ducts, spinning fans, hanging lamps and steam.
- **It actually trains.** While you're in, its AI is paused and it works the bag in a fighting guard:
  - jab-jab-cross
  - jab-cross-hook
  - jab-hook-overhand
  - a body hook into an uppercut
  - single power overhands
  - footwork with feints and slips
  - a rest every 5–8 routines (hands on knees, breathing, shaking out)

  Armless Nightmares do jaw work (bites) on the bag instead. The bag hangs at **your** Nightmare's shoulder height, and it stands where its punches land. In Studio the cross and overhand sink into the leather, and the jab and hook meet its surface.
- **The bag swings for real.** It's a damped pendulum on every client, kicked by the strike markers in the animation, scaled per strike (`GymDefinitions.Strikes`). Measured in Studio: a combo knocks it about 1.6 studs off centre, then it settles back over a few seconds. Hits also bring dust from the leather, a thump, chain rattle on heavy shots, and a little camera shake.
- **Camera director:** the camera changes angle when your Nightmare changes exercise (side, over the shoulder, three-quarter front, low hero, wide).
- **Rewards** (`GymDefinitions`, all rolled on the server):
  - **Timing:** one roll every 90 s of training.
  - **Tiers and real odds at 1x luck:** Common 62%, Uncommon 24%, Rare 9.5%, Epic 3.6%, Legendary 0.8%, Mythic 0.09%, Secret 0.01%. The panel always shows the true % at your current luck.
  - **Payouts:** Common pays coins, Uncommon pays coins plus essence, Rare/Epic/Legendary pay a part of that rarity. Mythic and Secret pay a mutated Legendary part, coins and a title ("Iron Will" / "Gym Phantom").
  - **Saving:** anything Rare or better saves immediately. Lifetime time, rewards, best tier and titles are kept in the profile.
- **Reveals:** Rare and better make the crate glow in the tier's colour. The camera eases in, the name appears as a silhouette and then in colour, the lid flips open and sparks burst out (bigger, with a flash, for Mythic and Secret). **Space** or **Skip** skips. Common and Uncommon tick in at the bottom of the screen and on your bay's screen.
- **Boosts** (coins only, 15 min, real time): 2x Luck (250), 3x Luck (600), Fast Training x1.5 (200). Luck boosts don't stack: the strongest one applies. There's no Robux boost yet; that needs a Developer Product you create.
- **Balance:** an hour in the gym is about 40 rolls, mostly coins. Fighting bosses stays the faster way to progress.
- **Panel:** next-reward countdown, luck/speed, active boosts, this session (time, count, best), all-time totals and titles, recent rewards, the odds table, boosts, and **LEAVE THE GYM** (or press B on a controller). **Hide** (H) shrinks it to a small countdown bar.
- **Sound slots** (empty until you add ids): `GymDoor`, `BagHit`, `BagHeavy`, `ChainRattle`, `GymReward`, `GymRevealRare`, `GymRevealMythic`, and the `GymAmbience` ambience.
- **Studio test hook:** `game.ServerStorage.DevBridge:Invoke("GymService", "DevRollNow", player, "Mythic")` rolls the next reward now (optionally forcing its tier). It's Studio only.

## Jab, elbow, leg sweep (v0.11.2)

- **P P K is now the Elbow into Leg Sweep:**
  - **Jab.**
  - **Devastating elbow:** step in and turn the whole body through a rear horizontal elbow, 12 damage (the cross was 7) and a big stagger. It never knocks down, so they're still standing for the sweep. Measured on the hit frame: the elbow point is on the centre line at jaw height, 2.0 studs out.
  - **Leg sweep:** drop into a deep crouch on the lead leg and scythe the straight rear leg through their ankles (13 damage, unlocks at level 2). Measured: the foot is at ankle height (0.4 above the floor) 2.1 studs out on the hit frame. A whole-move scan every 0.025 s keeps both feet within 0.12 studs of the floor line.
- **The sweep flips them.** Instead of the usual backwards tip-over, a swept body is popped up and rotated heels over head (`Config.Ragdoll.Sweep`). Measured on a Scrapling: launched at 48 studs/s, spinning 11 rad/s, a full turn in the air, landing flat on its back about 0.35 s after the hit. Bigger bodies fly lower, and the usual knockdown rules (armour, size, bosses, 5 s cooldown) still apply.
- **Combos stay on one enemy.** Every follow-up strike of a combo goes to the enemy the combo opened on, as long as they're alive and in reach, even if you swing the camera onto someone closer mid-combo. A new combo, or your lock-on target, picks again. Tested with two Scraplings: with the camera whipped onto the other one, the elbow and hook both stayed on the first; a fresh jab after the combo ended went to the new one.
- **Combos menu:** "The 1-2" is now **Jab & Elbow**, "1-2-3" is **Jab, Elbow, Hook**, and the 1-2 Low Kick is replaced by **Elbow into Leg Sweep**. The new ones are discovered fresh. The cross is still there on K P.

## Bite clamp, spin kick fix, more gym moves (v0.11.1)

- **The Bite clamps and rips:**
  - **Clamp:** the jaws lock on and the bitten enemy is held in the Nightmare's mouth for about 1.5 s, thrashed side to side in step with the head, unable to attack. It takes 55% of the damage here.
  - **Rip:** the head tears away to the left with the rest of the damage, throwing the enemy hard (Heavy, so it can knock them down). Measured in Studio: clamp hit at +0.30 s, held at the mouth until +1.78 s, then flung 17+ studs.
  - **Bosses and players' own characters** aren't lifted; the Nightmare still clamps on and rips.
  - **Charged Bite** does the same, slower and harder.
  - **New sound slots:** `BiteGrind`, `BiteRip`.
- **Spin kick fixed:** it was hitting with your leg nowhere near them. Measured on the old hit frame, the foot was *behind you at knee height*, and the lunge stopped 3.4 studs from their body when your leg only reaches about 2.4. It's now a jumping spinning back kick (back turned, heel driven straight back at chest height), and the lunge carries you in until the heel lands. Measured on a training dummy: heel on its chest, 0.1–0.3 studs into its body on the hit frames.
- **Gym, more moves:** two-legged Nightmares now also throw a teep, a roundhouse, clinch knees (grabbing the bag) and a spinning back kick. They step to each kick's own range first: measured foot-to-bag at contact −0.5 to +0.35 studs. They also practise **their own abilities** at random from their loadout (abilities without an animation yet still strike the bag at their real timing, with sparks), and the Bite clamps the bag, shakes it and rips it away.

## The Bite, finished (v0.11.0)

- **The lunge** is driven frame by frame on the server, so every player sees it on time: measured, it covers 3 studs by the hit frame (it was 0.1).
- **The jaws reach the target.** The lunge stops where the **mouth** meets the target's body, and the bite only goes off once it can reach. Measured jaw-to-body gap at the hit: −0.1, +0.1 and −0.2 studs; before the fix it could be 3 studs of air.
- **The jaw** gapes wide on the lunge, snaps shut on the hit frame, holds through the tear and opens on the release.
- **Rusty Slash** is a real sweep. The claw tip goes from behind-right, to dead ahead on the hit frame, to across the left. The left-arm version is an exact mirror.
- **Animation assets:** both are in `Nightmare.rbxm` (Ability_Bite, ChargedBite, RustySlash, RustySlash_Left).

## Combat overhaul: Stage 1 demonstration (v0.10.0)

Every Stage 1 move is a real, editable **KeyframeSequence** in `src/shared/Animations/` (in Studio: `ReplicatedStorage > Shared > Animations`). In Studio the game plays them through Roblox's **Animator** (registered locally; nothing is published). Each was checked in a playtest: at its key frames the asset puts the fist / foot / head within **0.000–0.017 studs** of the tuned version. Event markers inside each animation (`Hit`, `Whoosh`, `StepL/R`, `Land`) drive sound and dust on the exact frame. In Studio, a check warns if any move's server hit time doesn't sit on its `Hit` marker.

| Animation | Used by | Asset (editable) | Status | Hit synchronisation |
|---|---|---|---|---|
| Jab, Cross, Hook, Overhand (the P-P-P-P combo) | Your character (R15) | `Handler.rbxm` → Jab / Cross / Hook / Overhand | Custom, keyframed, measured; not published | Server hit 0.11 / 0.14 / 0.17 / 0.34 s = `Hit` markers; measured hits 0.10–0.35 s |
| DropKick | Your character | `Handler.rbxm` → DropKick | Custom (earlier build, now an asset with markers) | Hit 0.26 s, Land 0.82 s |
| DodgeLeft / DodgeRight (side dive) | Your character | `Handler.rbxm` → DodgeLeft / DodgeRight | Custom, new | Launch → shoulder roll → land facing them (measured: 0° off, range held at about 7) |
| Biped heavy haymaker | Any Biped Nightmare | `Nightmare.rbxm` → Nightmare_Biped_Heavy | Custom, new | Plays at the speed that lands its Hit frame on the server's windup (measured hits 0.47–0.48 s for a 0.45 s windup) |
| Get-up after a knockdown | Every Nightmare / enemy | `Nightmare.rbxm` → Nightmare_Common_GetUp | Custom, new | Starts when the ragdoll ends |
| Scrap Titan ground slam | Scrap Titan | `ScrapTitan.rbxm` → Boss_ScrapTitan_Slam | Custom, new (the Titan got hip + knee joints) | A real leap timed so the body lands on the impact frame (measured: takeoff 0.82 s, on the ground at impact) |

- **Side dodge:** when you're facing an opponent (locked on, or one in front of your camera), Shift + left/right is a side dive. You launch off the outside foot, roll over the shoulder and come up squared up to them. It circles about 9 studs around them, so you stay in counter range. Shift + forward is still the dive roll; Shift + back is the step-back.
- **Scrap Titan's Ground Slam:** a physical leaping double-fist slam: squat, spring, airborne, both fists into the floor. It throws everyone in the circle outward from the impact (a knockdown, then the get-up). On impact: a ground shockwave, rolling dust, flying chunks of floor (real physics, they never trip players), and camera shake plus a punch-in scaled by how close you are.
- **Get-ups:** floored Nightmares and enemies no longer pop straight upright. They push up off the floor and rise.
- **Effects setting:** Settings → *Impact effects* (Full / Reduced / Minimal) scales dust, debris and shockwaves. *Camera shake* and *Hit flashes* still have their own settings.
- **Sound:** slots `PunchWhoosh`, `PunchHeavy`, `Footstep`, `Land`, `BossSlam` in `AudioDefinitions.luau` (empty until you add sound ids).

### Making / changing animations (dev workflow)
1. Tune the move's keyframes in `HandlerPoses` / `NightmarePoses` / `BossPoses`. Check them in a playtest with the scrub attributes: `ScrubPose` / `ScrubTime` for your character, `NMScrubAction` / `NMScrubTime` for Nightmares and bosses. You can also tune live with `ScrubPose = "Lab"`.
2. Export (edit mode, command bar):
   `require(game.ServerStorage.DevTools.AnimationExporter:Clone()).Export("Handler", {"Jab", ...})` (or `"Nightmare"`, `"ScrapTitan"`)
3. Right-click the selected folder → Save / Export → Save to File → `src/shared/Animations/<Kind>.rbxm`.
4. To edit in the Animation Editor, or to publish one: copy a KeyframeSequence into `ServerStorage.RBX_ANIMSAVES.<RigName>` on a matching rig, Load, edit, then Publish to Roblox. Paste the id into `AnimationDefinitions` (Handler / Nightmare / Boss) and it plays everywhere, including live servers. Until then, live servers play the same keyframes from code.

## Size, armour & knockdowns (v0.9.3)

- **Size matters.** Every body has a size: the cube root of its hitbox volume. Approximate sizes: you 3.2, a Scrapling 2.8, a Biped Nightmare 3.9, bosses 9–13.
  - Hitting something smaller than you does more damage (up to +40%) and sends it flying further (up to 2×).
  - Hitting something bigger does less (down to −20%) and barely moves it.
  - Boss damage isn't size-scaled, because their health is already tuned.
- **Knockdowns are a roll, not automatic.** A knockdown-worthy hit (heavy move, ability, Ultimate, big chunk of health, or hard knockback) floors the target with a chance:

  | Target | Chance on a heavy hit (measured in Studio vs your Handler) |
  |---|---|
  | Scrapling / normal enemy | 100% |
  | Another player's Nightmare, Defence 0 | 63% (78% on a big hit) |
  | Defence 10 | 56% (70%) |
  | Defence 20 | 49% (62%) |
  | Defence 40 | 36% (45%) |
  | Defence 60 (max armour) | 22% (28%) |
  | Boss | 12%, only from a signature strike, then not again for 25 s |

  Armour (the Defence stat from its parts) and StaggerResist make a Nightmare harder to drop. Being bigger than its attacker helps too.
- **Stuns too:** a Nightmare's armour also cuts the stagger it builds up. At 60 Defence it ignores up to 30% more, and 70% is the most anything can ignore. Another player's armoured Nightmare is much harder to stun than a Scrapling.
- **Flooring a boss:** it topples slowly onto its side, its attack is interrupted, and **KNOCKED DOWN!** pops up with a camera jolt. It's back on its feet 1.8 s later and gets its bearings before swinging again. Tested on the Scrap Titan: it lay flat, stood back up at its proper height, and attacked again 1.2 s after getting up.
- Every number is in `Config.Ragdoll` (Size*, Resist, Boss).

## The Overhand (v0.9.2): one punch built properly

The fourth punch of P P P P, rebuilt from scratch and tested in Studio frame by frame (see `docs/overhand_frames.png`).

- **The motion (0.86 s):**

  | Time | Phase | What happens |
  |---|---|---|
  | 0.00 | Guard | Elbows tucked, fists by the jaw |
  | 0.13 | Load | Knees sink, weight rocks onto the rear foot, a small coil to the right; the fist stays home |
  | 0.24 | Launch | Rear foot drives, hips snap round, the body tilts hard to the lead side, the elbow comes up and out, and the fist loops over the top. It climbs about half a stud above your own head while your body drops under it |
  | 0.34 | Impact | Folded right over at the waist with the chin tucked, so your face points at the floor (measured: 60° down). Head off the centre line, the fist dropping over the top onto their jaw on the centre line (height 1.1, 2.7 studs out). The shoulder lifts to make up for the bend. Lead hand covering the temple, feet planted (hips counter-rotate so the feet don't spin) |
  | 0.47 | Follow-through | The bodyweight keeps falling through, still bent over looking at the floor (67° down), the fist carrying down and across |
  | 0.66 → 0.86 | Recover | Back up and round into the guard |

- **The hit is synchronised with the impact frame:** the server checks the hit at `HitTime = 0.34` s, the same frame the fist lands. Measured in Studio, the hit registered 0.334–0.353 s after the move started.
- **The reaction follows the force.** The blow carries a direction (`HitDir`: down, forward and across to your left). The Nightmare's body snaps that way, the head whipping further than the torso, and its knees sag. Every strike now reacts in the direction it was thrown.
- **Heavy enough, and it crumples.** An overhand knocks the target down (5 s cooldown per body), but as a CRUMPLE rather than a launch: the legs buckle and it folds down the way the blow drove it, ragdolls, then gets back up (about 1.3 s).
- **Feel on impact (your side):**
  - **Hit-stop:** your body freezes for 85 ms on the impact frame, then carries on (45 ms for light strikes).
  - **Camera punch:** the field of view snaps in 4° and eases back out with a short jolt. It follows the Camera Shake setting.
- **Sound:** new slots `PunchWhoosh` (as the punch flies) and `PunchHeavy` (the landed impact) in `src/shared/AudioDefinitions.luau`. Paste sound ids there; empty ids stay silent.
- **The guard everyone fights from** was rebuilt too. It used to look like a double-biceps flex, with fists out at shoulder width. Now the elbows are tucked to the ribs and the forearms turned in, so both fists sit by the jaw.
- **A body-twist bug, found by measuring.** On the right-hand punches the body was twisting the wrong way: the cross landed 1.5 studs off to the left, with the punching shoulder going back. The jab and cross also landed at belly height. Both are fixed.

### The animation asset (editable keyframes)

The overhand is a real **KeyframeSequence**: `src/shared/Animations/Overhand.rbxm`, which appears in Studio as `ReplicatedStorage > Shared > Animations > Overhand`.
- 7 keyframes on all 11 joints, Cubic In/Out easing, priority Action2.
- Markers `Whoosh` (0.24) and `Hit` (0.34).
- **In Studio the game plays this asset** through Roblox's Animator (`Config.Dev.PreviewKeyframesInStudio`), registered locally, so nothing is published. Measured: the fist positions match the tuned code pose to 0.01 stud at every key.
- **Live servers** need a published animation id. Until it has one, the move plays its code pose (the same keyframes, in `HandlerPoses.luau`).

**To edit it in the Animation Editor:**
1. Avatar tab → Rig Builder → R15 → Block Rig. This puts a rig in Workspace.
2. In ServerStorage, create a folder `RBX_ANIMSAVES`. Inside it create a folder named exactly like the rig (e.g. `Rig`), and copy `ReplicatedStorage.Shared.Animations.Overhand` into that folder.
3. Select the rig → Avatar tab → Animation Editor → ⋯ → Load → **Overhand**. Edit as you like.
4. To keep your edit in the project: ⋯ → Save, then right-click the saved KeyframeSequence → Save / Export → Save to File → overwrite `src/shared/Animations/Overhand.rbxm`.

**To publish it (so live servers use it):**
1. In the Animation Editor: ⋯ → Publish to Roblox. Copy the asset id it gives you.
2. Paste it into `src/shared/AnimationDefinitions.luau` → `Overhand = { Id = "rbxassetid://<id>", ... }`.
3. With an Id set, every client plays the published animation, including other players. The hit-stop pauses it the same way, and the server's hit time stays 0.34 s. Keep the `Hit` marker on that frame if you retime it.

### Studio tools used to build it (dev only)

- **Scrub:** set the workspace attributes `ScrubPose = "Overhand"` and `ScrubTime = 0.34` to freeze your character on that frame. `ScrubTime < 0` loops the move.
- **Pose lab:** `ScrubPose = "Lab"` plays the pose JSON in the `PoseLab` attribute. That lets you tune a move live from the command bar with no restart.

## The FIGHTER menu, signature moves & run styles (v0.9.1)

- **FIGHTER menu (U, the FIGHTER button, or the MENU hub):** your level and coins, plus three tabs:
  - **MOVES:** the 12 signature moves. Undiscovered ones show only a hint ("???"), so you have to find them. Pull one off for the first time and a big **NEW MOVE DISCOVERED** banner pops up. It's saved in your profile and its inputs appear in the menu.
  - **WEAPONS:** the loadout (this replaces the old ARSENAL panel; the ARSENAL button opens this tab). Put a weapon in slot 1–3, or take it off.
  - **RUNS:** goofy run styles you buy with coins and equip. Everyone sees them, and every one snaps straight into a strike the moment you attack.

    | Run | Cost |
    |---|---|
    | Charge | free |
    | Ninja | 120 |
    | Swagger | 160 |
    | Zombie | 200 |
    | Chicken | 260 |
    | Gorilla | 320 |
    | Superhero | 450 |

- **Signature moves:** One-Two, One-Two-Three, Overhand Knockdown, Low Kick, Head Kick Finisher (PPPK), Knee into Uppercut, Spin Kick, Kickboxer (KPP), Teep, **Superman Punch** (step back, then P), **Head Hunter** (step back, then K: a step-in roundhouse to the head) and Drop Kick.
- **Real closed fists:** a human hand balled up, in your avatar's skin colour and sized to your forearm. It has the back of the hand, four knuckles, the fingers curled into the palm (the pinky smaller) and the thumb wrapped across the index and middle fingers. It replaces the flat or open avatar hand.
- **Scythe held like a scythe:** the snath carries on along your forearm and the blade hooks left, so every swing sweeps a huge arc at chest height. Before this, the pole stood straight up whenever you raised your arm.
- **The counter now connects:** after a step back the dash closes the whole gap, up to 16 studs, and stops right on the target. You're no longer left swinging at air.
- **Overhand:** a real looping overhand. You dip and bend at the waist and the fist comes over the top like a hook.
- **Strikes blend:** each move flows out of the last pose instead of snapping, so punches into kicks chain smoothly.
- **Fists that fit a Roblox hand:** the hand keeps its normal size and shape, with knuckles, finger lines and a thumb on it (no more cube gloves).
- **Reaper Scythe:** a new, much bigger animation. You coil, reap and hop into an airborne whirl, and a violet trail follows the blade. The Rust Blade has a trail too.
- **Magnet vs bosses:** it zips you in to the boss, hits ×4 and staggers it hard. Training dummies (anchored) no longer drag you to them.
- **Storm Spear:** it was invisible because it had no model. It now has a real javelin in your hand (ash shaft, copper coils, steel head crackling with lightning), and the same spear flies when you throw it.
- **Weapons for everyone?** In Studio everything is unlocked so you can test (`Config.Dev.UnlockAllMovesInStudio`). Real players start with the Magnet, then get the Scythe at level 3, the Blade at 5, the Whip at 8 and the Spear at 12.

## Fists, kicks & weapons (v0.9.0)

- **Punch (LMB / R2 / ATTACK) and kick (a quick right-click / X / KICK), thrown like a UFC striker:** an orthodox stance, with the hips turning and feet pivoting into every strike. Holding and dragging right-click still turns the camera. Mix them and they combo:

  | Combo | Moves |
  |---|---|
  | P, PP, PPP, PPPP | Jab, Cross, Lead hook, **Overhand** (knockdown) |
  | K, KK, KKK | **Head kick** (UFC roundhouse, hip turning over), Leg kick, **Spin kick** (knockdown) |
  | PK, PKP | Knee, Uppercut |
  | PPK | Leg kick |
  | PPPK | **Head kick finisher** (knockdown) |
  | KP, KPP | Cross, Hook |
  | KPK | Teep |
  | Kick while running | **Drop kick** (knockdown) |
  | P or K right after a step back (X) | **Superman punch** / **Head Hunter** |

  - Presses made during a move are remembered and fire the moment it can chain.
  - Swings turn you toward the enemy you're aiming at (or your lock-on target) and step you in until the fist (or shin, or blade) lands right on them. Punches drive the whole body forward: the weight shifts onto the front leg and the arm goes to full extension.
  - **Real closed fists:** Roblox hands are flat blocks, so every character gets fists (curled fingers, knuckles, thumb across the front) in its own skin colour.
  - **Drop kick:** sprint flat out at the target with its own sprint animation, then spring off the floor laid back nearly horizontal and drive both feet in. You land on your back, sit up and get up.
  - Your guard comes up while you're locked on or trading blows.
  - Nothing is drawn in front of you; the hits themselves show.
- **Every swing hits its whole arc:** each move covers a slice of circle in front of you (a jab is narrow, a blade swing ~150°, the scythe whirl all the way round), so a full swing really goes through everything in its path.
- **Hotbar = your fists (\`) plus 3 weapon slots (1–3).** Pick which weapons you carry with the **ARSENAL** button next to the hotbar; your loadout is saved. Controller Y cycles; tap on phones.
- **Weapons hit far harder than fists, so each has charges:** after its uses it goes back on your belt, your fists come up, and it recharges (the slot shows the countdown).

  | Weapon | What it does | Uses / recharge |
  |---|---|---|
  | **The Magnet** | Hold it straight out and it drags the enemy in front of you right to you (bosses don't budge, so it drags YOU to them). You walk while it's out, and it never punches. | 1 / 15 s |
  | **Reaper Scythe** (replaces the pipe) | Huge two-handed sweeps that hit everything in front of you; the third whirls all the way round and knocks down | 5 / 24 s |
  | **Rust Blade** | Full swings straight through the target, then a cleave and a lunging stab | 8 / 20 s |
  | **Chain Whip** | A real chain: it hangs, drags and settles on the floor, folds up when you back off, and lashes out on a crack with a flash at the tip. The third lash sweeps a crowd. | 6 / 22 s |
  | **Storm Spear** | Thrown: it flies at your target and strikes with lightning (knockdown + Shock) | 1 / 10 s |

- **Unlocks by level:**

  | Level | Unlock |
  |---|---|
  | 2 | Overhand |
  | 3 | Reaper Scythe |
  | 4 | Spin Kick |
  | 5 | Rust Blade |
  | 6 | Drop Kick |
  | 8 | Chain Whip |
  | 12 | Storm Spear |

  The level-up message and GOALS list show them. In Studio everything is unlocked (`Config.Dev.UnlockAllMovesInStudio`).
- **Everyone sees your moves:** punches, kicks, dives, step-backs, get-ups and weapon holds play on your character on other players' screens too. The whip chain cracks for everyone.
- Every move has an animation slot in `AnimationDefinitions`, ready for filmed animations. Moves, combos and weapons are in `src/shared/MeleeDefinitions.luau`.

## Footwork & knockdowns (v0.8.2)

- **Step back (X, or Shift / B while moving backwards):** a quick hop straight back, still facing the fight, with a moment of invulnerability. Cheaper than the dive. Tuning: `Config.Handler.StepBack`.
- **Counter:** attack within 0.7 s of a step back and you dash straight back in with a punch or a front kick (they alternate). It doesn't wait for the normal swing timer, hits about 2× as hard and knocks back.
- **Nightmare footwork (your companion):** no more standing still trading hits. When the target starts an attack close by, it often hops back or sidesteps, then usually dashes straight back in with a hit. It dash-lunges in from just outside reach. After a combo finisher or heavy it may hop out and circle the target for a moment before going back in. AGGRESSIVE stance circles less and presses more. Tuning: `Config.Nightmare.Fight`.
- **Lock-on while possessing:** Z (or Select / LOCK) works while you possess your Nightmare. The camera sits behind the Nightmare (further back for big builds), and it strafes facing the target. Its attacks aim at the target. If you were locked on when you took possession, the lock carries straight over and the camera glides from your Handler to the Nightmare (and back when possession ends).
- **Enemy attacks track you:** a Scrapling keeps turning toward you through its swipe windup (capped at 170°/s), then commits for the last 0.18 s and lunges up to 3 studs into the swing. The red floor marker turns with it. Jogging around it no longer works; time a dive, a step back or a late sidestep instead. Tuning: `Config.Enemies.Scrapling` (TrackTurnRate, TrackCommit, StepIn).
- **Knockdowns happen far more often now:** any special move (Nightmare abilities and Ultimates, heavy attacks, boss slams), any hit with knockback ≥ 40, or a big hit (≥ 18 % of max health in one hit, or ≥ 35 % taken in a quick burst) knocks the target down. That covers Handlers, Nightmares and normal enemies like Scraplings. Bosses still never fall, and each body can be knocked down at most once every 5 s. Tuning: `Config.Ragdoll`.

## Combat feel (v0.8.1)

- **Dive (Shift / B):** a low, fast leap in the direction you're moving (forward if you're standing still) that ends in a forward roll on the floor and back onto your feet. Untouchable while airborne. Dive through stomps, slams and projectiles. Tuning: `Config.Handler.Dodge` (Speed, Hop, Duration, RollSpeed, RollDuration, InvulnerableTime).
- **Charge run:** Roblox's running legs with a code upper body on top: leaning in, fists up and pumping, like you're rushing someone.
- **Lock-on (Z / gamepad Select / LOCK button on phones):** locks onto the nearest boss (else the enemy you're looking at) and keeps you facing it. The camera glides in behind you (and glides back out on release), with no reticle. Releases when the target dies or gets too far away. Tuning: `Config.LockOn` (LockInTime, ReleaseTime).
- **Realistic ragdoll knockdowns:** a big HEAVY hit (boss slams, the Foundry press, the Maw's eruption...) throws Handlers and Nightmares away from the hit; they tumble over backwards and fall limp. Knees and elbows only bend the natural way, the neck and spine stay stiff, and limbs have muscle-like resistance. Once the body settles, a face-down or face-up get-up plays. Bosses never fall; each body can be knocked down at most once every 5 s. Tuning: `Config.Ragdoll`; joint limits are in `RagdollService` (JOINTS).
- **Dimmer Forge:** the hub's neon and lights are toned down (`World.HubNeonDim`, `World.HubLightScale`).
- **Animation slots:** every Handler move is listed in `src/shared/AnimationDefinitions.luau`. Paste an uploaded animation id into a move's `Id` and the game plays it instead of the built-in code animation.

## The new world (v0.8.0)

The old hub + portal hall is gone. The world is now one connected map you **walk**: the Forge hub in the middle and four themed routes leading out to each boss's arena (layout and region looks in `src/shared/WorldDefinitions.luau`; screenshots in `docs/map-screenshots/`).

| Route (from the Forge) | Region | Walk to the gate | Arena | Arena hazards |
|---|---|---|---|---|
| West, orange | The Rusted Expanse: checkpoint, conveyor + Crusher, crane yard, smelting pit, the Titan's footprints | ~44 s | The Titan's Foundry | steam vents, hydraulic press |
| East, violet | The Shattered Reach: floating white walkways over a mirror lake, Plaza of Echoes, mirror walls, Reflection Pool, temple | ~29 s | The Hall of Reflections | mirror beams |
| North, blue | The Storm Cliffs: a 120-stud climb, pylons with arcs, cliff fort, crystal grotto, broken rope bridge | ~34 s | The Tempest Summit | lightning strikes, wind gusts |
| South, teal | The Drowned Descent: canyon stairs, dripping cavern, flooded ruins, bone bridge | ~33 s | The Maw Cathedral | tentacle slams, abyss bubbles |

- **The Forge hub:** the Nightmare Engine tower (Crafting Forge anvil at its foot), Workshop (NW), Training Arena (NE), Hall of Nightmares with the showcase + leaderboard (SW), Colosseum (SE). Each gate is themed after its region, with a coloured conduit from the Engine, a title, and a **stone monument of that boss**.
- **Boss gates:** each route ends at a plaza outside the arena with a **Challenge altar** (opens the usual difficulty panel) and a **waystone**. The boss stands dormant inside its arena until you challenge it. The first time you reach a gate, the camera sweeps over the arena; every fight opens with a camera sweep to the boss as it wakes. After a fight you come back out at the gate.
- **Waystones (shortcuts you earn):** the waystone at a boss gate always takes you home to the Forge. The waystone at the matching hub gate wakes once you've beaten that boss, then takes you straight to its gate.
- **13 hidden relics** (1 in the Forge, 3 per route) reward exploring: +60 coins, +15 Essence, +90 XP each, with a line of lore. They're saved per player.
- **Region looks:** lighting, fog, colour grading, clouds and sky blend as you walk between regions, plus lightning in the Storm region. Moving set pieces: gears, conveyor, swinging hooks, floating shards, orbiting eyes, pulsing lights.
- **Ambience:** `AudioDefinitions.Ambience` has one looping sound per region (empty ids for now, same as the rest of the audio).
- **Several groups at the same boss:** the first group fights in the world arena; anyone else gets an identical copy far away, so nobody waits.

### Test checklist (new world)
1. Spawn at the Forge. Walk each route to its gate (follow the coloured conduit / path edges). Check nothing blocks you, coming back too.
2. At each gate: the arena reveal plays once, the dormant boss is visible inside, and the altar opens the Challenge panel.
3. Fight a boss: the intro camera sweeps to it, hazards start after about 8 s (Normal), you return to the gate afterwards, and the waystone takes you home.
4. Beat a boss, then use the hub waystone at its gate (it's locked until then).
5. Find a relic: you get a toast with its lore and rewards, it disappears for you, and it stays found after you rejoin.
6. The tutorial still flows: the Training Arena (NE corner), then the orange path west to the Scrap Titan.

## Launch checklist (what's left is in Studio / the Creator Dashboard)

Code-side review done in v0.7.6 (details in `docs/DESIGN.md` → 7f). **Note:** Studio playtests now save to separate `_Studio` DataStores, so anything you got while testing (free crafting, Studio mutations) stays out of the live game. Your live save starts fresh.

1. **Publish:** File → Publish to Roblox. Game Settings → Security → turn on *Enable Studio Access to API Services* (needed for saves + leaderboards in Studio).
2. **Server size:** Game Settings → Places → Max Players (a party is 4 and a 3v3 is 6; 12–16 is a good start).
3. **Creator Dashboard:** fill in the Experience Questionnaire (maturity rating). This is required before the game can be public. Set the genre, description, and devices (Computer, Phone, Tablet, Console).
4. **Icon + thumbnails:** a 512×512 icon and at least one 1920×1080 thumbnail.
5. **Audio:** paste asset ids into `src/shared/AudioDefinitions.luau` (empty = silent).
6. **Real multiplayer test:** a private server with friends. Try 3v3, ranked with 3+ players, and a full 4-player party on each boss.
7. **Go public:** set the experience to Public. Watch the Analytics tab (funnel, economy, BossWin/BossFail) during the first days.

## Bosses 3 and 4: THE STORM BEAST + THE ABYSSAL MAW

The Boss Portal hall now has **four** portals, easiest on the left; each boss is unlocked by beating the previous one on Normal or harder (all unlocked in Studio). Both use the Normal / Hard / Nightmare system, party scaling and revives, and each has a "Fastest" leaderboard and a weekly challenge.

| | ⚡ THE STORM BEAST | 🌀 THE ABYSSAL MAW |
|---|---|---|
| Portal | 3rd (dark stone, electric blue) | 4th (mossy stone, green) |
| Unlock / Power | beat the Mirror Warden · ☠☠☠ · 80 | beat the Storm Beast · ☠☠☠☠ · 90 |
| Creature | four-legged lightning beast, crackling mane, back spikes, forked tail (it trots) | giant worm-maw rising from the ground: rings of teeth, glowing eyes, two tentacles |
| Arena | Thunder Plateau: rocky mesa, lightning rods, storm clouds | Sunken Abyss: stone platform in a bottomless black pool |
| Attacks | **Thunder Pounce** (lands on the red circle) · **Chain Lightning** (hops between players, SHOCK) · **Thunderstorm** (bolts everywhere) · **Claw Swipe** | **Burrow & Erupt** (vanishes, bursts up under someone) · **Tentacle Slam** (long lines) · **Abyssal Inhale** (pull, then bite) · **Ink Spit** (WEAKEN) |
| At 50% | **SUPERCHARGED**: double pounces, **Static Nova** | **THE ABYSS OPENS**: dark pools that keep hurting anyone inside |
| Signature drop | **Electric Jaw** (Rare) | **Shadow Tentacle** (Rare) |

Electric Jaw and Shadow Tentacle were in the game before but couldn't be obtained; now they can.

## Phase 7 (in progress): ANALYTICS

Uses Roblox's built-in AnalyticsService ([GameAnalyticsService.luau](src/server/Services/GameAnalyticsService.luau)); all server-side and wrapped so it can never break gameplay. Studio test players are never logged.

**Where to see it:** Creator Dashboard (create.roblox.com) → your experience → **Analytics**. Data only arrives from the **published** game with real players, usually within a day.

| Report | What's logged |
|---|---|
| **Onboarding** funnel | 1 Joined → 2 Created a Nightmare → 3 Trained → 4 Commanded → 5 First Scrapling → 6 First boss → 7 Tutorial complete. Shows exactly where new players quit. |
| **Economy** | Coins / Essence / Arena Tokens earned (per boss, challenges, duels, tutorial, dismantling) and spent (crafting, per part). |
| **Custom events** | BossWin / BossFail (boss, difficulty, party size; value = seconds), DuelEnd (Casual / Ranked / Team NvN, result, reason), MutationFound, PartCrafted, ChallengeComplete, LevelUp (value = level). |

## Phase 7 (in progress): MOBILE + CONTROLLER

- **MENU hub:** one screen of big tiles (Workshop, PvP, Party, Goals, Codex, Settings, Summon/Recall). Phones: the **☰ MENU** button. Controller: **D-Pad Right**. Works on PC too.
- **Phones:** the top bar is compact (**☰ MENU · BUILD · RECALL**) so it never runs into the status panel; every menu panel grows to almost full screen on small screens.
- **Controller:** **B** closes the open menu (top-most first); every menu puts the selection on a button when it opens; the controller hint line lists the new buttons.

### How to test
- **Phone:** Test tab → **Device** (Device Emulator) → pick a phone in landscape → Play. Clicks act as taps. Check the compact top bar, the MENU hub, and that each menu fills the screen and its buttons are tappable.
- **Controller:** Test menu → **Controller Emulator**, or plug in an Xbox / PlayStation controller before pressing Play. D-Pad Right = MENU, the D-Pad / left stick moves between buttons, A presses, B goes back.

## Phase 7 (in progress): SOUND + MUSIC

The whole audio system is in; **you add the sounds** in ONE file: [AudioDefinitions.luau](src/shared/AudioDefinitions.luau). Empty ids are skipped, so the game simply stays silent until you fill them in.

**How to add a sound:** Studio → **Toolbox** → **Creator Store** → **Audio** → search (e.g. "punch", "explosion", "sword") → preview → right-click → **Copy Asset ID** → paste it as `Id = "rbxassetid://<number>"`. Prefer sounds uploaded **by Roblox** (free to use in any game; most other people's audio is private and won't play).

| Group | Keys |
|---|---|
| Combat (in the world, fades with distance) | Hit, HeavyHit (25+ damage), Block, GuardBreak, Stagger, Defeated, Shock, Shield, Slam (impacts), Projectile |
| Alerts | Warning (red telegraph appears), Ultimate, Possess |
| Bosses | BossIntro, BossPhase (Overdrive / Mirror Cracks), Victory, Defeat |
| Rewards | RevealUncommon / Rare / Epic / Legendary, LevelUp, ChallengeComplete, Craft |
| PvP / UI | DuelBell (round start), Click (every button), Toast |
| **Music** (looped, cross-fades) | Hub, Boss, BossOverdrive (after the phase change), Duel |

Volumes follow **Settings → Music / Sound effects**. Each sound has its own Volume, random Pitch range (so repeated hits don't sound robotic) and Cooldown (so 10 hits at once aren't deafening).

## Phase 7 (in progress): SETTINGS

Press **K** or the **⚙** button (left of BUILD). Everything applies instantly and is saved to your profile ([SettingsDefinitions.luau](src/shared/SettingsDefinitions.luau)):

| Setting | Options |
|---|---|
| Music volume / Sound effects volume | 0–100% (used by the audio coming next) |
| Camera shake | Full · Reduced · Off |
| Hit flashes | On / Off |
| Damage numbers | On / Off |
| Other players' Nightmares (outside fights) | On / Off: hides them and their health bars for performance; always shown in your boss fights and duels |
| Control hints (bottom left) | On / Off |

> *Your monster. Your creation. Your nightmare.*

- Tuning numbers: [src/shared/Config.luau](src/shared/Config.luau)
- Parts: [src/shared/PartDefinitions.luau](src/shared/PartDefinitions.luau) · Abilities & Ultimates: [src/shared/AbilityDefinitions.luau](src/shared/AbilityDefinitions.luau) · Status effects: [src/shared/StatusDefinitions.luau](src/shared/StatusDefinitions.luau) · Bosses: [src/shared/BossDefinitions.luau](src/shared/BossDefinitions.luau)
- Design & architecture: [docs/DESIGN.md](docs/DESIGN.md)

## How to run
1. Double-click **`START ROJO.bat`** and leave the black window open.
2. In Roblox Studio, open **Build A Nightmare** from Recents. **Don't** open it from the folder.
3. Click **Plugins → Rojo → Connect**.
4. Press **▶ Play**.

---

## Phase 6: THE NIGHTMARE SHOWCASE

A row of **8 dark-steel pedestals with a blood-red glow** just south of the Workshop (under the gold "NIGHTMARE SHOWCASE" sign). Every player in the server gets one with a life-size, frozen copy of their **active Nightmare** (mutation looks and sparkles included); it updates within a few seconds when they change builds. The label shows "Name's Build · ★ RESPECT · archetype · Power".

- Press **E** (Inspect) at a pedestal: the card shows every part (with mutations), Q / E / G abilities, stats and a **GIVE RESPECT ★** button.
- One respect per player per day, never your own. The owner gets "★ X gave your Nightmare RESPECT!". Saved (`profile.Showcase.Likes`, schema v9).
- **MOST RESPECTED NIGHTMARES** joins the Hall of Nightmares board.

### Showcase test (2 players)
| # | Do this | Expected |
|---|---|---|
| 1 | Walk to the Workshop, then south | Two occupied pedestals with your Nightmares and labels. |
| 2 | Player1: change the active build in the Workshop | Player1's statue changes within ~4 s. |
| 3 | Player2: E at Player1's pedestal → GIVE RESPECT ★ | "You gave Player1's Nightmare respect!"; Player1 gets the toast; the label shows ★ 1 RESPECT. |
| 4 | Player2: try again | "You already gave this Nightmare respect today." |
| 5 | Inspect your own pedestal | No button: "That's your own Nightmare. Earn respect from others!" |

## Phase 6: TEAM DUELS (2v2 and 3v3)

Party up (**L**), then as the **party leader** press **P**: every player row gets a **TEAM 2v2** / **TEAM 3v3** button (matching your party size). Challenge another party's **leader**; both parties must be the same size (2 or 3). Their leader gets "X's party challenges your party to a 3v3 Team Duel!". Team duels are **Best of 3**, casual (normal duel rewards; ranked stays 1v1).

- A player is **OUT** for the round when their Nightmare is defeated or their Handler is knocked out twice. Out players wait on their team's pad: frozen, untouchable, their Nightmare stops. **A team loses the round when every member is out.** Everyone comes back fresh next round.
- No friendly fire. Teammates spawn side by side on their pad; enemies get the red outline (not players who are out).
- Time-out: the team with the higher average remaining health wins the round.
- **FORFEIT** forfeits for your whole team. A player who **disconnects** is just out and the team plays on (a whole team gone = forfeit).
- Scoreboard: "Standing — Your team 2/3 · Enemy 1/3".
- 1v1 duels play exactly as before (being out = losing the round).

### Team duel test (Studio: Server and Clients, **4 players** for 2v2, 6 for 3v3)
| # | Do this | Expected |
|---|---|---|
| 1 | Player1 invites Player2 (L); Player3 invites Player4 | Two parties of 2. |
| 2 | Player1: P → TEAM 2v2 next to Player3 | Player3: "Player1's party challenges your party to a 2v2 Team Duel (Best of 3)!" |
| 3 | Player3: ACCEPT | All 4 in the arena, teams side by side. Banner "2v2 TEAM DUEL · Team Player1 vs Team Player3". |
| 4 | Defeat one enemy Nightmare | "PLAYERX IS OUT"; scoreboard "Enemy 1/2"; that player can't move or be hit. |
| 5 | Defeat the other one | "TEAM PLAYER1 WINS THE ROUND"; next round everyone is back. |

## Phase 6: RANKED PvP

Press **P** → the **RANKED** box → **FIND MATCH**. The matchmaker pairs you with the closest-rated player who is also searching (range starts at ±100 and widens 25 per second, up to ±800; no instant rematch with the same opponent). Ranked matches are always **Best of 3** with the 100 Power budget; normal duel rewards still apply.

- **Rating** starts at 1000 (Elo: beating stronger players is worth more). The first 5 games are placement games and move it faster.
- **Ranks:** Bronze < 900 ≤ Silver < 1100 ≤ Gold < 1300 ≤ Platinum < 1500 ≤ Diamond < 1700 ≤ **Nightmare**.
- **No dodging:** forfeiting or leaving a ranked match is a loss for your rating.
- Starting a boss fight or a casual duel takes you out of the queue.
- A **HIGHEST RANKED RATING** board is on the Hall of Nightmares.
- Same-server matchmaking for now (cross-server would need MemoryStore + teleports). Rules: [RankDefinitions.luau](src/shared/RankDefinitions.luau), queue: [RankedService.luau](src/server/Services/RankedService.luau). Save schema v8.

### Ranked test checklist (2 players)
| # | Do this | Expected |
|---|---|---|
| 1 | Both: **P** | RANKED box: "SILVER 1000", "0 W · 0 L · 0 D · placement 0/5", FIND MATCH. |
| 2 | Player1: FIND MATCH | "Searching... 0:03 · rating range ±175", button says CANCEL SEARCH. |
| 3 | Player2: FIND MATCH | Within a second: "RANKED DUEL · Player1 (SILVER 1000) vs Player2 (SILVER 1000) · Best of 3". Scoreboard says RANKED. |
| 4 | Finish the match (or FORFEIT) | Winner: "RATING +24 → SILVER 1024"; loser: "RATING −24 → SILVER 976" (placement games swing 24 at equal ratings). |
| 5 | Search again, then CANCEL SEARCH | "You stopped searching." |

## Phase 6: LEADERBOARDS

The **HALL OF NIGHTMARES** board (a tall dark board with purple glowing posts) stands just outside the Forge ring, south-west of the spawn: turn around from the Forge's burning heart and look left. It cycles every 8 s through five top-10 boards: **Highest Level · Most Boss Wins (Normal+) · Most PvP Wins · Fastest Scrap Titan · Fastest Mirror Warden** (best win time on any real difficulty).

- **Global** (all servers) via OrderedDataStores. Values are written only when they change (every 30 s and when you leave), and only for real, saving players: Studio test players (Player1, Player2…) never reach the global boards.
- If the global boards can't be read (Studio without API access, Roblox outage) the board says **THIS SERVER** and ranks the players who are here instead.
- Tuning: `Config.Leaderboards` (bump `StorePrefix` to reset the boards). Code: [LeaderboardService.luau](src/server/Services/LeaderboardService.luau).

## Phase 6: PARTIES + co-op bosses

Press **L** or the blue **PARTY** button. Invite anyone in the server (up to **4** players); they get an ACCEPT / DECLINE pop-up (20 s). The leader can KICK; anyone can LEAVE (if the leader leaves, the next member leads). Party members' names and Handler health show on the left of the HUD.

**Co-op bosses:** only the **leader** can press FIGHT; every party member who is free (not in a duel / another fight, not knocked out) is brought into the same arena. Boss health scales with party size: ×1.65 for 2, ×2.3 for 3, ×2.95 for 4. Everyone gets their own loot roll and challenge progress.

**Comebacks (party revives)**, shared by the whole party and shown on the boss bar:

| Difficulty | Revives | Wait |
|---|---|---|
| Normal | one per party member | ~8 s, then ~12 s, then ~16 s |
| Hard | 1 for the whole party | ~8 s |
| Nightmare | none | — |

A knocked-out player with a revive comes back into the arena after the wait; without one they're **out** (sent to the Forge, the boss ignores them) but still get the reward if the party wins. The fight fails when nobody is left standing **in the arena**. Solo players get no comebacks. LEAVE only removes you; the rest fight on. FIGHT AGAIN is leader-only and brings the party back in.

### Party test checklist (Studio: Test → Clients and Servers, 2 players)
| # | Do this | Expected |
|---|---|---|
| 1 | Player1: **L** → INVITE next to Player2 | Player2 gets "Player1 invites you to their party!" |
| 2 | Player2: ACCEPT | Both see the party list (★ Player1). Each sees the other's name + health bar on the left. |
| 3 | Player2 opens a Boss Portal | FIGHT is LOCKED: "the leader starts the fight". Shows "Party of 2 (boss health ×1.65)". |
| 4 | Player1: FIGHT | Both are teleported into the arena side by side; banner says PARTY OF 2. |
| 5 | On NORMAL, let Player2 get knocked out | "KNOCKED OUT · back in 8s"; PARTY REVIVES goes 2 → 1; Player2 returns to the arena. On HARD the 2nd knockout is "OUT OF THE FIGHT"; on NIGHTMARE the 1st is. |
| 6 | Win | Both get their own reward screen. Player2's FIGHT AGAIN says only the leader can. |
| 7 | Player1: LEAVE PARTY | Party disbands (party of 1); the HUD bars disappear. |

## Phase 5: CHALLENGES + LEVEL UNLOCKS

Press **J** or the green **GOALS** button.

**Level unlocks** ([LevelUnlocks.luau](src/shared/LevelUnlocks.luau)): PvE Power budget **100 → 110 at level 10 → 120 at level 20** (PvP always stays 100). Crafting: Rare recipes at level 3, Epic at 5. The LEVEL UP! message lists what you just unlocked.

**Challenges** ([ChallengeDefinitions.luau](src/shared/ChallengeDefinitions.luau)): **3 daily** (reset 00:00 UTC) and **2 weekly** (reset Monday 00:00 UTC), the same set for every player. Picked from pools such as: defeat a boss, defeat Scraplings, use abilities, use your Ultimate, possess your Nightmare, dismantle parts, beat bosses on Hard+, beat the Mirror Warden, craft a part. **No PvP challenges** (PvP is optional). Rewards are paid automatically when one finishes: daily +80 coins · +15 Essence · +60 XP, weekly +300 coins · +60 Essence · +250 XP. Save schema v7.

### Goals test checklist
| # | Do this | Expected |
|---|---|---|
| 1 | Press **J** | GOALS: your level, XP bar, "Power budget: PvE 100 · PvP 100", the unlock list (✓ for reached), 3 daily + 2 weekly challenges with reset timers. |
| 2 | Do whatever one of today's challenges asks (e.g. use abilities, kill Scraplings) with GOALS open | Its bar fills live. |
| 3 | Finish one | Toast "DAILY CHALLENGE COMPLETE: … (+80 coins…)", the row turns green "✓", coins/Essence go up. Doing more never pays twice. |
| 4 | Reach level 10 | "LEVEL UP! … Unlocked: PvE Power budget 110"; the Workshop's Power bar now allows 110. |

## Phase 5: THE CODEX

Press **M** or the pink **CODEX** button (also works from inside the Workshop).

| Tab | Shows |
|---|---|
| **BOSSES** | Lore, area, ☠ difficulty, recommended Power, tips, your wins + best time on each difficulty, loot (✓ = owned), lock reason |
| **PARTS** | Every part by slot. Discovered: stats, ability / ultimate / on-hit, Power, owned count, source. Undiscovered: "???" + rarity, slot and where to find it |
| **STATUS EFFECTS** | What Burn / Poison / Shock / Chill / Weaken do (numbers from the game data) and how to counter them |
| **MUTATIONS** | The Mutation Book (below), with the Studio-only DEV: GRANT MUTATION button |

## Phase 5: MUTATIONS + the Mutation Book

A part dropped by a boss can be **mutated**: the same part plus a bonus and a new look (tint, material, sparkles). Chance per drop: **Normal 8% · Hard 14% · Nightmare 22%** (50% in Studio: `Config.Dev.StudioMutationChance`). Tutorial drops never mutate.

| Mutation | Effect | Extra Power |
|---|---|---|
| Venomous / Infernal / Frozen / Charged / Cursed | hits may Poison / Burn / Chill / Shock / Weaken (+ a small stat) | +2 |
| Glass | +12 Attack, −40 Health | +1 |
| Ironclad | +6 Defence, −1 Move Speed | +2 |
| Swift | +2 Move Speed, +8 Attack Speed | +2 |
| Colossal | +45 Health, +10 Stagger Resist, −5 Attack Speed, part looks 15% bigger | +3 |
| ✦ Prismatic (very rare) | a little of every stat, shimmering | +4 |

- **Workshop:** mutated copies are their own entries ("✦ Venomous Rusty Claw"). Equip like any part.
- **Mutation Book:** the MUTATIONS tab of the Codex (**M**). All 10 mutations: found ones show effect, count and parts; the rest are "???". In Studio, **DEV: GRANT MUTATION** gives a random mutated copy of one of your parts instantly.
- **Safe:** crafting and dismantling only ever use **plain** copies, never mutated ones.
- Data: save schema v6 (`profile.Mutations`, `profile.MutationBook`, `build.Mutations`). Definitions: [MutationDefinitions.luau](src/shared/MutationDefinitions.luau).

### Mutation test checklist
| # | Do this | Expected |
|---|---|---|
| 1 | Press **M** → MUTATIONS | 0 / 10 discovered, all "???". |
| 2 | Click **DEV: GRANT MUTATION** (or beat bosses: 50% mutation chance in Studio) | "Granted Venomous Rusty Claw (NEW!)"; boss reward cards say "✦ … MUTATION". |
| 3 | Look at the list | That mutation is now listed with its effect, "Found ×1" and the part. |
| 4 | EQUIP NOW / Workshop | The mutated part is its own entry; equipping it changes stats and Power, and the preview is tinted. |
| 5 | SAVE, close the Workshop | Your Nightmare shows the tint and a few sparkles on that part. Status mutations apply their effect in fights. |
| 6 | Crafting Forge → DISMANTLE | Mutated copies are never listed as spare. |

## Phase 5: Boss 2, THE MIRROR WARDEN

The **right-hand portal** in the Boss Portal hall (the Scrap Titan moved to the left one). Unlocked by beating the Scrap Titan on Normal or harder (always unlocked in Studio). Recommended Power 70.

A **floating crystal knight**: a faceless mirror mask crowned with shards, a glass blade and a round mirror shield. Its theme is reflection: its attacks echo across its own round arena, the Hall of Reflections.

| Attack | What to do |
|---|---|
| **Mirror Combo**: 3 red boxes in front, one after another | Step out to the side, then punish |
| **Reflected Slam**: a circle under you **and** one at the mirror-image spot across the hall | Check both circles |
| **Shard Storm**: glass shards fall around everyone | Keep moving |
| **Shatter Nova**: a big ring around the Warden | Back off when it appears |
| **THE MIRROR CRACKS** at 50% (60% on Nightmare) | Slams hit 4 mirrored spots, more shards, and **Prism Beam**: two crossing beams |

Loot: **Phantom Legs** (Epic), Frost Horns / Crystal Shell (Rare), Peeper Orb / Drifting Wisp / Jelly Legs (Uncommon, good for dismantling), Reactor Heart (Legendary). Same Normal / Hard / Nightmare system. Behaviour: [MirrorWarden.luau](src/server/Services/Bosses/MirrorWarden.luau).

### Mirror Warden test checklist
| # | Do this | Expected |
|---|---|---|
| 1 | Go to the Boss Portals | Two portals: Scrap Titan (left, orange), Mirror Warden (right, pale blue). |
| 2 | Open the Warden portal | ☠☠, Recommended Power 70, its own tips and loot, difficulty buttons. |
| 3 | FIGHT (NORMAL) | A round glass arena. A hovering crystal knight with a blade and a mirror shield, sitting just above the floor. |
| 4 | Watch a Reflected Slam | Two red circles: under you and on the opposite side of the arena centre. |
| 5 | Get it to 50% | "THE MIRROR CRACKS!", it turns pink-violet, 4-way slams, crossing Prism Beams. |
| 6 | Fight on HARD / NIGHTMARE | Pinkish / purple tint; Nightmare uses 4-way slams from the start. |
| 7 | Win | Reward from the Warden's loot table; REPLAY keeps the difficulty. |

## Phase 5: The Crafting Forge

Press **E** at the **anvil** in the middle of the Forge (under the burning heart, sign "⚒ CRAFTING FORGE").

| Part | Rarity | Level | Essence | Coins | Also uses |
|---|---|---|---|---|---|
| Frost Horns | Rare | 3 | 60 | 150 | 1× Cracked Skull |
| Crystal Shell | Rare | 3 | 80 | 200 | 1× Wooden Body, 1× Scrap Visor |
| Demonic Claws | Epic | 5 | 150 | 400 | 2× Rusty Claw, 1× Magnetic Claw |
| Void Wings | Epic | 5 | 180 | 500 | 1× Tiny Bat Wings, 1× Reinforced Core |

**Dismantle** spare duplicates into Essence: Uncommon 5 · Rare 15 · Epic 40 · Legendary 100. Your **last copy** of a part and copies **used in a saved build** are never taken (by dismantling or as crafting ingredients). Epic/Legendary dismantles need a second click to confirm. Recipes: [CraftingDefinitions.luau](src/shared/CraftingDefinitions.luau). In Studio crafting is free (`Config.Dev.FreeCraftingInStudio`).

### Crafting test checklist
| # | Do this | Expected |
|---|---|---|
| 1 | Walk to the anvil in the middle of the Forge, press E | THE CRAFTING FORGE opens with your Level / Essence / Coins and 4 recipes. |
| 2 | CRAFT Frost Horns | "Crafted Frost Horns! NEW PART!" and owned goes to 1. |
| 3 | Open the Workshop (B) → Head | Frost Horns is there and can be equipped. |
| 4 | DISMANTLE tab | Only parts with spare copies are listed. Dismantling adds Essence (top line updates). |
| 5 | Set `FreeCraftingInStudio = false` | Costs show green/red; CRAFT explains what's missing (level, Essence, coins or spare parts). |
| 6 | Try to dismantle a part your saved build uses | It isn't offered (or says no spare). |

## Phase 5: Boss difficulties

The Boss Portal now has **NORMAL / HARD / NIGHTMARE** buttons.

| | Normal | Hard | Nightmare |
|---|---|---|---|
| Unlock | always | beat Normal once | beat Hard once |
| Boss HP / damage | ×1 / ×1 | ×1.6 / ×1.3 | ×2.4 / ×1.6 |
| Attacks | normal | faster (warnings 10% shorter, never < 0.5 s) | fastest, **double slams from the start**, bigger barrages, Overdrive at **60%** |
| Legendary odds | 3% | 4% | 5% |
| XP / coins / Essence | ×1 | ×1.5 | ×2.25 |

Tuning: `Config.Difficulties` and `Modes` in [BossDefinitions.luau](src/shared/BossDefinitions.luau). In Studio all difficulties are unlocked (`Config.Dev.UnlockAllDifficultiesInStudio`). Wins and best times are tracked per difficulty (save schema v5; players who already beat Normal keep Hard unlocked).

### Difficulty test checklist
| # | Do this | Expected |
|---|---|---|
| 1 | Open the Boss Portal | Three buttons. NORMAL selected; FIGHT (NORMAL). |
| 2 | Click HARD | Button turns red, ☠☠, Hard tip at the top, rewards say "(HARD odds)" with 4% Legendary, FIGHT (HARD), "x1.5 XP, coins and Essence". |
| 3 | Fight on HARD | Banner says HARD DIFFICULTY, health bar says "· HARD", boss has red eyes and more HP. |
| 4 | Fight on NIGHTMARE | Purple glowing eyes; every Ground Slam hits twice; Overdrive at 60%. |
| 5 | Win | "HARD VICTORY!" / "NIGHTMARE VICTORY!", bigger XP/coins/Essence. REPLAY keeps the same difficulty. |
| 6 | Set `UnlockAllDifficultiesInStudio = false`, new profile | HARD and NIGHTMARE show 🔒 and "Beat THE SCRAP TITAN on NORMAL to unlock." |

---

## What's new in Phase 4: THE NIGHTMARE COLOSSEUM (PvP)

PvP is **completely optional**. Players can switch duel requests **OFF**.

| Feature | Details |
|---|---|
| **Where** | Walk **south** from the Forge to the red-pillared Colosseum and press **E** at the podium. You can also press **P** or the red **PVP** button. |
| **Duel requests** | The menu lists everyone in the server with **BEST OF 1** / **BEST OF 3** buttons. The other player gets an Accept/Decline pop-up that expires after 20 s. |
| **How to win a round** | Defeat the opponent's **Nightmare**, **or** knock out their **Handler twice**. The first knockout gives a short protected respawn and their Nightmare keeps fighting. |
| **Each round** | **PREP** (12 s, pick any PvP-legal saved build) → **COUNTDOWN** (3 s, frozen) → **FIGHT** (3:00) → **SUDDEN DEATH** (30 s, a red ring shrinks and standing outside it hurts). If time runs out, the player with more health left wins. Hiding never wins. |
| **Fairness** | Builds must fit the **100 Power budget** (max 1 Legendary). Player level never changes stats. Nightmares deal 45% damage to Handlers, so duels are about the monsters. An Ultimate can never take more than 45% of a target's health. HP, stamina, cooldowns and meters reset every round. |
| **Rewards** | Win: 30 Arena Tokens + 80 XP. Loss: 10 Tokens + 40 XP. Draw: 15 Tokens + 50 XP. Given once per match and saved. Matches under 30 s pay nothing (stops farming). Max 12 rewarded matches per hour. |
| **Leaving** | Leaving or pressing FORFEIT counts as a loss. |

### How to test a duel in Studio (2 players)
1. Make sure Rojo is connected.
2. Click the **Test** tab at the top of Studio.
3. In the **Clients and Servers** section, set the player count to **2 Players**, then click **Start**.
4. Two extra game windows open (Player1 and Player2). In **Player1's** window, press **P** and click **BEST OF 3** next to Player2.
5. In **Player2's** window, click **ACCEPT**.
6. Fight! Switch between the windows to control each player.
7. When you're done, click **Cleanup** (or Stop) on the Test tab to close both windows.

### Phase 4 test checklist
| # | Do this | Expected |
|---|---|---|
| 1 | Player1: P → BEST OF 3 next to Player2 | Player2 sees "Player1 challenges you…" with ACCEPT / DECLINE. |
| 2 | Player2: DECLINE | Player1 gets the toast "Player2 declined your duel." |
| 3 | Player2: turn DUEL REQUESTS: OFF, then Player1 challenges again | "Player2 isn't accepting duel requests." |
| 4 | Turn it back ON and accept | Both teleport to a private arena with a blue pad and a red pad. The PREP list shows your builds; any over 100 Power say NOT PvP-LEGAL. |
| 5 | Countdown | Nobody can move or attack. Then "ROUND 1 · FIGHT!" |
| 6 | Fight | Your opponent has a red outline. Your Nightmare attacks them automatically, and R targets them. Nightmare hits on a Handler do noticeably less damage. |
| 7 | Knock out a Handler once | "Player's HANDLER IS DOWN · Knockout 1/2". They reappear at their pad with a force field. A second knockout wins the round. |
| 8 | Defeat a Nightmare | The round is won immediately and the score goes to 1–0. Next comes PREP for round 2. |
| 9 | Wait out a round | At 0:00 SUDDEN DEATH starts and the red ring shrinks. Standing outside it costs health. |
| 10 | Win 2 rounds | VICTORY / DEFEAT screens with rewards. Both players are returned to the Forge with their normal Nightmares. |
| 11 | Press FORFEIT mid-match | The opponent wins. Under 30 s there are no rewards. |
| 12 | Try the Workshop or Recall mid-duel | They're blocked ("You can't change builds mid-duel"). |
---

## What's new in Phase 3

| Feature | Details |
|---|---|
| **NIGHTMARE POSSESSION (F)** | Fill the purple meter by hitting enemies, landing Nightmare hits (more when you command it to attack), using abilities and **dodging boss attacks at the last moment**. Then press **F** to become your Nightmare for 10 seconds. While you're possessing, your Handler stands still and takes half damage, and a big hit on the Handler cancels possession. 45 s cooldown. |
| **ULTIMATES (G)** | The gold bar fills as your Nightmare fights. Each Core has one: Wooden Body = Splinter Storm, Peeper Orb = Thousand-Eye Glare, Reinforced Core = Bastion Quake, Crystal Shell = Crystal Cataclysm, Reactor Heart = **Scrap Apocalypse**. **Void Wings** override the Core with **Void Collapse**. Every Ultimate shows a warning before it hits. |
| **Heavy attacks** | Your Nightmare uses a slow, hard-hitting attack after finishing a combo. While possessing, press Right Click (or Ctrl). |
| **Stagger** | Heavy hits fill a yellow stagger bar. When it's full, the target is stunned. A staggered **Scrap Titan** stops attacking for 2.5 s, which is your chance to hit it hard. For a few seconds after a stagger, the bar fills more slowly, so nothing can be stunned over and over. |
| **Status effects** | Burn, Poison (stacks up to 5), Shock (jumps to a second nearby enemy), Chill (slow, never a freeze), Weaken (deals less damage). They show as coloured tags over health bars. They come from abilities and from parts like **Venomous Spider Legs**, which poison on every hit. |
| **Commands** | **V** opens the command menu (Attack target / Defend / Aggressive / Retreat). **T** switches between Defend and Aggressive. |
| **Smarter pathfinding** | Your Nightmare walks around walls and junk piles. It only works out a new route when it needs one. |
| **New body type: Quadruped** | Mangy Hound Legs (every player gets a pair, including existing saves) and Venomous Spider Legs (Rare, drops from the Scrap Titan). They walk with a trotting animation. |

## Controls

| Action | Keyboard/Mouse | Gamepad | Touch | While POSSESSING |
|---|---|---|---|---|
| Attack | LMB | R2 | ATTACK | Nightmare combo |
| Guard (hold) | Left Ctrl | L2 | GUARD | **Heavy attack** |
| Dodge | Shift | B | DODGE | Nightmare dodge |
| Abilities | Q / E | L1 / R1 | Q / E | same |
| **Possess / exit** | **F** | D-Pad ← | POSSESS | exit |
| **Ultimate** | **G** | R3 | ULT | same |
| **Command menu** | **V** | L3 | CMD | — |
| Sic target | R | X | (in menu) | — |
| Defend ↔ Aggressive | T | Y | (in menu) | — |
| Retreat / Summon / Build | C / H / B | D-Pad ↓ / ↑ / → | | — |
| **PvP menu** | **P** | (HUD button) | PVP | — |

The command menu uses **V** because Roblox reserves Tab for its player list.

---

## Phase 3 test checklist

| # | Do this | Expected |
|---|---|---|
| 1 | Watch your Nightmare fight a Scrapling | Every few seconds it does a bigger, slower **heavy** swing. A yellow line under the enemy's health bar fills, and then **"STAGGERED!"** appears and the Scrapling stops (its attack is cancelled). |
| 2 | Press **V** | The command menu opens. Pick **AGGRESSIVE** and it chases enemies further away, and the HUD shows "AGGRESSIVE · hunting". Press **T** to switch back to **DEFEND**. |
| 3 | Fight until the purple **POSSESSION** bar says READY, then press **F** | The camera moves to your Nightmare and the screen gets a purple tint. WASD moves the Nightmare and the timer counts down from 10. LMB = combo, Right Click = heavy, Shift = dodge, Q/E = abilities. Your Handler stands still. |
| 4 | While possessing, let a Scrapling hit your Handler | Your Handler takes reduced damage. A strong hit ends possession with "INTERRUPTED". |
| 5 | Wait for **F** again | "Possession recharging 45s". |
| 6 | Fill the gold **Ultimate** bar, then press **G** | A big name banner appears (e.g. "SPLINTER STORM") and purple warning circles show, then multiple blasts hit. |
| 7 | Equip **Mangy Hound Legs** (Workshop → Legs) | The archetype says QUADRUPED and four legs trot when it walks. |
| 8 | Equip Electric Jaw / Frost Horns / Demonic Claws (Studio test with `GrantAllPartsInStudio = true`) | Combo finishers apply SHOCK (lightning jumps to a second enemy), CHILL (slow) or BURN (damage over time). The tags appear over the enemy's health bar. |
| 9 | Boss fight: heavy-hit the Titan repeatedly | Its yellow stagger bar under the boss health fills. At full, the HUD shows "STAGGERED!" and the boss stops mid-attack. |
| 10 | Send your Nightmare at an enemy on the other side of the Training Arena wall | It walks around through the entrance instead of pushing into the wall. |

## Working vs later
| ✅ Working now | ⏳ Later |
|---|---|
| Everything from Phases 1–2 (builder, saving, Scrap Titan, loot, pity, tutorial) | **Phase 6**: ranked rating + matchmaking queue, 2v2, parties, showcase |
| Possession, Ultimates, heavy attacks, stagger, 5 status effects | **Phase 5**: more bosses, mutations, Codex, crafting, Hard/Nightmare difficulty |
| Full command set, pathfinding, Quadruped body type | |
| **Phase 4: 1v1 duels (Bo1/Bo3), requests, KO rules, sudden death, PvP balance, Arena Token rewards** | |
| | **Phase 7**: audio, polish, settings menu (camera shake reduction etc.) |

**Note:** Phase 4 was playtested in Studio with 2 players (full Bo3 duel). Fixes from that test: duel decline/timeout messages now show inside the PvP panel; you can't challenge a player with no PvP-legal build; melee hits are blocked by walls and pillars; Nightmares path around cover instead of getting stuck, and fight back when hit by something while they can't reach their target. In Studio, test players skip the tutorial (`Config.Dev.SkipTutorialInStudio`).
