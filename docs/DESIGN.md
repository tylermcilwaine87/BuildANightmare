# BUILD A NIGHTMARE — Design Review & Technical Architecture

*Lead-dev document · Phase 1 (core playable prototype) · v0.1.0*

---

## STEP 1 — Design review: conflicts, risks, and resolutions

| # | Issue in the spec | Why it matters | Resolution (core identity preserved) |
|---|---|---|---|
| 1 | **Handler HP 100 vs Nightmare combo ≈46 damage.** In a 1v1 duel, "knock out the Handler twice" wins. | Two Nightmare combos delete a Handler, so every duel becomes "ignore the monster, kill the player". That kills the creature fantasy. | Phase 4 adds `PvP.NightmareDamageToHandlerMultiplier = 0.45` and a Handler guard stance. Handler KOs stay a real threat, but the Nightmare remains the main target. Tuned in playtests. |
| 2 | **Duplicates "can be equipped on another saved Nightmare"** combined with 3 saved build slots. | If a copy were locked to one build, new players couldn't fill three builds from the starter set. | **Ownership = unlock + count.** A build can use a part as many times as you own copies (two Rusty Claws for two arms). Saved builds don't lock parts away from each other because only one Nightmare is active at a time. Duplicates are still useful for mirrored limbs, dismantling into Essence, and (later) trading. |
| 3 | **Legendary limit is undefined.** Two arms means two "Hands of the Puppet Master" would be possible. | Stacked signature abilities break the "Legendary ≠ unbeatable" rule. | **Max 1 Legendary per build** (`Config.Builds.MaxLegendaryParts`). It is enforced by `BuildValidator` on both client and server, plus high Power Cost (Reactor Heart = 38/100). |
| 4 | **Free resizing/rotating vs "never change hitboxes".** | Visual tweaks can't become a combat advantage. | Each archetype has a fixed, invisible hitbox. Every visual part is `CanCollide/CanQuery/CanTouch = false` and massless. Scale is limited to 0.8–1.25 and rotation to ±20°. Reach is a part **stat**, not geometry. |
| 5 | **"Unique animation for every combination"** is impossible at this scale. | Animation cost would grow with every part combination. | **Joint-role procedural animation.** Every socket is a Motor6D named by role (`Joint_RightArm`, `Sub_Legs_L`…), and one client animator drives them all. Authored AnimationTracks can be layered on later for signature parts. |
| 6 | **Bond Level unlocks build preset slots, and monetisation sells extra build slots.** | Two sources for the same reward, and one of them is paid. | 3 slots are free. Bond milestones grant +2. Robux slots are a convenience only, never combat power. |
| 7 | **PvE budget rises to 120, but PvP stays at 100.** | A player's favourite PvE build might be illegal in PvP. | The workshop shows a separate PvP-legal badge (Phase 4). Ranked queues check the 100 budget at entry and offer to pick another saved build. |
| 8 | **Pity counter vs disconnect exploits.** | Players could quit before a non-Legendary reward is committed. | Rewards and pity are rolled **server-side when the encounter completes** and committed in the same `UpdateAsync` as the inventory grant, with an encounter GUID for idempotency (Phase 2). Leaving early never touches the counter. |
| 9 | **Mirror Warden copies player Nightmares.** | This looked expensive. | *Superseded in Phase 5:* every boss is its own creature. The Warden is a unique crystal knight whose REFLECTION theme lives in its attacks (echoed slams, crossing beams), not in copying the player. |
| 10 | **Hub with 30+ players, each with a summoned Nightmare.** | Each Nightmare is about 25–60 parts, so performance becomes a risk. | Strict 7-slot rig, about 12 pieces max per part. Visual parts are massless with no collision. One shared AI loop at 10 Hz and an animator culled at 160 studs. Phase 7: optional "hide other Nightmares in hub" setting and StreamingEnabled tuning. |
| 11 | **Possession: Handler takes 50% DR but a "Handler knockout interrupts".** | It's unclear whether a KO during possession counts toward the 2-KO loss. | Yes, it counts. Possessing is a deliberate risk, and the HUD shows a warning vignette when the Handler is hit during possession. |
| 12 | **Companion AI dodging "telegraphed attacks".** | Perfect dodging would make the AI play itself. | AI reacts with a 0.25–0.45 s randomised delay, 60% base success, and only on attacks whose telegraph it can "see". Commands like RETREAT let skilled players do better. |
| 13 | **ProximityPrompt default key E** clashes with Ability 2 (E) in Phase 3. | Input conflict. | In Phase 3, workshop prompts move to a context action that is disabled in combat zones. |
| 14 | **Text input for names.** | Roblox requires filtering. | Every name goes through `TextService:FilterStringAsync` on the server. If filtering fails, the old name is kept and the player is told. Names are never shown unfiltered to others. |

**Scope decisions for Phase 1** (the honest list):
- **Saving is in-memory only.** DataStore persistence is Phase 2. `PlayerDataService` already has the final API, and the UI tells players that builds reset when they leave.
- **Movement uses direct `Humanoid:MoveTo`**, which is fine for flat arenas. PathfindingService with throttled recomputation comes in Phase 3.
- **Abilities, stagger, dodge/guard, status effects, possession and ultimates are not implemented yet.** Parts show their *planned* ability, labelled "unlocks in a later update".
- **Two archetypes ship now: Biped and Floating.**

---

## STEP 2 — Architecture

### Studio tree (what Rojo produces — or build it by hand)

```
ReplicatedStorage
├─ Shared                      (Folder)
│  ├─ Config                   ModuleScript   all tuning numbers
│  ├─ Util                     ModuleScript   pure helpers
│  ├─ RarityDefinitions        ModuleScript   Uncommon → Legendary
│  ├─ SlotDefinitions          ModuleScript   7 slots, required/optional, mirroring
│  ├─ ArchetypeDefinitions     ModuleScript   Biped, Floating (base stats + hitbox)
│  ├─ PartDefinitions          ModuleScript   16 parts, data-driven placeholder art
│  ├─ StatCalculator           ModuleScript   build → stats (shared formula)
│  ├─ BuildValidator           ModuleScript   sanitise + rules (shared)
│  ├─ NightmareAssembler       ModuleScript   build → rigged Model (shared)
│  └─ Net                      ModuleScript   remote registry
├─ Remotes                     (Folder, created at runtime by Net.Setup)
└─ Assets/PartModels           (OPTIONAL Folder: real art overrides, see below)

ServerScriptService
└─ Server                      (Folder)
   ├─ Main                     Script         bootstrap
   └─ Services                 (Folder)
      ├─ AntiExploitService    ModuleScript   token-bucket rate limits, flags
      ├─ WorldBuilder          ModuleScript   placeholder map, collision groups, lighting
      ├─ PlayerDataService     ModuleScript   profiles (in-memory P1, DataStore P2)
      ├─ InventoryService      ModuleScript   server-only part ownership
      ├─ HitDetectionService   ModuleScript   GetPartBoundsInBox queries
      ├─ CombatService         ModuleScript   the ONE damage pipeline + Handler attack
      ├─ NightmareAIService    ModuleScript   companion brains + commands
      ├─ NightmareSpawnService ModuleScript   summon / recall / respawn
      ├─ NightmareBuildService ModuleScript   save/switch builds (BuildRequest)
      └─ TrainingService       ModuleScript   dummies + Scraplings

StarterPlayer/StarterPlayerScripts
└─ Client                      (Folder)
   ├─ ClientMain               LocalScript    bootstrap
   └─ Controllers              (Folder)
      ├─ UIKit                 ModuleScript   UI helpers & palette
      ├─ ClientState           ModuleScript   profile snapshot + BuildRequest wrapper
      ├─ NightmareAnimator     ModuleScript   procedural joint animation
      ├─ EffectsController     ModuleScript   damage numbers, flashes, telegraphs, bars
      ├─ HUDController         ModuleScript   combat HUD + touch buttons
      ├─ WorkshopController    ModuleScript   the creature builder
      ├─ CombatController      ModuleScript   attack requests, targeting, commands
      └─ InputController       ModuleScript   keyboard/mouse/gamepad bindings

Workspace (generated by WorldBuilder unless you provide "NightmareForgeHub")
├─ NightmareForgeHub/{Ground, Hub, WorkshopAreas, TrainingArea}
├─ Nightmares                  summoned Nightmares (server-owned)
├─ Enemies                     training enemies
└─ ClientEffects               (client-only effect parts)
```

