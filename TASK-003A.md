> Historical reference: this report describes the original Task 003A branch and its original artifacts. Its existing source is restored in the corrected Task 002C.5 checkpoint; see TASK-002C5.md for current build hashes, integration validation and launch paths.

# Task 003A â€” Starter ceremony and persistent collection foundation

Branch: `task-003a-starter-collection`.
Exact accepted starting branch: `origin/main`.
Exact starting SHA: `0c6225f5428e874621f14837e37df47bad505fa7`.
Fetched and verified the requested main, inspected menu/garage/preferences,
part definitions, starter handling, Run flow, preview/art and input suites,
confirmed a clean tree and passed all 24 accepted baseline suites before
branching. The final SHA is supplied in delivery/Git history to avoid embedding
a commit's own hash. No merge to main. Human acceptance remains pending.

## First-save experience

A missing collection begins with **zero owned parts**, regardless of an old
prototype.cfg practice build. BEGIN opens three 4x animated machine previews
at native 640x360. All three remain visible and freely inspectable. Breaker is
restless/aggressive; Bastion is planted; Vane has a directional orbit. Copy is
short and uses the actual existing identities rather than invented statistics.

Choosing a card opens MAKE IT YOURS, with a large preview, component breakdown
and separate CHOOSE [NAME] / BACK confirmation. No ownership is written before
confirmation. A successful safe write precedes `[NAME] IS YOURS`, a brief accent
flash, component reveal and the existing restrained acquisition cue. The 1.4s
ownership beat enters the Workshop automatically; a new deliberate Continue is
accepted after 0.8s. Existing input-release protection prevents held Confirm
from choosing across screens. Back from confirmation restores the chosen card.
No forced inspection, copied creature-game presentation or long cutscene.

Subsequent title flow is CONTINUE TO WORKSHOP. LAUNCH OWNED TOP uses equipped
components and goes directly to the temporary starting-power draft. Normal
Runs never ask for the three historical starters again.

| First choice | Only owned Blade | Only owned Ratchet | Only owned Bit |
|---|---|---|---|
| Breaker | `blade:smash` | `ratchet:high` | `bit:flat` |
| Bastion | `blade:guard` | `ratchet:low` | `bit:ball` |
| Vane | `blade:hook` | `ratchet:mid` | `bit:rubber` |

These are three unique parts per save. The 11-part catalogue remains intact;
unchosen starters' components are unowned, not removed or class-locked.

## Persistent architecture and schema

`scripts/collection_save.gd` is a scene-independent RefCounted save/API. Normal
location is `user://collection.json`, in Godot's existing game user-data folder.
Schema **1** whitelists only:

```json
{
  "schema_version": 1,
  "starter_selected": "breaker",
  "owned_part_ids": ["bit:flat", "blade:smash", "ratchet:high"],
  "equipped_build": {"blade": "smash", "ratchet": "high", "bit": "flat"}
}
```

Ownership IDs qualify immutable catalogue keys with category. Labels, positions,
array indexes and translated names are never save identities. Equipment uses
those same existing keys. Owned arrays are sorted/unique; snapshots are copies.
Catalogue metadata (including future rarity) stays in part definitions, not
redundantly in inventory records. No unused currency or fake progression data
is populated. A later schema can add actual currencies/collection metadata
without replacing these identity or ownership APIs.

Public API:

- `load_save()`, `is_initialized()`, `can_launch()`, `snapshot()`.
- `owns_part("blade:smash")`, `owned_parts("blade")`, `owned_count()`.
- `grant_part(id)` returns `{ok,status}`: `newly_acquired`, `already_owned`,
  invalid/uninitialized/read-only/write failure. Repeated grants never duplicate
  ownership and the already-owned path does not rewrite the file.
- `can_equip_build(build)`, `equip_build(build)`, `equipped_build()`.
  Equipment requires exactly three valid, owned category components; catalogue
  default substitution cannot accidentally equip or acquire missing parts.
- `initialize_starter(id)` is irreversible for the save; only explicit developer
  reset can reopen the historical choice.
- `part_id(category,id)`, `split_part_id(id)`, `is_valid_part_id(id)`.
- `reset_collection(explicitly_requested=false)` rejects implicit calls.

003B can grant a part and equip a full legal owned build through these APIs.
Duplicate conversion, packs, shop, prices, odds, rarity balance, boss rewards
and all real-money systems remain absent.

## Safe persistence and migration

Mutations stage candidate memory, write/flush a neighboring `.tmp`, verify its
bytes, preserve the previous valid collection via `.bak.tmp` â†’ `.bak`, then
rename the verified primary staging file. Memory commits only after success.
First ownership also seeds a backup. Interrupted staging files are never loaded.
A damaged primary cannot overwrite a valid backup with corrupt bytes. The unit
suite injects partial writes and real rename failures.

