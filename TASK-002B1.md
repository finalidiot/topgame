# Task 002B.1 - roguelite ramp and identity

The Run now starts with an animated Breaker, Bastion or Vane selection, followed by a deterministic power choice before Encounter 1. Meaningful combat fills a visible Level bar. An earned choice pauses the current encounter, presents animated cards, commits once, and resumes that same encounter with the new power active. XP replaces the old fixed-slot draft schedule. The six existing powers and 24-top Ammunition Waves remain functional.

## Delivery and baseline

- Repository: `https://github.com/finalidiot/topgame.git`.
- Starting SHA: `8fa737bacf798d4b2c80e030aeb5103843452fb6`, verified clean on `task-002b-first-broken-build` before implementation. Eight relevant baseline suites passed before changes.
- Delivery branch: `task-002b1-roguelite-ramp`, created directly from that SHA. No merge to main.
- Final SHA is supplied in the delivery message and branch history; it cannot be embedded in its own commit.
- Windows build: `releases/windows/SpinningMetal.exe`.

The first controller checkpoint received the human feedback, "It feels ok, need to be far more extreme though." The final pass responds with stronger authored starter handling and lower early XP costs. The final stronger build has not received a detailed human feel verdict. Automated combat, rendered inspection, and human feedback are distinguished throughout this report.

## Final starters and measured behaviour

| Identity | Physical assembly | Authored Run behaviour |
| --- | --- | --- |
| Red / Breaker | SMASH / HIGH / FLAT | Acceleration 1.32x, speed parameter 1.20x, collision attack 1.30x, natural orbit 1.50x, bank centring 0.85x. Restless angular blade. |
| Blue / Bastion | GUARD / LOW / BALL | Acceleration 0.72x, speed parameter 0.78x, physical mass 1.35x, drain 0.90x, natural orbit 0.25x, bank centring 1.35x, wobble recovery 1.30x. Broad reinforced blade. |
| Green / Vane | HOOK / MID / RUBBER | Acceleration 1.18x, speed parameter 1.12x, mass 0.94x, collision attack 1.05x, drain 0.82x, orbit 1.60x, wobble recovery 1.15x. Swept directional blade. |

Profiles are centralized in `scripts/starters.gd` and apply only to the player in an authored Run. Garage parts, custom Runs, rivals and Quick Duel keep original part physics. Each starter has a real different assembly, separate blade silhouette, enamel plates, animated motion personality, strengths and weakness. Colour reinforces these differences.

Deterministic measurements with no Run Powers compare each authored starter with its own neutral assembly. Breaker reaches 189.30 velocity units after one second versus 141.52 (+33.76%), deals 30% more collision spin damage, and retains its high spin drain and poor recovery. Bastion reaches 101.38 versus 145.10 (-30.13%), takes 16.28% less recoil, drains 11.13% less spin and recovers wobble 30% faster. Vane reaches 193.66 versus 163.43 (+18.50%), spends 17.56% less spin, and recovers wobble 15% faster. These are controlled fixture measurements, not player opinions. Raw evidence: `tests/results/task002b1-starter-results.json`.

Alternatives were exercised in simulated motion/contact diagnostics. BALL gives Bastion more grip/stability and better braking than NEEDLE: brake velocity 29.02 versus 33.21, steering turn 45.0 versus 38.34 degrees; NEEDLE spends less spin but is less controllable. RUBBER gives Vane cleaner turns than BALL (49.45 versus 44.48 degrees) and stronger braking (26.11 versus 29.36), at a spin cost. HOOK preserves glancing shear and a distinct swept silhouette; BALANCE/RUBBER was also measured. Selection of these assemblies is a design judgment supported by diagnostics, not a claimed human comparison test.

## XP, level costs and safe drafts

`scripts/run_progression.gd` owns all progression tuning. XP awards require player attribution and valid monotonic combat events:

- Accepted direct collision, severity at least 0.22: 2 XP. Heavy collision above 0.50: 4 XP.
- Pair cooldown: 1.15 active seconds. Global accepted-collision cooldown: 0.30 seconds.
- Credited full rival ring-out/spin-out: 18 XP.
- Credited small-top elimination: 3 XP, including impact destruction.
- Completed swarm wave with a credited player elimination: 6 XP.

Weak touches do not establish full-rival elimination credit. Small-top attribution expires; an incoming full-top power cause must still be live when applied. A meaningful direct full-rival contact retains credit within that encounter. Duplicate events, eliminations and waves are rejected. Retirement, cleanup, timeout/draw animations and passive time award no XP. Power impulses can establish valid attribution without changing power behaviour.

| Earned level | Incremental cost | Cumulative XP | Unique powers after claim |
| --- | ---: | ---: | ---: |
| 2 | 18 | 18 | 2 |
| 3 | 22 | 40 | 3 |
| 4 | 36 | 76 | 4 |
| 5 | 56 | 132 | 5 |
| 6 | 84 | 216 | 6 / MAX |