**No StarterGui setup is needed.** All UI is built in code (`CombatHUD`, `WorkshopGui`), so it scales and can be maintained in version control.

### Server vs client responsibilities

| Server (authoritative) | Client (presentation + requests) |
|---|---|
| Profiles, inventory, build validation, name filtering | Workshop draft editing, live preview, stat diffs |
| Spawning and owning Nightmare physics (`SetNetworkOwner(nil)`) | Procedural animation (`Motor6D.Transform`, never replicated) |
| AI decisions, attack timing, hit queries, damage, defeat | Swing prediction, damage numbers, telegraph markers, health bars |
| Cooldowns and rate limits for every remote | Input mapping, touch buttons, target *suggestion* |

### Remotes (`Shared/Net`)

| Remote | Type | Direction | Payload | Server validation |
|---|---|---|---|---|
| `BuildRequest` | RemoteFunction | C→S | `"GetState"` / `"SaveBuild", slot, draft` / `"SetActive", slot` | rate limit, slot index integer 1..3, Sanitize (types, NaN, unknown ids, clamps), Validate with the server inventory, TextService filter |
| `CombatAction` | RemoteEvent | C→S | `"BasicAttack"` | rate limit, alive, 0.65 s interval (minus 0.08 s latency tolerance), server-side hit box from the server's HRP |
| `NightmareCommand` | RemoteEvent | C→S | `"Attack", Model` / `"Follow"` / `"Retreat"` / `"ToggleSummon"` | rate limit, target must be a living `Enemy` within leash range |
| `CombatFeedback` | RemoteEvent | S→all | `"Damage", {Target, Amount, Position, Source}` / `"Defeated", {...}` | visual only |
| `UIStateUpdate` | RemoteEvent | S→C | `"Profile", snapshot` / `"NightmareDefeated"` / `"Summon"` / `"Toast"` | — |

### Module relationships

```
Main ─ Init(services) ─ Start()
  CombatService ◄─── NightmareAIService (combo hits)      ◄─ NightmareCommand
       ▲   ▲                    ▲
       │   └── TrainingService  │ Register/Unregister
       │      (Scrapling hits)  │
  HitDetectionService     NightmareSpawnService ◄─ NightmareBuildService ◄─ BuildRequest
                                │                         │
                         NightmareAssembler ◄── StatCalculator ◄── BuildValidator
                         (Shared, also used by WorkshopController preview)
                                │
                         PlayerDataService / InventoryService
```

### Contracts other phases build on

- **Combatant** = Model + `Humanoid` + `HumanoidRootPart`. Side = has tag `Enemy` or not. `Defence` attribute.
- **Action replication**: set `ActionName`, `ActionWindup`, `ActionDuration`, then increment `ActionSeq`. The client animator and telegraph system react. Bosses (Phase 2) use the same contract.
- **Damage**: always `CombatService:ApplyDamage{Attacker, Target, BaseDamage, AttackPower, Knockback, Source}`. Status effects, crits, stagger and PvP context slot into this one function.
- **Rig**: `Joint_<Slot>` / `Sub_<Slot>_<Group>` Motor6Ds pivot at sockets.
- **Art override**: put a Model named `<PartId>` (or `<PartId>_Left`) in `ReplicatedStorage/Assets/PartModels`, pivoted at the joint and facing −Z, and the assembler uses it instead of the placeholder.

---

## Damage & stat formulas (Phase 1)

```
MaxHealth   = Archetype.MaxHealth + Σ part.MaxHealth            clamp 150..700
AttackPower = 100 + Σ part.AttackPower                          clamp 50..175
Defence     = Σ part.Defence                                    clamp 0..60
MoveSpeed   = Archetype.MoveSpeed + Σ part.MoveSpeed            clamp 10..26
AttackSpeed = 100 + Σ part.AttackSpeed (percent)                clamp 70..140
Reach       = Archetype.Reach + max(arm Reach bonus)            clamp 3..9
PowerCost   = Σ part.PowerCost                                  ≤ 100 (PvE now; PvP always 100)

Damage = round(Base × AttackPower/100 × 100/(100 + Defence)),  min 1
Combo timing = Windup/Recovery × 100/AttackSpeed
```

---

## Roadmap after Phase 1

| Phase | Deliverables | Exit test |
|---|---|---|
| 2 | DataStore persistence (UpdateAsync, session lock, retries, migrations, BindToClose), Scrap Titan boss (state machine with telegraphs and an Overdrive phase), BossRewardService with drop tables and pity, reward reveal screen, dodge and guard, first abilities, tutorial, 20+ parts | Defeat the boss, receive a part, rejoin and still have it, equip it, fight again |
| 3 | Heavy attack, stagger meter, status effects, full commands, Pathfinding, AI dodge, Possession, Ultimates, Quadruped archetype | Combat feels responsive across 5+ distinct builds |
| 4 | Colosseum, duel requests, 1v1 rules (Nightmare KO or 2 Handler KOs), Power budget gate, normalisation, Sudden Death, Arena Tokens | Two players duel with no desync or duplicate rewards |
| 5 | Remaining bosses, mutations and Mutation Book, Codex, crafting and Essence, difficulties, challenges, levels | — |
| 6 | Parties (up to 4) with boss scaling, ranked rating and matchmaking, 2v2, showcase, leaderboards | — |
| 7 | Polish, audio, analytics, performance, mobile/console certification, policy checks | — |

---

## Phase 2 architecture additions (v0.2.0)

**New shared modules:** `AbilityDefinitions` (15 abilities: Melee/AoE/Dash/Pull/Shield), `BossDefinitions` (display, balance, modes, loot pools), `TutorialDefinitions` (6 steps).

**New server services** (load order in `Main`):
| Service | Role |
|---|---|
| `PlayerDataService` (rewritten) | DataStore `UpdateAsync` only, session lock `{JobId, Time}` (wait for live locks, take over stale >10 min), refuses saves if another server owns the lock, retries with backoff, autosave every 120 s, release on leave, `BindToClose`, schema v2 + migrations, validation that never deletes unknown items. Studio without API access falls back to a non-saving profile; live servers kick instead of overwriting. |
| `ProgressionService` | XP/levels (`100 + 60·(L−1)` per level, cap 50), coins, essence |
| `TelegraphService` | Broadcasts every warning shape (WorldFX) **and** keeps a registry of hostile zones the companion AI reads to dodge |
| `HandlerService` | Server-owned stamina, dodge i-frames, guard (startup, -65%/-30% heavy, stamina drain, guard break) |
| `AbilityService` | Validates cooldowns and executes abilities; AI queues them until in range |
| `TutorialService` | Event-driven step completion (`Notify(player, event)`), gates first summon, chooses the boss mode |
| `BossRewardService` | Rarity roll → boss loot pool → grant → pity → XP → immediate save |
| `BossService` (+ `Bosses/ArenaBuilder`, `Bosses/ScrapTitan`) | Encounter lifecycle, arena slots (up to 12 concurrent), generic 10 Hz boss state machine (Chase → Attacking → PhaseTransition → Defeated), threat table with periodic target switches, health scaling by participants, `Rewarded[player]` flag set **before** granting |

