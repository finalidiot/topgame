# Task 002C.2 - Endless Threat Director checkpoint

Run `SpinningMetal.exe`, choose **CONTINUOUS RUN**, a starter and a starting power,
and launch once. Bastion is the most forgiving first test; also try Breaker/Vane.
No developer commands are needed. Survive several minutes to give elites and
bosses opportunities to arrive. Neither a particular boss nor a fixed sequence
is guaranteed. The Run continues after every ordinary or boss defeat.

Keyboard: WASD/arrows steer, Space Burst, Shift brake, Escape pause.
Gamepad: left stick steer, bottom face Burst/Confirm, shoulder/trigger brake,
Menu/Start pause, east face Back. Release steering/Burst/brake after a draft.

Try a level-up, rank/mutation, swarm, elite, boss arrival, post-boss combat and
an eventual loss. Yellow markers identify elites; red crowns identify bosses.
The HUD shows active survival time, tier, pressure and current population.

1. Does the arena feel alive rather than like sequential matches?
2. Does pressure rise naturally?
3. Are moments of relative calm useful?
4. Can you recognise movement roles without their labels?
5. Does the first elite feel meaningfully different?
6. Does the boss warning/arrival feel important?
7. Is killing a boss satisfying while combat continues?
8. Do strong builds have enough targets to demonstrate their strength?
9. Does the screen remain readable, including mixed pressure?
10. Is any period too empty or permanently overloaded?

Record starter, controller, approximate time, result-screen seed, and specific
moments that felt good or frustrating. On defeat, `user://last_run_director.json`
stores recent decisions and your build. The seed can be investigated with
`SpinningMetal.exe -- --run-seed=<seed>`; decisions also depend on combat outcomes.

**Temporary RPM rule is unchanged:** continuous Runs pay 12% of each tick's net
reserve loss. There are no between-threat refills. Ring-outs and spin-outs still
end the Run. This is architecture-testing tuning, not the final RPM economy.
Quick Duel and standalone build practice retain their single-battle flow.

This checkpoint stops at Task 002C.2. Human feel and balance acceptance are pending.