The starting power is free. Overflow is retained and multiple earned entitlements queue in order. Every offer has up to three unowned powers; the last offers naturally narrow as the six-power pool empties. No duplicate ranks, class locks, starter-exclusive pools or weighting were added. Stable draft IDs and run seed checks guard exactly-once acquisition. At six powers the bar reads FULL BUILD / MAX.

The observer publishes XP only after a complete fixed simulation tick. Drafts stop positions, spin reserve, power state/cooldowns, encounter clock and swarm scheduling. Resume appends the acquired power without resetting the battle or replenishing a spent Second Wind. Input requires neutral steering and released Burst/brake. A result-time entitlement returns to results after acquisition; restarting creates a fresh starting draft for the same starter.

## Measured ramp and swarm payoff

`tests/test_ramp_playthrough.gd` runs real combat using sampled imperfect pursuit, partial steering, guarded Burst and edge braking. It never injects victories, teleports tops, refills spin or fabricates power procs. Active seconds exclude countdowns, drafting and acquisition. It remains a bot diagnostic, not a human stopwatch test.

Twelve runs (three starters, seeds 421/7341/1609/975) produced a first earned choice at 7.58-17.12 active seconds: median 13.00, mean 12.55. Eight reached one minute and held four or five powers at that moment (median four). Four failed earlier and held two powers; they are excluded from the one-minute statistic. Breaker reached a minute in 2/4 trials, Bastion 3/4, Vane 3/4. Bastion completed the eight encounters in 3/4 trials; Breaker and Vane ultimately lost in this sample. This reveals a real aggression/survival tradeoff, not a universally easy Run. Raw evidence: `tests/results/task002b1-ramp-results.json`.

The earlier softer pass measured first choices at 14.02-21.35 seconds and three/four powers in successful first minutes. The final tuning deliberately goes faster than the original 15-25 second target in response to the user's request for a more extreme feel.

Isolated Ammunition Waves trials start with one actual power. Breaker earns Iron Comet at 5.45 seconds in wave 1, then Impact Wake at 10.12 seconds in wave 2. After resuming, Wake triggers five times in that same encounter. The swarm clears at 27.15 seconds with 16 credited eliminations and eight natural retirements. Bastion earns Wake at 11.68 seconds in wave 2 (three procs); Vane at 6.70 seconds in wave 1 (four procs). All spawn the original 24 tops; peak active is nine in these trials, below the preserved cap of twelve. No cleanup shortcut is used. This demonstrates a concrete before/after mechanic; whether it feels memorable requires human feedback.

## Art, acquisition, Level bar and audio

Power cards now use bold 64x64 mechanical illustrations instead of relying on tiny HUD symbols. Six distinct phenomena have six-frame authored loops: toothed pressure race, collapsing/reforming bearing, hot overloaded rotor, directional rebound wedge, staggered rotor echoes and linked pressure detonations. Large names, short truthful copy, category words and discrete high-contrast focus keep comparison quick. Only the focused card animates; integer placement and nearest filtering preserve pixel edges.

Editable production sources:

- New `assets/source-art/power_cards_002b1.aseprite`: 36 frames, five named RGBA layers, six stable tags, named 12-colour palette, contact pivot (32,32), durations 110/90/75/75/100/170 ms per loop.
- Revised `assets/source-art/power_icons_002b.aseprite`: six independently authored 16px compact mechanical HUD symbols with the original stable IDs and pivot.
- New `assets/source-art/starter_blade_accents_002b1.aseprite`: 24 frames, three named layers, named 16-colour palette, three tags, contact pivot (24,40), Breaker/Bastion/Vane timing 65/160/100 ms. Original angular, broad and swept silhouettes are preserved exactly.

Installed Aseprite opened all three masters and exported pixels that match the runtime PNGs exactly. Independent binary inspection also verified layers, tags, pivots, timing and pixels. Ordinary export tools read edited sources and do not overwrite artist edits; explicit author switches rebuild the initial sources. `assets/source-art/POWER-002B1.txt` documents this workflow. Existing combat FX and small-top art masters are preserved.

A level completion adds a 0.18 second hit before the draft. Acquisition animates the illustration/name with a mechanical pulse and existing acquisition strike, then returns after 0.50 seconds. Starting, mid-battle and result-origin prompts respectively say LAUNCH, RETURN TO COMBAT and CONTINUE.

The compact HUD displays starter identity, RPM, owned powers, encounter and a separate bottom Level bar. XP visibly advances, flashes near 80%, announces completion, and becomes MAX at the pool limit. Five new finite cues cover focus, selection, near-level, level-up and resume. There is no constant XP ding. The existing eight-channel audio cap, priorities and contact aggregation remain. Camera and isometric composition remain fixed.

## Controller and visual inspection

The human agreed to test with a controller and reported the initial checkpoint "feels ok," then asked for a more extreme pass. Model was not supplied. No detailed per-action report was received for steering, Burst, brake, pause, focus restoration or held Confirm. The final stronger build was supplied as a second checkpoint. Full physical-controller acceptance is therefore unconfirmed; synthetic tests are not presented as hardware proof.