**New remotes:** `BossRequest` (RF), `TutorialAction`, `WorldFX` (S→all), `PlayerFX` (S→one, client-applied impulses), `BossEvent`, `RewardNotification`.

**Damage pipeline (CombatService:ApplyDamage):** defence → Handler dodge i-frames / guard → ability shields → TakeDamage → knockback (server-owned only, bosses immune) → feedback → OnDamaged (AI retaliation, boss threat) → OnDefeated (kill credit).

**Adding a new boss:** add an entry to `BossDefinitions`, then add `Services/Bosses/<Id>.luau` exporting `BuildModel`, `PreferredRange`, `ChooseAttack`, `OnPhase`, and `Attacks` using the `ctx` API (`Wait`, `WindupTime`, `Action`, `Face`, `Circle`, `Box`, `DamageCircle`, `DamageBox`, `Pull`, `Projectile`, `Impact`, `Banner`, `Targets`, `PickTarget`). It needs no other changes.

**Phase 2 balance targets:** Normal Titan 4,500 HP. Expected effective DPS is ~20–25 (Nightmare combo plus Handler plus abilities, minus time spent dodging), giving about 3–5 min fights. The Tutorial Titan is 30% HP, 55% damage and ×1.3 windups, with no Overdrive.

---

## Phase 3 architecture additions (v0.3.0)

| New module | Role |
|---|---|
| `Shared/StatusDefinitions` | Burn, Poison (stacks ≤5), Shock (burst + 1 chain), Chill (35% slow, never freeze), Weaken (−15% outgoing). Element → status map. |
| `Services/StatusService` | Stagger meters (StaggerPower × (1−StaggerResist)), stun durations (Nightmare 1.2 s / Enemy 1.5 s / Boss 2.5 s), 5 s anti-chain resistance at 25%, decay; status ticks at 4 Hz; publishes `Statuses`, `SpeedMultiplier`, `Stagger*` attributes |
| `Services/NavigationService` | Raycast first; background `PathfindingService` only when blocked; repath ≤1/s or when the goal moves >6 studs |
| `Services/PossessionService` | Meter gains (handler hit 5, Nightmare hit 2, commanded hit 3, ability 4, perfect dodge 15); network-ownership handoff; Handler channel (WalkSpeed 0, −50% damage, heavy hits interrupt); server-timed possessed actions; 10 Hz watchdog (expiry, KOs, range, **speed/teleport check → snap back + end**) |
| `Services/UltimateService` | Energy (dealt/5, taken/8, +6 per ability), resolution Back-signature → Core, four executor types (Nova, Barrage, Beam, Collapse) with friendly telegraphs |
| `Client/PossessionController` | Camera subject swap, FOV ease, tint (no flashing), drives the possessed Humanoid with `PlayerModule:GetControls():GetMoveVector()` so keyboard, gamepad and touch all work |

**Damage pipeline (final order):** side check → AttackPower × attacker Weaken → Defence (unless IgnoreDefence) → Handler i-frames / possession −50% / guard **or** Nightmare possession-dodge i-frames → shields → TakeDamage → knockback (server-owned, non-immune only) → Stagger → Status → feedback → OnDamaged (AI, threat, possession meter, ultimate energy, tutorial) → OnDefeated.

**Commands:** Attack(target) · Defend (aggro 25 around the Handler) · Aggressive (aggro 70, +25 leash, heavy cooldown ×0.6) · Retreat (5 s) · Use Ability (Q/E). "Follow" is kept as an alias of Defend.

**Data:** schema v3. The migration grants `MangyHoundLegs` to existing players, which shows the versioned-migration path working.

**Balance check (PvE):** a 4.5k HP Titan, StaggerMax 300 → about 8 heavy-equivalents per stagger, so 2–4 staggers per fight. Possession roughly every 45–60 s in active fights; Ultimate roughly every 60–90 s. These are starting values for playtests.

---

## Phase 4 architecture additions (v0.4.0)

**`Services/DuelService`**: requests (20 s expiry, 4 s anti-spam, respects `Settings.AllowDuels`), private arena slots (10), and the match state machine **Prep → Countdown → Live → SuddenDeath → RoundOver → … → Ended**. It also handles the Handler-KO rules (KO 1 = protected respawn, KO 2 = round loss), Nightmare defeat = round loss, the time tie-break (`0.7·NM HP% + 0.3·Handler HP% − 0.3·KOs`), and rewards that are granted once, capped hourly, with no pay-out for matches under 30 s. Forfeit on leave.

**Combat changes:** `CanDamage` lets player-owned models hurt each other **only** when `DuelService:AreOpponents` is true (a live round). In PvP, Nightmare→Handler damage ×0.45 and Ultimate damage is capped at 45% of target max HP per cast (`CastKey`). Lethal damage on a duelling Handler is clamped to 1 HP and becomes a **KO** (never a real death).

**Freeze/reset hooks:** Handler (WalkSpeed 0, no dodge/attack), AI (paused), abilities, ultimates and possession all respect `DuelService:IsFrozen`. A round reset rebuilds the Nightmare from the chosen saved build (`NightmareSpawnService:ForceSpawn(player, index)` overrides the build without touching the saved `ActiveBuild`) and resets stamina, possession meter and cooldown.

**Client:** `PvPController` (panel, pop-up, scoreboard, prep picker, banners, sudden-death ring, opponent outlines, reset disabled during duels). Opponents are identified by the replicated `DuelId`/`DuelSide` attributes.

**Data:** schema v4 adds `ArenaTokens`, `PvP {Wins, Losses, Draws}` and `Settings {AllowDuels}`.

**Deferred to Phase 6:** ranked rating, matchmaking queue (rating, latency and queue-size expansion) and 2v2 (team victory rules are separate, as the spec requires).

**Phase 4 playtest fixes:** melee hits need line of sight (`HitDetectionService:FilterVisible`, optional `origin` on `QueryBox`/`QueryRadius`); Nightmares path to the target itself when it's out of sight, detect being stuck (`Config.Navigation.Stuck*`) and sidestep; they switch to an attacker when they can't land hits on their own target (`SwitchTargetAfter`).

---

## Phase 5 architecture additions (v0.5.0, in progress)

**5a: Boss difficulties (done, playtested).** `Config.Difficulties` (Normal → Hard → Nightmare, reward multipliers, unlock chain) + per-boss `Modes` in `BossDefinitions` (health, damage, windup, `AttackDelayMultiplier`, optional `PhaseThresholds`, boss-specific twists such as `ExtraSlams`/`BarrageBonus`). `BossDefinitions.IsModeUnlocked` is shared, so the portal displays exactly what the server enforces. Windups are floored at `Config.Bosses.MinWindup`. Behaviour modules may export `OnSpawn(ctx)` for per-difficulty looks. Data schema v5 stores `Bosses[id].Modes[mode] = {Wins, BestTime}`; the migration treats an existing `BestTime` as proof of a Normal win.

