# Beast Charge / Manifest — future combat design

**Design only. Not implemented in 003A.** The working names are Beast Charge and
Manifest; neither the name nor the final input binding is locked. This document
adds no HUD, input action, gameplay state or save field.

## Two separate roles

The automatic extreme-hit manifestation is a brief, rare visual response to an
exceptional physical collision. Its fixed impact qualification, collision
identity, dominant owner and bounded presentation timeline belong to cosmetic
presentation. It does not grant combat benefits or spend future charge.

A full beast special would require earned charge and deliberate player input.
It would create a substantial, beast-specific physical opportunity and have a
clear commitment, response window and recovery. This leaves spectacle above the
current automatic manifestation without making routine collisions summon it.

## Earning charge through physics

Candidate sources are extreme delivered hits, major force successfully received,
counter-collisions, well-aimed Burst impacts, meaningful ring-edge recoveries,
elite/boss exchanges, and deliberate bracing against a huge incoming attack.
Use confirmed canonical collision/movement evidence, not power activation labels.
The existing accepted-impact identity and physical impulse can be read by a
separate future gameplay consumer without making the cosmetic controller an
authority for rewards.

Offence and defence must have equivalent routes to readiness. A Stone Tortoise
fortress that deliberately braces, counters or steers into a huge attack should
earn meaningful charge even when its displacement is small. Conversely, actual
outgoing force and commitment should reward an aggressive player's precise hit.
The dominant cosmetic owner must not prevent another eligible player from
earning their independently verified defensive contribution in future multiplayer.

No passive timer fills the meter. Recent deliberate steering, Brake or Burst
must support the earning event; automatic retaliation alone is insufficient.
Deduplicate each event and cap contributions from repeated contacts with the
same target or sequence. Tiny contacts, damage-over-time, passive orbit farming,
cleanup eliminations and harmless wall oscillation must not become charge farms.
Thresholds, weights, caps and recovery criteria require a separate offence/defence
study; this specification deliberately does not assign numerical charge values.

## Readiness, activation and recovery

The conceptual sequence is EARNING → READY → COMMITTED SPECIAL → RECOVERY.
At full charge, retain readiness until a valid deliberate activation. Charge is
spent once on accepted activation, not on the automatic hit apparition. Define
invalid activation, retirement, round transitions and interruption rules before
implementation; readiness must not accidentally fire after leaving a menu.

Keep the resource temporary to combat. New Runs reset it. Permanent collection,
Credits and Salvage do not purchase charge. A future deterministic implementation
must own its fixed-tick gameplay state, replay/reset rules and event accounting;
003A's permanent save schema remains unchanged.

## Preliminary physical signatures

| Beast | Proposed commitment and opportunity | Cost or counterplay to investigate |
| --- | --- | --- |
| Black Arrow | Precision directional assault with an explosive corkscrew/somersault approach and a large collision opportunity. | High mobility and risk; committed direction and a meaningful miss/recovery window. |
| Iron Bull | A brutal, difficult-to-redirect momentum charge that can produce spectacular displacement. | Run-up, telegraph, turning limits and the risk of overshooting. |
| Stone Tortoise | A temporary extreme brace that receives a major attack window and releases stored physical force as a counter. | Finite capacity, commitment and recovery; successful receipt matters rather than simple invulnerability. |
| Coil Dragon | A sweeping coil/orbit motion that physically redirects or repositions opponents to create a subsequent collision setup. | Bounded reach, force and targets; an escape or disruption opportunity. |

These are starting points, not locked move designs. Specials manipulate momentum,
displacement, stability, anchoring, recoil and collision opportunity through the
existing solver. They do not bypass it with arbitrary magic damage or directly
assign a ring-out. Test massive defenders, small threats, arena boundaries and
simultaneous impacts before accepting any move.

## Windows, controllers and Android

Plan one dedicated logical action without displacing Burst or Brake. Final
keyboard, Xbox, PlayStation and Nintendo-style bindings remain undecided; use
platform-appropriate prompts and check conflicts with menu confirmation.

Conceptual HUD: a compact MANIFEST bar, then MANIFEST READY. It must remain clear
at the native landscape resolution and inside Android safe areas. A touch control
needs independent finger ownership, an adequate target and steering + action
multitouch. Pause, draft and READY re-entry must clear stale activation ownership
and require a fresh deliberate press while retaining prepared steering.

Future special presentation may use a fuller authored apparition, its own action
animation, a restrained lighting response, sound/music punctuation and bounded
camera emphasis. Preserve Reduced Flashing and the player's view of the real top.
Do not interrupt controls with a long cinematic. No meter, button, special move,
new music treatment or related runtime state is introduced by this 003A pass.