Loads validate all categories/IDs, ignore unknown IDs, deduplicate known entries
and strictly validate equipment. A usable existing owned assembly can replace
invalid equipment without granting any parts. If none exists, equipment stays
empty and Launch is blocked; known ownership/history is retained. Malformed
primary falls back to its previous valid backup. This may roll back the most
recent acquisition/equip. Without a valid backup, corrupt data is preserved and
collection writes/launch are blocked rather than silently granting content.
Future schema versions are read-only, including a newer file appearing after
an instance loads. See the documented deliberate test reset below.

Schema-0 fixture migration accepts `starter_id`, category-local `owned_parts`
and `build`; it sanitizes them into v1 in memory. A successful later mutation
writes v1 safely. Existing prototype.cfg has no collection: it remains an
independent settings/practice build file and triggers a fresh ceremony.
Preferences are never deleted or silently reset by collection migration.

The lightweight save is intended for one active game instance. Close other
instances before reset. Stale loaded state is rejected before overwriting a
newer ownership/equipment state; Retry reloads the latest collection. There is
no database or multi-process transaction framework.

## Workshop, construction and Run separation

The Workshop shows the current assembled preview, **3 / 11 PARTS OWNED**, counts
by category and historical FIRST CHOICE. Owned entries show EQUIPPED/OWNED;
other catalogue entries remain focusable NOT OWNED inspection tiles. Selecting
one leaves equipment/save/focus intact. No pricing or misleading Buy button.
Owned part selection uses the strict save API and restores selection focus after
rebuilding the menu. Launch is unavailable for incomplete/read-only data.

Historical starter is a collection memory, not a permanent class. The accepted
prototype has extra Run handling in `Starters.HANDLING`, beyond modular part
stats. `identity_for_build()` now derives identity from the **current complete
assembly**. Exact Breaker/Bastion/Vane configurations retain their accepted
handling and enamel/motion art. Any mixed assembly uses ordinary part stats and
neutral custom identity, even if every original component is later replaced.
This compatibility bridge preserves feel without a large physics rebalance;
a future physical-build tuning pass can move those authored profiles into parts.
No invisible starter bonus is serialized in collection.

RunContext, powers/ranks/mutations, XP/level, director, RPM, enemies, cooldowns
and survival clock remain temporary. Collection writes do not run on power
drafts, deaths, restarts or threat transitions. Run restart reads the persistent
equipped build and creates fresh temporary state. End returns to owned Workshop.
One-launch combat and all accepted C.1â€“C.4 mechanics remain intact.

Quick Duel and PRACTICE GARAGE are labeled independent testing modes. The full
catalogue and signature practice presets remain usable without ownership.
Their builds never grant parts or overwrite collection equipment. Practice
Garage's owned-Workshop route cannot launch an unowned custom Run.

## Art, input and production files

No new art library was needed. Existing `starter_blade_accents_002b1.aseprite`
remains editable/unmodified: 48x48, 24 frames; layers preserved authored steel
silhouette / identity enamel plates / rotational rim signature bands; pivot
(24,40). Eight-phase tags `breaker` 65ms, `bastion` 160ms, `vane` 100ms. Existing
nearest-filtered `assets/top/starters/*_spin.png` exports are reused. Ceremony
and confirmation use integer 4x; Workshop 3x. Existing source handoff is
`assets/source-art/POWER-002B1.txt`; no source flattening/re-export drift.

Preview identity derives from current components. UI animation is cosmetic;
physics, power timing, director RNG, RPM equations and fixed camera are untouched.
Audio reuses UI detent, focus and acquisition cues through the existing bounded
pool. Keyboard/controller/mouse share actual input dispatch. Native captures
check dominant silhouettes, clear focus, readable names/copy, component rows,
locked state and incomplete-assembly presentation.

Major files: `collection_save.gd`, `main.gd`, `menus.gd`, `top_preview.gd`,
`starters.gd`; new collection save/full-flow/UI suites and ceremony capture;
legitimate first-save changes in controller/flow/continuous/ramp regressions;
README/report and Windows checkpoint.

## Validation and checkpoint artifacts

All **27 relevant suites pass** on the final product code: spin economy,
Threat Director, continuous Run, RunContext, flow, combat architecture, menus,
controller, powers, swarm, presentation, progression, starters, starter physics,
XP observer, ramp integration, card assets, escalation progression/physics/
integration/completion/assets, RPM replay, signature presentation, collection
save, collection full-flow and collection UI. Accepted tests were preserved;
changed first-save assertions now use permanent ownership instead of a Run
starter selector. Pure unrestricted menu/catalogue fixtures remain explicit
practice unit tests.