**5b: Crafting Forge (done).** `Shared/CraftingDefinitions` (recipes: level, Essence, coins, ingredient parts; dismantle values; `SpareCount` = owned − max(1, most copies any saved build uses)) is shared by `CraftingService` (remote `CraftRequest`, saves immediately) and `CraftingController` (anvil prompt `OpenForge`). Studio crafting is free (`Config.Dev.FreeCraftingInStudio`).

**5c: The Mirror Warden (boss 2).** Design rule: **every boss is its own creature** (no copying the player). `BossDefinitions` gains `Arena` and `RequiresBoss` (+ shared `IsBossUnlocked`). `BossService` builds arenas per (type, slot) from `ArenaBuilder.Types` (Junkyard row 0, MirrorHall row 1). The Warden is a hand-rigged crystal knight (`Joint_*` motors, so the client animator drives it; `Archetype = "Floating"` for the hover bob). New ctx helpers: `DamageCircles` / `DamageBoxes` (multi-zone, each target hit once) and `Reflect(position, degrees)` (mirror through the arena centre).

**5d: Mutations + Mutation Book.** `Shared/MutationDefinitions` (10 mutations: Stats, PowerCost, OnHit, Visual, roll Weight). Ownership = "unlock + count" extended: `profile.Inventory[part]` still counts ALL copies; `profile.Mutations[part][mutation]` counts how many of those are mutated. Builds store `build.Mutations[slot]`; `BuildValidator.Validate(build, inventory, budget, mutations)` checks mutated ownership (every server caller passes `profile.Mutations`). `StatCalculator` adds mutation stats/Power; `NightmareAssembler` tints/re-materials/scales the slot's pieces and adds a sparkle emitter (not in previews); `NightmareSpawnService` adds mutation OnHit rules. `BossRewardService` rolls `Config.Mutations.Chance[mode]` → `InventoryService:GrantMutated` (also updates `profile.MutationBook`). `CraftingDefinitions.SpareCount` only ever spends plain copies. Schema v6.

**Prompt key conflict (review item 13) resolved:** `InputController` tracks shown ProximityPrompts; while one is visible, its key (E / gamepad X) goes only to the prompt.

**5e: Codex.** `CodexController` (M / CODEX button, DisplayOrder 22) with tabs Bosses / Parts / Status Effects / Mutations; read-only from shared definitions + the profile snapshot (`Discovered`, `Bosses`, `Inventory`, `MutationBook`). It absorbed the Mutation Book screen (and its Studio-only dev grant, server-checked in `CraftingService`).

**5f: Challenges + level unlocks.** `Shared/LevelUnlocks` (`PvEBudget(level)`: 100 / 110 @10 / 120 @20, used by NightmareBuildService, NightmareSpawnService and the snapshot's `PowerBudget`; PvP stays `Config.Builds.PvPPowerBudget`). `Shared/ChallengeDefinitions` (daily/weekly pools; `PeriodInfo` = UTC day / Monday-week key + end time; `Pick` = seeded shuffle of the key, so everyone shares a set with no storage). `ChallengeService:Notify(player, event, amount, data)` is called from BossService (BossWin), CombatService.OnDefeated (Scrapling kills), AbilityService, UltimateService, PossessionService, CraftingService; it rolls periods over, sets `Done` before paying, saves on completion and pushes a small `UIStateUpdate("Challenges")`. Client: `GoalsController` (J / GOALS). Schema v7 (`profile.Challenges`).

**Phase 5 is complete.**

---

## Phase 6 architecture additions (v0.6.x, in progress)

**6a: Parties.** `PartyService` (in-memory parties ≤ `Config.Party.MaxSize`; invite → pop-up → accept/decline with expiry; leader hand-over; disband at 1; remotes `PartyRequest` / `PartyEvent`). `BossService:StartEncounter` is leader-only for parties and brings every member that passes `CanJoin`; health already scales via `Config.Bosses.HealthScaling`. Comebacks per difficulty (`Config.Party.Revives`: Normal = party size, Hard = 1 shared, Nightmare = 0) with growing waits (`RejoinDelays` on top of the 5 s respawn). The encounter tracks `InArena` / `PendingRejoin` / `Out`: `OnHandlerDown` reserves a comeback or marks the player out; `OnCharacterAdded` re-places reserved players; `AnyoneStanding` (alive AND in the arena) decides failure, also when someone leaves; `GetTargets` ignores players who aren't in the arena. Out players are still rewarded on victory. The LEAVE request now ends the fight only for the leaver. Client: `PartyController` (L / PARTY; not O, which Roblox uses for camera zoom: panel, invite pop-up, members' health HUD); the Boss Portal locks FIGHT for non-leaders and shows the party scaling.

**6b: Leaderboards.** `LeaderboardService`: one OrderedDataStore per board (`Config.Leaderboards.StorePrefix` + id): Level, BossWins (`BossDefinitions.RealWins`), PvPWins, TitanTime / WardenTime (min BestTime over real modes, ascending). Writes only changed values, only for `IsPersistent` players with UserId > 0, every `WriteInterval` and on leave. Reads top `Size` every `ReadInterval` (names cached via `GetNameFromUserIdAsync`); on failure falls back to a THIS SERVER ranking from live profiles. Displayed on a server-built SurfaceGui board (HallOfNightmares) that cycles boards.

