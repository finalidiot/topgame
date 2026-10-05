# Workspace policy

Read this file before producing task output. The Task 002C.5 / 002C.5.1 / 002C.5.2
stack received human playtest acceptance on 2026-10-05 and is approved as the next
main milestone. After the milestone merge, branch new work from the updated main
unless a task explicitly requires another base. Historical task reports may still
say PENDING HOME HUMAN PLAYTEST because they record the state at their own checkpoint.

## Authoritative locations

| Content | Location |
| --- | --- |
| GitHub repository | https://github.com/finalidiot/topgame |
| Working game repository | `C:\GPT GAME BUILDING\GyroBrothers` |
| Active Git metadata and object store | `C:\GPT GAME BUILDING\GyroBrothers\.git` |
| Active LFS objects | `C:\GPT GAME BUILDING\GyroBrothers\.git\lfs\objects` |
| Registered historical checkouts with preserved local work | `C:\GPT GAME BUILDING\GyroBrothers-Worktrees` |
| Large QA and human review | `C:\GPT GAME BUILDING\GyroBrothers-QA` |
| Newest validated playable Windows executable | `builds/latest/SpinningMetal.exe` |
| Milestone checkpoint | `builds/checkpoints/<TASK>/SpinningMetal.exe` |
| Release candidates/public distributions | `builds/release/` |
| Editable production masters | `assets/source-art/` |
| Runtime art, audio and data | `assets/` outside `source-art/` |
| GDScript regression code and deterministic drivers | `tests/*.gd` plus their `.uid` files |
| Compact versioned evidence | `tests/results/` |
| New task reports | `docs/tasks/` |
| Art/workflow notes | `docs/art/` |
| Architecture notes | `docs/architecture/` |
| Human playtest guides | `docs/playtests/` |
| Workspace tools | `tools/workspace/` |
| Build tools | `tools/build/` |
| Windows playtest/preset launchers | `tools/playtest/windows/` |

Existing `assets/top/`, `assets/powers/`, `assets/ui/`, `assets/audio/` and root
scene/script paths are preserved. Production masters in `assets/source-art/`
include historical root masters and `power_identity_002c5/`; runtime PNGs and
their `.import` settings remain separate. New families may use mechanic-named
subdirectories under source-art. Preserve native layers, tags, pivots, timing,
metadata and source/runtime parity. Organisation must not repaint assets.

Existing flat `tools/` art/audio/export/capture programs remain in place to avoid
breaking their repository-relative imports. New tooling belongs in the relevant
subdirectory. Historical `TASK-*.md`, `README.txt` and `QA.txt` remain at the root;
they are historical records, not a second active policy. Their original absolute
QA paths and old `releases/windows` references describe earlier deliveries.
Consult this policy and the migration ledger for the current locations. New task
reports use `docs/tasks/`. Test fixtures that must be versioned belong in
`tests/fixtures/`; do not move valid runtime/test resource paths for aesthetics.

## QA output and naming

```text
GyroBrothers-QA/
  <TASK>/
    video/         final review movies and phone clips
    images/        final matrices, comparisons and review screenshots
    frames/        raw frame sequences
    logs/          engine output and verbose test logs
    manifests/     provenance, capture metadata and migration ledgers
    benchmarks/    performance output
    temp/          encoding/export intermediates; never a final deliverable
    archive/       coherent historical task trees retained during migration
  archive/
    builds/        historical packaged checkpoints
    inactive-backups/  verified historical Git/LFS backups; no active backend
    tools/         externally supplied capture runtimes
  temp/
```

Use task IDs such as `002C.5`, `002C.5.1`, `002C.6`, `003A`. File names should
describe the task and purpose, for example `002c5_power_art_showcase_v2.mp4`,
`002c5_power_visual_matrix.png`, `002c5_results.json`. Timestamps belong in
metadata or preservation directories, not the primary identity of final output.

Run `python tools/workspace/workspace.py create-task 002C.6` to prepare an empty
task workspace; this does not begin that content milestone. The shared helper
honours `TOPGAME_QA_ROOT`, defaulting to the sibling `GyroBrothers-QA`. Reusable
tools must accept CLI output paths or use this helper. Do not hard-code another
task's absolute output directory. Engine/tool configuration uses `TOPGAME_GODOT`,
`TOPGAME_ASEPRITE` and `TOPGAME_FFMPEG`, with PATH lookup and documented local
installation fallbacks. Archived FFmpeg lives at
`GyroBrothers-QA/archive/tools/imageio_ffmpeg/binaries/`.

Historical QA trees are archived intact to retain paired movies, frame sequences,
one-off scripts and relative provenance. Verified final review artifacts are
available in each task's standard categories. The full old/new file ledger is
in `002C.5.1/manifests/`; do not mistake an immutable historical path in a report
for a reusable tool default. Never manufacture new provenance by changing old
result JSON paths or overwriting historical media. Unknown material is preserved.

## What belongs in Git

Track production code/scenes/configuration, runtime PNG/WAV/fonts/data, native
`.aseprite` masters, palettes, `.uid` sidecars and meaningful `.import` settings,
tests, fixtures, tools, docs and deliberately compact reproducibility JSON.
`tests/results/` is historical evidence with its original milestone scope; it
does not imply the current suite was rerun. New compact summaries should link
to external detailed evidence and avoid bulk frame/telemetry duplication.