Headless synthetic-controller coverage passes 685 checks across starter and starting draft, combat, pause, mid-battle draft, acquisition, swarm, failure, restart and completion. It exercises fresh-confirm gates, stick hysteresis/centering, discrete navigation, restored focus and neutral combat rearming. Native synthetic tests encountered ambient physical input and are excluded from the claimed controller pass.

Rendered starter/cards/acquisition/HUD/swarm images were visually inspected at native 640x360 and 2x integer scale. Starter silhouettes and motion families differ; focused borders and enlarged illustrations read clearly; copy stays within cards and the Level bar stays outside the arena. Rendered integration and complete-flow smoke fixtures were inspected. Smoke victories and XP are explicitly injected flow fixtures, separate from the unmodified combat measurements above. Desktop automation did not provide a reliable direct manual-play session, so no agent human playtest is claimed.

## Automated verification and performance

All relevant suites pass on Godot 4.7.2. Existing power/swarm/presentation coverage is preserved.

| Suite | Checks |
| --- | ---: |
| Flow | 169 |
| Run context | 316 |
| Combat architecture | 35 |
| Menus (headless / rendered) | 1324 / 1350 |
| Controller (headless synthetic) | 685 |
| Six powers | 79 |
| Swarm | 33 |
| Existing presentation | 72 |
| Progression | 85 |
| Starter mapping | 17 |
| Starter physics (with report) | 38 |
| XP observer | 30 |
| Ramp integration (headless / rendered) | 19 / 47 |
| Card/source/audio assets | 113 |

Differential physics compared all 48 neutral assemblies against the saved completed-002B battle source: 127,776 comparisons, zero failures. Custom/Quick Duel behaviour remains identical. The complete rendered smoke loop exercises all eight encounters, initial plus five earned acquisitions, completion, failure and restart. Windows release export succeeds; the exported executable also passes that complete smoke route with exit code zero.

A Windows compatibility-renderer stress fixture holds twelve small tops with repeated chain effects: 419 samples, simulation median 1.837 ms / p95 2.910 ms, CPU draw submission median 0.604 ms / p95 0.990 ms; harness wall-frame median 3.227 ms / p95 4.770 ms, 28 FX and 15 draw calls. Hardware: i3-10105F / GTX 1660. This excludes HUD and asynchronous GPU time and is not a claimed full-game FPS measurement. Raw evidence: `tests/results/task002b1-render-results.json`. Existing seeded swarm coverage also verifies the active cap, attribution propagation and all six power procs.

## Five acceptance answers

1. **Did the first minute become significantly more exciting?** The ramp is substantially stronger: a prebattle power, first earned choice around 13 seconds and four/five powers in surviving one-minute trials. The initial human verdict requested more intensity; final subjective excitement remains unconfirmed.
2. **Does the Level bar create anticipation?** It now exposes real progress, near-level tension and an immediate payoff. These mechanisms are implemented and inspected; psychological anticipation needs the final human check.
3. **Do the starters feel like different characters?** They differ in assembly, measured movement/impact/stability, silhouette and animation. The stronger separation is objective; whether a player recognizes each without copy remains a human acceptance question.
4. **Are the cards substantially better?** Yes in inspected production detail and presentation: dedicated 64px animated art, mechanical depth, disciplined palettes, readable copy and strong focus replace functional tiny icons as the primary reward illustration. Artistic preference still belongs to the player.
5. **Is there a memorable mid-encounter transformation?** A concrete transformation is proven: earned Impact Wake becomes active mid-swarm and repeatedly blasts that same pack. Human memorability has not yet been established.

## Known tradeoffs, changed files and deferred work

The final first level is intentionally earlier than the original target. Dense swarm credit can place two choices close together; overflow is preserved rather than discarded. Breaker burns out early with the sampled policy; Bastion is more forgiving. A six-power pool can reach MAX before the last encounter, so late XP cannot offer fake duplicate rewards. Final human timing, anticipation, stylistic preference and detailed physical-controller acceptance remain outstanding evidence.

Runtime changes: `scripts/{starters,run_progression,run_context,encounters,battle,main,menus,top_preview,run_powers,sound}.gd`. Assets: the three listed Aseprite masters, cards/icons/metadata, separate starter sheets and five audio cues. Reproduction tools: `tools/{build_power_art,build_starter_art,build_power_audio}.py`. Tests: updated flow/context/menu/controller/playthrough plus new progression, starter, physics, observer, ramp and card suites; three measured JSON reports. Documentation: this report, `TASK-002B1-PLAYTEST.md`, source-art notes, README; housekeeping ignores Python caches. Release: the Windows executable.

Deferred as requested: the remaining six powers, power evolutions, specialist rivals, Crown Engine/boss phases, Pulse Pylons, permanent progression, currency, shops, campaign, branching map, multiplayer and a large arena catalogue. No class system or evolution framework was overbuilt.