**6c: Ranked.** `Shared/RankDefinitions` (Elo with placement K, tiers, widening search range). `RankedService`: same-server queue (DuelRequest "QueueRanked" / "LeaveQueue"), 1 Hz matchmaker (oldest first, closest fit within both players' ranges, rematch avoidance, busy players dropped), `StartMatch(a, b, 3, { Ranked = true })`; `ApplyResult` is called once from `DuelService:EndMatch` (inside the Rewarded guard) and returns `{Old, New, Delta, Tier}` for the results screen. Forfeits/leaves count. `profile.Ranked` (schema v8). Leaderboard "Rating" board. Cross-server matchmaking (MemoryStoreService queue + TeleportService reserved servers) is deliberately out of scope for now.

**6d: Team duels (2v2 / 3v3).** `DuelService` matches are now side-based: `Teams[1..2]`, `Side[player]`, `Score[side]`, `KOs[player]`, `Out[player]` (per round), `Left[player]`, `TeamNames`, `TeamSize`; `StartMatch(a, b, ...)` takes Players or lists. Losing condition generalised: `Eliminate` marks a player out (Nightmare defeated / 2 Handler KOs / left); a side with everyone out loses the round, so 1v1 behaviour is unchanged. `IsFrozen` includes out players; `AreOpponents` requires different sides and neither out (no friendly fire); `GetOpponentModels` returns all fightable enemies (AI targeting). Team challenges: `DuelRequest "ChallengeTeam"` leader → leader, equal party sizes (`Config.PvP.Min/MaxTeamSize`), re-checked on accept (`CheckTeams`). `HealthScore(match, side)` averages a side. Disconnects: `OnPlayerLeft` (team plays on unless the whole side left). Client: TEAM NvN buttons for party leaders, team pop-up, "Standing" scoreboard, `DuelOut` attribute hides outlines.

**6e: Showcase.** `ShowcaseService` builds `Config.Showcase.Slots` pedestals (south of the Workshop), assigns one per player, and re-assembles an anchored statue with `NightmareAssembler` whenever the JSON signature of the active build changes (polled every `RefreshInterval`). Prompt `InspectShowcase` (attribute `OwnerUserId`) → `ShowcaseRequest "Inspect"` returns the build + likes + `CanLike`; `"Like"`: one per viewer per owner per UTC day (`profile.LikesGiven = {Day, To}`), not yourself, saved on both profiles. Labels escape player-typed text for RichText. Leaderboard "Likes". Client: `ShowcaseController`. Schema v9.

**Phase 6 is complete.**

---

## Phase 7 additions (v0.7.x, in progress)

**7a: Settings.** `Shared/SettingsDefinitions` (Toggle / Choice / Slider with `Sanitize` + `Get` defaults) stored in `profile.Settings` (unknown keys dropped on load; `AllowDuels` kept). Server: BuildRequest `"SetSetting"` (allowed mid-duel). Client: `SettingsController` (K / ⚙) applies instantly (local override until the server confirms) and fires `Changed`; consumers: EffectsController (shake scale, hit flash, damage numbers), HUD control hints, Nightmare hiding via `LocalTransparencyModifier` + disabling BillboardGuis/particles (re-applied every 0.5 s; skipped in boss fights / duels).

**7b: Audio.** `Shared/AudioDefinitions` (all SFX + music ids; empty = silent) and client `AudioController`: two SoundGroups (Music / SFX) driven by the volume settings; `Play(key, position?)` with per-sound cooldown, random pitch and optional spatial playback at the event position; hooks on existing remotes (CombatFeedback, WorldFX, BossEvent, DuelEvent, UIState LevelUp / challenge toasts) plus direct calls (UIKit.OnClick for every button, reward reveals, crafting, possession); a 1 Hz music director (Duel > Boss/BossOverdrive > Hub) with cross-fades.

**7c: Performance pass.**
- *Effects are sent only to nearby players:* `Net.FireNearby(remote, position, radius, ...)` replaces every `FireAllClients` (CombatFeedback Damage / Defeated / Blocked / GuardBreak / Staggered / Status / Chain; WorldFX Telegraph / Impact / Projectile / Shield / UltimateBanner). Radius `Config.Performance.EffectRadius` (250), plus the shape's own size for telegraphs / projectiles so long beams reach everyone they can hit. Far-away boss fights and duels cost other clients no bandwidth and no effect parts.
- *Cached raycast filters:* `NavigationService.obstacleParams` and `HitDetectionService.sightParams` are rebuilt at most every `FilterRefresh` (1 s) instead of per call (they run for every moving creature, every AI tick).
- *Checked and already fine:* client loops are throttled (HUD 10 Hz, party 5 Hz, settings 2 Hz, music 1 Hz), overhead bars are event-driven, the animator culls beyond 160 studs, floating text is capped, creature Humanoids have unneeded states disabled, arenas are reused. The "hide other Nightmares" setting covers the busiest hub case.
- *Deliberately not done:* `Workspace.StreamingEnabled`. It would help very large maps, but much of the client expects world objects (portals, pedestals, boards, arenas) to exist; turning it on needs its own pass with testing.

**7d: Mobile + controller.** `MenuController` (hub of every menu; ☰ MENU on touch, D-Pad Right on gamepad, which used to open the Workshop directly). Touch-only devices (`UIKit.IsTouchOnly`) get a compact top bar. `UIKit.Responsive(panel)` resizes centred panels to 95% × 90% when the viewport is shorter than `UIKit.SmallScreenHeight` (560). `InputController` keeps one list of closable menus (`openMenus`): `anyMenuOpen` blocks combat input, and controller **B** closes the top-most one (checked before `gameProcessed`, which Roblox sets while you navigate UI with a pad). New helpers: `SettingsController:Close`, `PvPController:IsPanelOpen`, `BossController:IsPortalOpen`.

**7e: Analytics.** `GameAnalyticsService` wraps Roblox `AnalyticsService` (every call pcall-guarded; UserId ≤ 0 skipped): onboarding funnel (step 1 on a fresh profile's first join, steps 2–7 from `TutorialService:Advance` via `TutorialSteps`), economy (`Rewards` after every `ProgressionService:Award` call site, crafting sinks, dismantle source; balance read after the change; reason passed as the item SKU), custom events with up to 3 breakdown fields (BossWin/BossFail, DuelEnd, MutationFound, PartCrafted, ChallengeComplete, LevelUp).

**Bosses 3 & 4.** `StormBeast` (quadruped rig with `Sub_Legs_FL/FR/BL/BR` motors so the client trots it; pounces via the new `Context:PlaceAt`) on the `ThunderPlateau` arena (row 2), and `AbyssalMaw` (burrow: anchors the root and moves it 45 studs underground, untargetable, and always re-emerges via `PlaceAt` on every exit path, including fight end and stagger) on the `SunkenAbyss` arena (row 3). Boss damage helpers now pass `opts.Status` through (Shock / Weaken). Unlock chain Titan → Warden → Storm Beast → Maw (`RequiresBoss`). Portal hall widened to four portals. Leaderboards StormTime / MawTime; weekly challenges WeeklyStorm / WeeklyMaw. Electric Jaw and Shadow Tentacle are now obtainable.

**7f: Launch review (v0.7.6).**
- *Separate Studio stores:* in Studio, profiles and leaderboards use `StoreName .. Config.Data.StudioStoreSuffix` ("_Studio"). With API access on, Studio shares DataStores with the live game, so without this, free Studio crafting / the 50% Studio mutation chance / test scores would leak into live saves and boards.
- *Leave-save ordering:* `onPlayerRemoving` waits `RELEASE_DELAY` (0.5 s) so other services' PlayerRemoving handlers (duel forfeit loss, rating change) land in the final save, then marks the session `Released` (autosaves skip released sessions, so a late autosave can't re-lock the profile after release) and waits for any in-flight autosave before the release write. `BindToClose` releases every session not already released and also waits for releases already in progress.
- *Checked, no change needed:* user text = build names only, filtered via `TextService` (`GetNonChatStringForBroadcastAsync`) with a safe fallback when filtering fails; party / duel / showcase show Roblox display names. All 9 client remotes go through `AntiExploitService:Allow` with a `Config.RateLimits` entry and type-check their arguments. Every `Config.Dev` cheat is gated by `RunService:IsStudio()`; `DebugHitboxes` / `DebugNavigation` are off. Every per-player table is cleaned on PlayerRemoving (RankedService now also drops `lastOpponent` entries that point at the departed player).

**Phase 7 code is complete.** Remaining launch work is in Studio / the Creator Dashboard (see README).

## World rebuild (v0.8.0)

**Layout:** `Shared/WorldDefinitions` is the single source of truth: hub centre/radius/spawn, the four regions (Direction, Arena origin CFrame with LookVector out through the entrance, lighting presets, ambience key), `GatePlaza(region)` (= arena origin moved `GateDistance` (104) out of the entrance), `RegionAt(pos)` (hub disc, then the four quarters), `BossRegion`, and the relic list.

**Server build (`WorldBuilder`):** environment (lighting base, Sky, Terrain.Clouds, terrain material colours), removes the place's starter Baseplate/SpawnLocation (runtime only), then `World/Hub`, `World/ScrapRoute`, `World/MirrorRoute`, `World/StormRoute`, `World/AbyssRoute` each inside a pcall. `World/Kit` holds the builders: parts/shapes (ring, tube, curve, cable, ellipsoid), terrain helpers, `Path` (slabs + joint pads sunk by the local slope so they never form a ledge, optional terrain fill/edges/rails), `Smooth` (Catmull-Rom), `ClearCorridor` (carves air above a path, run after all nearby terrain), signs, billboards, lamps, `Relic`, `Waystone`, and the client animation tags. `Main` now pcalls each service's Start so one failure can't stop the others.

**Arenas (`Bosses/ArenaBuilder`):** `Build(origin, name, isWorld)`. A common layout (fight floor of `Radius`, walls with one entrance on local -Z, a ForceField barrier in it, the approach and plaza, the "BossPortal" altar and a "Hub" waystone), plus per-boss theming and `Hazards = { { Name, Run(ctx, arena) } }`. The info table adds `ReturnCFrame` (the world gate plaza). `Types[...]` gains `Region`.

**BossService:** slots are per arena type (`slotInUse[arenaType][slot]`). Slot 1 = the world arena (`WorldDefinitions.Regions[region].Arena`), slots 2+ = copies at `Config.Bosses.ArenaOrigin` (0, 1, 6000), spaced 600. Start-up builds every world arena, puts a dormant anchored `BuildModel` copy of the boss in it (`ShowDisplay`, hidden while slot 1 is in use), and builds a stone monument of each boss beside its hub gate (`BuildMonuments`). `RunHazards(enc)`: a hazard every ~8.5 s (6.5 s in overdrive) × pace (Normal 1.3, Hard 1.0, Nightmare 0.8, none in the Tutorial), first one after 6 s × pace. The new `Context:Push(dir, strength)` is used by the wind gust. `ReturnToHub(player, enc)` returns to `enc.Arena.ReturnCFrame`. The "Start" BossEvent adds `ArenaCenter`, `BossPosition` and `Region` for the client intro camera.

**ExplorationService (new):** handles the "Relic" prompt (once per player, saved in `profile.Relics`, `WorldDefinitions.RelicReward`, a lore toast, analytics `RelicFound`) and the "Waystone" prompt (`"Hub"` always works; a region needs a win against its boss; 3 s cooldown; not mid-fight). Profile schema **v10**: `Relics = {}` (migration, validation, snapshot).

**Client:**
- `WorldController` (new): region look blending (Atmosphere, ColorCorrection, Bloom, Clouds, Sky sizes and star count, ClockTime set instantly), a region title card the first time you enter, the gate reveal sweep (first visit per session), lightning flashes + distant bolts in the Storm region, ambience via `AudioController:SetAmbience`, hides relics you've taken, and animates tagged set pieces within 450 studs of the camera (WSpin/WBob/WSwing/WOrbit/WConveyor/WPulse/WFlicker).
- `BossController`: `GetBossId()`, `IntroCamera(data)`.

**Verified in Studio (automated walks):** every route is walkable from the Forge to its gate and back. Fights in the world Foundry start, run hazards (press + vents logged), and return players to the gate.

## Size, armour & knockdowns (v0.9.3)

- **CombatService:**
  - `bodySize(model)`: (hitbox X·Y·Z)^(1/3); Handlers use `Config.Ragdoll.HandlerBody`.
  - `sizeFactor(curve, attacker, target)`: clamp((size ratio)^Exponent, Min, Max). It's applied to damage (SizeDamage, never vs bosses), knockback (SizeThrow) and knockdown chance (SizeChance).
  - `KnockdownChance(attacker, target, big)`: bosses get Boss.Chance while their Boss.Cooldown is clear; everything else gets (1 − resist) × size factor × 1.25 if big.
  - Resist: Enemy 0, Handler 0.15, Nightmare 0.3 + Defence × 0.0075 + StaggerResist × 0.004 (max 0.85).
  - Bosses are only rolled for signature strikes (Heavy / Ability: / Ultimate:). A floored boss fires CombatFeedback "KnockedDown" (Boss = true).
- **RagdollService:Ragdoll(model, throw, dir, duration, options):** `AllowImmune` lets a KnockbackImmune boss go down, and `SpinScale` slows the topple. `restore` raycasts to the floor and stands any body at HipHeight + Size.Y/2.
- **BossService:** `Context:Alive()` and the Chase tick treat `Ragdolled` like a stagger, so the attack aborts and the next swing waits 1.2 s.
- **StatusService:AddStagger:** a Nightmare's Defence × 0.5 is added to StaggerResist (total ignore capped at 70%).
- **Studio dev bridge:** `ServerStorage.DevBridge` (BindableFunction, Studio only), called as `Invoke(serviceName, method, ...)` on the live services. The command bar runs in its own VM, so `_G` isn't shared.

## The Overhand, hit reactions & animation assets (v0.9.2)

- **Pose sign conventions** (measured in Studio, documented at the top of `HandlerPoses.luau`):
  - Root/Waist: +Y turns LEFT (the right shoulder comes forward), +Z leans left.
  - Shoulder: +Y turns the right arm inward, −Y the left arm.
  - Hips: Y = −(Root Y) keeps the feet planted.
  - The old right-hand punches had their yaw backwards.
- **Studio dev tools in HandlerAnimator:**
  - Workspace attributes `ScrubPose` / `ScrubTime` freeze or loop a move.
  - `ScrubPose = "Lab"` plays `PoseLab` (JSON) live.
  - Moves are tuned by measuring the fist or foot against the HumanoidRootPart (HRP-local: +X right, +Y up, −Z forward).
- **Hit direction:**
  - `MeleeDefinitions` move `HitDir = {right, up, forward}` (striker-local). MeleeService turns it into world space and passes it as `HitDirection` in the ApplyDamage params.
  - CombatService uses it for the ragdoll direction. With `Crumple = true` the throw is 0.3× and downward (legs buckle), instead of a launch.
  - The CombatFeedback "Damage" payload now carries Attacker, Dir, Heavy and KnockedDown.
- **Client reactions:**
  - `NightmareAnimator:Flinch(model, dir, heavy)`: the core tilts and shoves along the force (local space), the head whips 1.4–1.6× further, and a heavy hit sags the knees. It snaps in over about 80 ms and springs back over about 0.3 s.
  - `HandlerAnimator:HitStop(d)`: freezes the striker's pose (or pauses its AnimationTrack) for d seconds, then shifts the pose start time so the move carries on.
  - `EffectsController:ImpactPunch(s)`: FOV −4° and back over 0.3 s, plus a shake. It respects the CameraShake setting.
- **Audio:** `PunchWhoosh` (MeleeController, at HitTime − 0.12 for heavy fist strikes) and `PunchHeavy` (a landed heavy Handler strike, played instead of Hit/HeavyHit).
- **Animation assets:** `src/shared/Animations/<Code>.rbxm` holds a KeyframeSequence per move.
  - In Studio, `HandlerAnimator:Play` registers it with KeyframeSequenceProvider (Config.Dev.PreviewKeyframesInStudio) and plays it through the Animator. A playing track suppresses the Guard and run overlays and clears any finishing code pose.
  - A published `AnimationDefinitions` Id takes priority everywhere.
  - Other players' clients play the code pose through HPose until an Id exists.

## FIGHTER menu, discovery & run styles (v0.9.1)

- **MeleeDefinitions:**
  - `Combos`: { Id, Name, Seq, Inputs, Hint, Move? }, plus `CombosBySeq`. Seq is a Fists combo string, "Counter:P/K" or "Drop:K".
  - `Runs`: { Id, Name, Cost, Blurb }, plus `RunsById`.
  - `Contact`: the stop distance per move (counters slide to it).
- **Profile:** `Combos` { [id] = true }, `Runs` { [id] = true }, `RunStyle`.
- **MeleeService:**
  - `Discover`: on a first-time combo, fires UIState "ComboDiscovered" { Id } and pushes a snapshot.
  - `HandleRun("BuyRun" / "SetRun", id)`: sets the character "RunStyle" attribute.
  - Swing trails: the weapon's "SwingTrail" is enabled only for the swing.
  - Magnet: a boss (tagged "Boss" or KnockbackImmune) gets a MagnetZip, ×4 damage and BossStagger. Anchored targets don't move.
- **HandlerAnimator:**
  - `RUN_STYLES[RunStyle]` is an upper/lower overlay on every rig while it runs (local via MoveDirection, remote via velocity).
  - Every pose crossfades from `pose.From` over `BLEND_TIME`; `RootPos` translates the root.
- **FighterController (client):** tabs MOVES / WEAPONS / RUNS, the discovery banner, `Toggle(tab?)`, `Open`, `Close`, `IsOpen`. It's reached by U, the HUD FIGHTER button, the MENU hub tile and the hotbar ARSENAL button (→ WEAPONS).
- **WeaponModels.StormSpear:** the held javelin. `EffectsController:SpearThrow` flies a matching model (a Model pivoted at its grip).

## Fists, kicks & weapons (v0.9.0)

- **MeleeDefinitions (shared):**
  - `Moves`: Pose, Duration, HitTime, Cancel, Damage, Range, **Arc** (degrees of the swing), Knockback, Stagger, Heavy, Lunge, Leap, Status, Unlock, Weapon (spends a charge), Pull/PullTime, Throw/Speed, Lash.
  - `Styles`: combo strings per weapon (P = attack, K = kick); weapons fall back to Fists for kick-only strings.
  - `Weapons` (Arsenal order): Uses, Recharge, Hold (pose), WalkSpeed (the Magnet: 9). `LoadoutSlots = 3`. `CleanLoadout`.
  - Unlocks by level; all of them in Studio (`Config.Dev.UnlockAllMovesInStudio`). LevelUnlocks lists them.
- **Profile:** `Loadout` (default `{ "Magnet" }`, validated to known unique ids, max 3) is in the Snapshot.
- **MeleeController (client):**
  - `Press(input)` buffers presses made before the current move's Cancel time. `Fire` builds the combo string (continuing within Duration + ComboWindow, else restarting with the press). Special cases: a counter via `CombatController:TakeCounter()`, and a drop kick after 0.35 s of running. It refuses weapon moves while that weapon is recharging.
  - Faces the lock-on target, else the closest enemy within ~65° of the camera direction (never behind you). Slides Lunge studs or leaps, plays the pose, sends `CombatAction "Melee", seq, flag`, and lashes the whip chain (`ChainSimulator:Lash`) just before a crack's HitTime. No strike effect is drawn.
  - **Hotbar:** fists + 3 loadout slots + ARSENAL. Uses ("x5") and a recharge overlay with seconds come from the "Uses_<id>" / "ReadyAt_<id>" attributes.
  - **Arsenal panel:** slot buttons 1–3 and remove; sends `"Loadout", list`.
  - Sets the client-only "InFight" attribute while locked on or within 4 s of a strike.
  - PlayerFX "Pulled" / "MagnetZip" move your own body (or your possessed Nightmare).
- **MeleeService (server):**
  - **Combo checks:** re-resolves the move. A string must continue the previous one inside its window, else it restarts from the last input (no lockups after lag). Nothing faster than the previous move's Cancel time (minus tolerance). Counters bypass this once per step back.
  - **Charges:** weapon moves spend a charge (`SpendCharge`). The last one starts the recharge, and the weapon is unequipped after the move (after the release for a throw). It refuses weapon moves and equips while recharging.
  - **Hits:** stamps `HPose`. At HitTime it hits everything from `TargetsInArc` (QueryRadius around the Handler, filtered by the move's Arc in front, allowing for target size, with vertical reach `HitHeight`) through `CombatService:ApplyDamage`.
  - **Magnet:** grabs the nearest target in its 40° / 30-stud arc and drags it over PullTime 0.5 s (server-owned: LinearVelocity; client-owned: PlayerFX "Pulled"). Bosses and anchored bodies drag you ("MagnetZip"). WorldFX "MagnetBeam" lasts the whole drag.
  - **Spear:** the first target in its 30° / 45-stud arc. WorldFX "SpearThrow" {From, To, Time = distance / Speed}. Damage, Shock and knockdown land on arrival.
  - **Equip** only works for weapons in your loadout. `WeaponModels` are code-built and welded to RightHand. `WalkSpeedCap` is read by HandlerService (the Magnet: walk only).
- **ChainSimulator (client):**
  - A Verlet rope on every client for every Chain Whip: 18 links plus a weight pinned to the cap's ChainStart attachment. 2 substeps, 10 constraint passes, a final no-stretch pass, a heavier end weight, per-point floor raycasts with friction, and frozen beyond 220 studs.
  - `Lash` sets per-point velocities (the far end fastest; sideways for the sweep) and flashes the tip. Remote cracks are triggered from HPose.
  - A server-side physics chain was tried first. Network ownership and the character collision group made it unworkable.
- **Fists:** `MeleeService:ApplyFists` builds a closed fist on each hand when the character spawns: palm, 4 finger rolls with knuckles and creases, and a thumb. Each fist is massless, welded, in the hand's colour, and sized from hand.Size. The flat hand is hidden (Transparency 1), and the ragdoll ignores fist parts.
- **Contact:** each move has a stop distance from the target's body (fists 2.3; kicks, blades and the scythe more). The step-in clamps to it, so strikes land on the body instead of short of it.
- **Drop kick:** `MeleeController:DropKick` sprints at the aim target (SprintRange 30) with a plane LinearVelocity at SprintSpeed 30, looping the `SprintCharge` stride pose, until it's within Range or SprintTime runs out. Then it leaps (Freefall, 26 up, Leap 11 forward) and plays `DropKick`: body ~85° back, legs straight, then a fall onto the back, a sit-up and standing. It sends "Melee K Drop" at the leap. Presses are ignored while sprinting.
- **HandlerAnimator:**
  - Animates every player's character with code poses from `HandlerPoses`. Punches and kicks are UFC orthodox, built from a shared STANCE.
  - Keys may carry **RootPos** (studs) to move the whole body: weight shifting into punches, dips, leaps and sitting on the floor.
  - **Hold overlays** blend in when no move plays: the weapon's Hold pose (on everyone's screen, from the "Weapon" attribute) or the local "Guard" while InFight. The fists charge-run is off while a weapon is out.
- **Controls:**
  - A quick right-click (< 0.3 s, < 8 px of mouse movement) is a kick.
  - Hotbar keys are \` and 1–3. Gamepad X = kick, Y = cycle weapon. Touch: KICK.
- **Removed:**
  - The Scrap Pipe, the old basic attack and the white strike/slash effects.
  - Magnet punching: the Magnet only pulls, then your fists come up.
- **Verified in Studio:**
  - The Magnet sets walk speed 9, pulls once, starts a 15 s recharge and puts your fists back up. Re-equipping it while recharging is refused.
  - The Scythe ran Reap / Return / Whirl / Reap / Return with charges 5 → 0, then went back to fists.
  - The whip chain rests on the floor (weight about 4 studs out) and a crack flings it up and out about 8–9 studs.
  - The spear hit a training dummy with Shock, then started its 10 s recharge.
  - The Arsenal saved a loadout that persisted across restarts.

## Footwork & knockdowns (v0.8.2)

- **World arena terrain fix:** players spawned underground in the Storm and Scrap arenas. Terrain is stored in 4-stud voxels:
  - A fill rounds a partly covered voxel up to solid.
  - A solid voxel's smooth surface is drawn about 2 studs above its top.

  The arena's own under-floor fill (whose top was exactly the floor height) therefore poked up to 5 studs (Storm) or 1 stud (Scrap) through the floor. `ArenaBuilder.clearAbove` now clears the arena from one voxel below the voxel line under the floor, so terrain ends 2+ studs below the floor top, hidden by the floor plates. The approach outside the gate is cleared from the voxel line. It runs again after each arena's own terrain fill. The player spawn is now 5 studs up (was 3).

  Verified in Studio: no terrain above the floor at 45 sample points in all four arenas. A Handler dropped at each arena's spawn lands with its feet exactly on the floor (DiamondPlate / Marble / Slate / Cobblestone).

- **Ragdoll trigger** (`CombatService:ApplyDamage`) applies to Handlers, Nightmares and non-boss Enemies when the attacker exists and any of these hold:
  - the hit is *special*: `params.Heavy`, or a Source starting "Ability:" or "Ultimate:"
  - `knockback ≥ MinKnockback`
  - `dealt ≥ MaxHealth × DamageFraction`
  - a fading burst total (`recentDamage`, linear decay over `BurstWindow`) reaches `MaxHealth × BurstFraction`

  The throw uses `max(knockback, MinThrow)`. A successful knockdown clears the burst. Scrapling AI and swipes pause while Ragdolled.
- **Handler step back:**
  - **Client:** `CombatController:StepBack` slides the character away from the lock-on target (else toward the camera) with a plane `LinearVelocity` and plays the `StepBack` pose. AutoRotate is held off while sliding. `Dodge()` redirects to it when the move direction is more than about 127° from forward (relative to the lock target or the camera).
  - **Server:** `HandlerService:TryStepBack` handles stamina, cooldown, i-frames, and opens the counter window.
- **Counter:**
  - **Client:** `BasicAttack` within `CounterWindow` calls `CombatController:Counter`. It dashes toward the lock-on target, or the best target in range, stopping at reach. It plays CounterPunch or CounterKick (alternating) and sends `BasicAttack, "Counter"`.
  - **Server:** `HandleBasicAttack(player, counter)` calls `HandlerService:ConsumeCounter`, which allows one counter per step back. The counter skips the swing-interval check. After `CounterDuration` it queries a longer box and deals `Damage × CounterDamage` with knockback and stagger (Source "HandlerCounter").
- **Nightmare footwork** (`NightmareAIService`, `Config.Nightmare.Fight`):
  - **`QuickStep`:** a plane `LinearVelocity` slide of `distance` over `DashTime` that keeps facing the target. Raycasts shorten it before walls, and it refuses if there's no floor at the landing spot. Shared `DashCooldown`.
  - **`watchTarget`:** spots a new `ActionSeq` on the current target within threat range and, with `ReactChance`, schedules `reactAt` after `ReactDelay`.
  - **`React`:** may cut its own recovery (never a windup) to StepBack or Sidestep, then sets `counterAt` (`CounterChance`).
  - **`Engage`:**
    - `finisherPending` (set by Combo3 and Heavy) leads to an optional hop out plus a `circleUntil` strafe at `standOff + 2.5`, 40° steps.
    - `counterAt` leads to a DashIn (ignores the dash cooldown).
    - One lunge roll per approach (`lungeRolled`) inside `LungeDistance`.
  - **Animation:** the client NightmareAnimator plays StepBack/Sidestep with the "Hop" style (lean away, crouch, guard) and DashIn with the "Lunge" style.

## Combat feel (v0.8.1)

- **Dive:** `CombatController:Dodge` faces the move direction, sets Freefall, launches with `Speed`/`Hop` and holds the horizontal speed with a plane `LinearVelocity` for `Duration`. It then rolls at `RollSpeed` for `RollDuration` with HipHeight lowered to 70 %. It plays `HandlerAnimator:Play("Dive")`, whose Root turns a full -360° through the roll. `HandlerService:TryDodge` grants `InvulnerableTime` (0.45 s) and refuses while Ragdolled.
- **HandlerAnimator (client, new):** reads `Shared/AnimationDefinitions.Handler`. It points the default Animate script's run/walk at the slot ids after checking they load (PreloadAsync plus LoadAnimation with Length > 0). `Play(slot)` plays the uploaded Id (priority Action2), or else the slot's code pose: keyframed joint angles, smoothstep-blended and written to the R15 joints' `.Transform` in `RunService.Stepped`, so they override Roblox's animations for their duration. Joints can be `Motor6D` (classic rigs) or `AnimationConstraint` (avatars with Roblox's joint upgrade); both are collected. Angle signs were verified in Studio: Root -X leans forward, Shoulder/Hip +X swing forward, Knee -X bends back. With an empty Run Id, `applyCombatRun` layers the charge upper body on top of the default running legs, blended in and out over 0.18 s.
- **LockOnController (client, new):** `Pick` returns the nearest Boss within `Range`, else `CombatController:FindBestTarget`. While locked, Humanoid.AutoRotate is off and the root turns smoothly toward the target. The camera sits behind you (`BindToRenderStep` at Camera+1; the camera shake moved to Camera+2). Locking starts from the current camera CFrame and the follow rate ramps up over `LockInTime`. Releasing blends back to the default camera over `ReleaseTime`. There is no reticle. It auto-releases on death, distance > `BreakRange`, possession, or a WorldController camera reveal.
- **RagdollService (server):** `Ragdoll(model, throw?, direction?, duration?)` replaces every joint not attached to the HumanoidRootPart, whether Motor6D or AnimationConstraint (the latter reuse their own attachments), with an anatomical constraint from `JOINTS`:
  - Knees and elbows are limited HingeConstraints with a weak zero-speed motor acting as friction.
  - The neck, waist, shoulders, hips, wrists and ankles are BallSockets with cone/twist limits and `MaxFrictionTorque`.
  - Each joint gets a NoCollisionConstraint between its two parts.
  - Limbs get high friction and no bounce.

  It sets PlatformStand and the "Ragdolled" attribute. The throw is applied by `RagdollService.Throw` (server, Nightmares) or by the PlayerFX "Ragdoll" handler (client, Handlers). It goes to **every assembly root**, with velocity + spin × offset. With physics joints each limb is its own assembly, so pushing only the HumanoidRootPart leaves the body folding into a kneel. The spin tips the body over backwards, away from the hit. After `Duration` it waits for the body to settle (speed < 4, max 2 s), then restores. Nightmares are stood upright by PivotTo; their Motor6Ds snap back rigidly. A Handler's client handles its own get-up in `HandlerAnimator:GetUp`, because AnimationConstraints are soft and Roblox won't right a body lying flat:
  - It raycasts the floor and computes the facing (face-down: toward the head; face-up: toward the feet).
  - `snapToRig` rebuilds the body around the root by walking the joint tree.
  - It sets GettingUp and starts HipHeight at 25 %, tweening it back.
  - It plays GetUpFront or GetUpBack.

  It is triggered from `CombatService:ApplyDamage` for Heavy hits with Knockback ≥ `MinKnockback` on Handlers and Nightmares (bosses are KnockbackImmune). NightmareAIService treats Ragdolled like staggered.
- **Verified in Studio:**
  - The dive moves and spends stamina, and the charge run shows on the upgraded-joint avatar.
  - Lock-on glides in and out.
  - The Handler is thrown, lies flat (torso horizontal) for ~1.3 s, then rises to fully upright in ~0.8 s.
  - A Nightmare is thrown and recovers upright.

**Not done yet / ideas:** a distant "Backdrop" pass (`World/Backdrop` is optional and loaded if present), per-region music (only ambience hooks exist), AFK gym area, more side secrets.