Do not commit `.godot/`, generated builds, videos, screenshots/contact sheets,
frame dumps, encoder intermediates, verbose logs, local test saves or caches.
The narrow ignore rules do not blanket-ignore native art, runtime PNG/WAV or
JSON. EXEs are normally local under ignored `builds/`. A forward `*.exe` LFS rule
handles any explicitly approved versioned distribution. Current native masters
and WAVs are small ordinary Git assets; no history rewrite or mass LFS conversion
is authorised by workspace organisation. Historical LFS objects remain intact.

## Windows build and promotion

From a clean, committed checkout with Godot 4.7.2 and its Windows templates:

```powershell
python tools/build/windows_checkpoint.py build --task 002C.5.1 --checkpoint 002C.5 --archive-checkpoint
```

The helper snapshots exact tracked HEAD source into a fresh external QA staging
directory, imports it without old editor caches, exports an embedded Windows
executable, hashes it and runs the actual packaged rendered smoke flow. Smoke
uses an explicit isolated collection path, records real engine logs and required
menu/gameplay captures, and checks that the real user's collection hash did not
change. Its injected flow victories are labelled fixtures, not gameplay/balance
acceptance. Failed exports or smoke checks never promote. A completed cold import
that exits with the observed Windows native crash code `0xC0000005`, without
script/import errors, may be retried once in the same fresh staging directory.
Both attempt logs remain evidence; the final import must exit successfully.
Script errors, other process failures and packaged smoke failures are not retried.

Only a validated manifest whose binary/evidence hashes still match can be
promoted. The helper stages the complete payload, preserves the previous latest
and checkpoint (including unknown files), and rolls back if promotion fails.
README/hash/manifest travel with the executable. Optional checkpoint promotion
uses one folder per milestone, preserving an earlier revision externally rather
than creating dozens of nominal checkpoints. To promote an already validated
candidate use `python tools/build/windows_checkpoint.py promote --candidate
<payload-directory> --checkpoint 002C.5`.

`builds/latest/README.txt` states the exact source Git SHA, task, UTC build date,
controls and the acceptance status recorded for that checkpoint. The default editor export targets
`builds/temp/windows/`, so manual export cannot overwrite validated latest.
Release output is reserved for an explicitly authorised distribution. Substantial
future tasks must finish with a validated human-playable `builds/latest` unless
explicitly exempted. An existing collection continues; testing should use an
isolated save rather than resetting the human's collection.

## Audit, archive and cleanup

Run `python tools/workspace/workspace.py audit --out <external-manifest.json>`
for large untracked files, unexpected root folders, QA media inside the repo,
stray EXEs, hash duplicates and stale absolute task defaults. Review findings;
the auditor never removes anything.

`python tools/workspace/workspace.py clean-temp --task 002C.5.1 --dry-run` is a dry-run
(also the default when neither action flag is supplied).
It prints each exact known `.tmp`, `.part` or `.raw` intermediate under that
task's `temp/`. Add `--apply` only after checking the list. It does not delete
directory trees, final media, source art, JSON, build staging, logs or unknown
content, and never follows symlinks. Broader cleanup requires explicit inventory,
classification, hashes, confirmed authoritative copies, reference repair and
validation first. Same names or timestamps do not prove duplication.

**Never automatically delete:** unknown files; unique/uncommitted/untracked work;
synced ChatGPT `sources/`; the human's saves; source-art masters; final reviews;
provenance; Git/LFS storage; any historical checkout with unique work; unrelated
projects. `C:\GPT GAME BUILDING` is shared with unrelated projects. Their files
and folders are outside this task's management boundary.

The canonical project is now a normal self-contained Git working repository.
Its active metadata, refs, objects, reflogs and LFS store are inside
`C:\GPT GAME BUILDING\GyroBrothers\.git`. Copying/backing up the whole canonical
folder preserves the repository without depending on QA. The four registered
historical checkouts live under `C:\GPT GAME BUILDING\GyroBrothers-Worktrees`.
That separate root contains preserved unique local work and is essential source
history, not generated output. Use `git worktree list` and supported worktree
operations; never reset, clean, prune or delete those checkouts automatically.

QA is non-authoritative for Git, LFS, live checkouts and production source. It may
be relocated or regenerated without disabling normal Git operations. Preserve
human-review artifacts, provenance, unknown historical material and deliberate
backups rather than treating every QA file as disposable. Generated caches and
intermediates may be reviewed for cleanup using the conservative rules above.

The pre-hotfix Git/LFS snapshot at
`GyroBrothers-QA/archive/inactive-backups/git-storage-909c225/git-metadata.inactive-backup`
is an **inactive verified backup**, not a repository backend. No registered
checkout points there. Its old paths and reflogs are recovery evidence only;
do not repair that snapshot into the active topology. All evidence about the
conversion is in `002C.5.1/manifests/git-storage-hotfix/`. The historical 002B
copied Git pointer remains inactive documentation, never a registered worktree.