New coverage: **271 collection-save checks**, **395 collection full-flow checks**,
**1,996 headless / 2,008 native collection-input/UI checks**. All three fresh
starter paths reach a real launch, fixture defeat, Run restart/end, new Main
instance and disk reload with only their three components. Future acquisition
and mixed owned equipment, duplicate grants, locked equip, temporal-state
separation, explicit reset, corrupted/future data, stale two-window initialization
and Retry reload are covered. Controller uses real mapped synthetic device 3,
plus keyboard and mouse; it does not claim physical hardware acceptance.

The retained controller suite passes 676 checks; menu fixture 1,399; signature
presentation 3,177; two real natural seeded Runs retain exact reproducible RPM
curves/events/accounting/progression in RPM replay. Native ceremony/title/owned/
Workshop/incomplete/error captures include shaped text bounds; 17 standalone
native states also passed 326 text-fit checks. UI remains bounded; this task adds
three menu previews, no combat particles, entities or per-frame save writes.

Six separate source-engine process probes (write then reopen for each starter)
pass 14/12 checks, verifying disk ownership, actual Run launch/defeat/return and
absence of collection writes from temporary powers. Release export succeeds.
The actual packaged Windows executable also passes its full integration smoke:
first-save confirmation/ownership/Workshop, Quick Duel/input, powered Run,
10 continuing threats, live drafts/mutations, defeat/restart and Workshop return.
Those outcome/XP fixtures are architecture evidence, not natural play balance.

Windows checkpoint: `C:\GPT GAME BUILDING\GyroBrothers\releases\windows\SpinningMetal.exe`.
Embedded game, Windows x86_64, 110,041,808 bytes. SHA-256:
`27866679633c2ad1282f8a452cc7ca980d8b278943c28870ebb105d7259cb870`.
Adjacent `SpinningMetal.exe.sha256` records the same hash. Large executable uses
existing Git LFS workflow. No large video is committed.

Mobile review: `C:\GPT GAME BUILDING\task-003a-qa\003a_starter_ceremony.mp4`.
**26.33s, 1.21 MB, H.264/AAC, 1280x720**. Cycles all three real animated previews,
confirms Bastion, performs its safe ownership write and enters Workshop showing
only Guard/Low/Ball owned; locked Hook inspection cannot equip it. Real GUI input
and real UI audio. `003a_starter_ceremony.json` records initial zero ownership and
final three stable IDs. Clip-only audio gain improves phone review without
changing game mixing. Representative encoded frames at 4/14/15.7/24s were viewed
and names, component rows, 3/11 count and NOT OWNED state remain readable.

Godot MovieMaker initially fixes its size from the project window override;
resizing later invokes internal bilinear resampling. Final capture therefore
uses a disposable QA copy with startup window 640x360, lossless native PNG frames,
then FFmpeg nearest-neighbour 2x scaling. Product configuration is unchanged.
Logs, captures and manifest are outside Git in `C:\GPT GAME BUILDING\task-003a-qa`.
No regression found in tested scope. Human emotion/clarity/physical-controller
acceptance remains pending.

## Deliberate development reset and human checklist

Normal collection is `user://collection.json`; preferences are prototype.cfg.
Tests/review use isolated paths. Main smoke mode defaults to a unique isolated
collection and suppresses preference writes. No ordinary UI reset/change-starter
button exists. These explicit PowerShell commands use Godot's user-argument `--`:

```powershell
# Fresh isolated human review; does not touch the normal collection:
.\SpinningMetal.exe -- --collection-path=user://review/003a.json
# Deliberately repeat that isolated first-save ceremony:
.\SpinningMetal.exe -- --collection-path=user://review/003a.json --reset-collection
# Deliberately erase the NORMAL collection (preferences are retained):
.\SpinningMetal.exe -- --reset-collection
```

Reset removes only this collection's exact primary/backup/staging filenames.
Back up the collection first if its choice should be retained. A failed explicit
reset reports an error rather than pretending a new collection was created.

Human test: Begin a fresh review save; inspect all three personalities; choose
and confirm one; watch ownership; inspect Workshop and attempt a NOT OWNED tile;
launch, choose a power, play/end a Run; return and verify the same three parts;
close/reopen and verify persistence. Judge importance/clarity of the first choice,
three personalities, ownership satisfaction, locked-part anticipation and whether
it feels like the start of a collection rather than a permanent class restriction.

Known limits: only starter acquisition exists in normal play, so the initial
Workshop offers one owned part per category. Recovery of an incomplete damaged
save may require explicit reset/backup restoration. If future rewards fill its
missing category, callers should equip a complete owned build via `equip_build`
(or reload for conservative fallback), rather than expect `grant_part` to choose
a loadout. Rarity/shop/duplicate conversion/boss drops are intentionally future
work. Physical controller and subjective ceremony feel are pending human testing.
Web checkpoint was not rebuilt. No acceptance claim is based on automated input.
