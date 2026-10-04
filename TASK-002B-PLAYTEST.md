# Task 002B human playtest

Human feel validation is still pending. Automated input, replay, and visual checks do not answer the questions below.

## Launch

Run the exported Task 002B Windows build:

```powershell
& "C:\GPT GAME BUILDING\GyroBrothers\releases\windows\SpinningMetal.exe"
```

Or run the current source directly:

```powershell
& "E:\Desktop\Godot_v4.7.2-stable_win64_console.exe" --path "C:\GPT GAME BUILDING\GyroBrothers"
```

Select **EIGHT-ENCOUNTER RUN**. Start with your preferred assembly; try SMASH / LOW / FLAT for aggressive rebounds on a second run. Record the assembly, acquired powers, outcome, approximate run time, and one memorable or frustrating exchange. Inspect at the native 640×360 resolution as well as the normal integer-scaled window.

## Feel questions

Answer each question from play, with a concrete example. Mark a power **not observed** if the relevant situation did not occur.

| Feature | Exact feel target | Result / example |
| --- | --- | --- |
| Impact Wake | Can I deliberately trigger it? Does it feel powerful? | |
| Redline | Does activation immediately feel dangerous and exciting? | |
| Iron Comet | Do I intentionally seek wall rebounds? | |
| Afterimage | Does speed create new spatial strategy? | |
| Second Wind | Does the recovery create a memorable comeback? | |
| Chain Impact | Can one good swarm hit produce an understandable cascade? | |
| Swarm | Do I feel surrounded without feeling unfairly stun-locked? | |
| Build transformation | After acquiring 3–4 powers, does the player top feel substantially different from the start of the Run? | |

- [ ] Compare encounter 1 with encounters 4–8: identify a new decision or useful interaction, beyond brighter effects.
- [ ] If offered early, bring Impact Wake + Chain Impact into slot 3. Follow the first struck small top and the resulting ricochets. Is the cause understandable?
- [ ] Combine Redline + Iron Comet: Burst toward a solid wall, aim the charged return, and note the spin/wobble cost after the hit.
- [ ] Check that pressure effects, echoes, recovery, and corona leave the player, contact points, and both gate mouths readable.
- [ ] In Ammunition Waves, watch all three waves, safe entry telegraphs, the active count, and the final clear. Note unfair contact, excessive hit-stop, stalls, or audio clutter.
- [ ] Play Quick Duel and confirm the original steering, Burst, brake, and rematch still feel familiar.

## Controller route

On 3 October 2026, a native Godot probe detected one mapped device: **XInput Controller (device 0)**. This confirms attachment only; physical-controller play has not been observed by the implementation agent.

Complete this route using the physical controller without keyboard or mouse:

- [ ] Title → garage; select Blade, Ratchet, and Bit → Run start.
- [ ] Steer, Burst, brake, pause, and resume during combat.
- [ ] Draft with three, two, and one available card; inspect visible focus and collect the intended card.
- [ ] Open the Run menu from a draft and return: the offer and focused power should remain the same.
- [ ] Observe the short acquisition beat and automatic next launch. Holding or repeating Confirm must not collect twice or skip an encounter.
- [ ] Continue after encounter 5; lose and restart; finish a Run and restart; End Run to garage.

## Decision

**Does this now feel materially more like a roguelite than Task 002A, and what concrete behaviours create that difference?**

Human answer:

Remaining issues and severity:

Controller model / tester / date:
