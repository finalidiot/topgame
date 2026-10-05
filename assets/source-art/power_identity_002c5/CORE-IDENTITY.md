# Bank, Predator, Guard and Crosscut: physical-top correction v2

The human review rejected the d0d37e5 Bank cassette, Predator comb/hunter machine
and Guard piston/box. Those grades supersede the earlier internal A/B claims.
These corrected sources replace those devices. Crosscut was also corrected:
its artificial Rank II blade extension is removed.

## Historical comparison and reference choice

The actual earlier `roster_cards_002c5.aseprite`, `roster_icons_002c5.aseprite`
and `roster_fx_002c5.aseprite` were opened and their tagged frames inspected.
Their cards at least read as tops: Bank used a centered steel body and short
floor strokes; Predator used a large/small pursuit pair; Guard a steel body
with a contact rim; Crosscut a body with crossed strokes. Their small bars,
segmented rim and symmetric X were not strong enough to restore wholesale.

The accepted `starter_blade_accents_002b1.aseprite` supplied much clearer real
Breaker, Bastion and Vane blade/body silhouettes. The corrected cards copy
those original 48px native cels at their existing pixel scale and colours,
then assemble the accepted ratchet and bit textures in Battle's normal order.
They contain no resized or recoloured body and no new fictional attachment.
The different powers are distinguished by their physical scene and motion.

| Family | Corrected physical story | Rank II development |
|---|---|---|
| Momentum Bank | One actual round Bastion top fills the foreground and brakes over its own floor track. Two skids fold at its bit footprint, hold briefly, then straighten into a directed launch. | More tightly folded floor force and a stronger launch, without a detached cassette. |
| Predator Line | A real angular Breaker pursues one round Bastion on an upward diagonal. The hunter closes the gap and makes a short genuine rim scrape. | Tighter arrival and stronger pursuit/contact marks, with the same real bodies. |
| Crash Guard | A round actual Bastion receives the incoming Breaker, yields slightly at contact, then redirects the attacker's exit. | Less defender displacement and a stronger diverted exit; no piston, box or persistent shield. |
| Crosscut | An actual Vane descends into a tangential contact with Bastion, and the two tops leave on unequal lanes. | Greater separation and developed floor shear, without an added blade or symmetric X. |

## Editable sources

Each family has `_cards.aseprite`, `_icons.aseprite` and `_fx.aseprite` here.
Cards are 64×64 with five named normal layers and pivot (32,32). Each rank has
six deliberately directed poses held twice as twelve pipeline keys. These
are explicit holds: anticipation, approach/compression, contact, reaction,
follow-through and recovery. They do not claim twelve independently different
poses merely to satisfy a frame count.

Icons are independently drawn at 16×16 with two named layers and pivot (8,8).
Their small blade rims, front shells and bits depict tops; separate floor or
contact strokes distinguish the power. They are not reduced cards or devices.

FX remain 96×80, pivot (48,48), with four named normal layers and eight native
keys per tag. All eight projected headings `e,se,s,sw,w,nw,n,ne` exist at both
ranks. FX contain no replacement body, gadget or procedural particle field.
The real gameplay top stays visible while short floor skids and attached rim
pressure show the existing event. Every directional placement is authored
upright; no sprite rotation or image resampling is used.

Internal tags retain compatibility: Bank uses `bank_load`, `bank_stored` and
`bank_release`; Predator uses `predator_pressure` and `predator_tracking`;
Guard retains the old internal name `damper_contact`, now a physical blade
absorption/redirect response with no damper hardware; Crosscut uses
`shear_slice`. Rank and heading suffixes select the appropriate native cels.

`bank_stored` selects the eight existing real charge stages, never an automatic
filling animation. The empty key is completely transparent. Every positive key
has a compact two-pixel gold/pale fold just outside the actual rear heel; higher
charge tightens the same short skid, and Rank II has one additional floor fold.
The earlier correction's near-empty low-charge key disappeared beneath the body
and team ring in real motion. The first bright replacement also failed its real
south-facing hold because the live blade occluded it. The final fold therefore
has an upright, individually placed rear span per heading and a continuous short
steel floor seam back to the actual bit. In 8,064 native starter/phase/lean/stage
composites, at least 19 bright pixels remain exposed outside the real body; that
is an occlusion check rather than a gameplay or artistic grade. The failed real
frame and intermediate master remain in the external iteration evidence. The renderer
owner selects positive stages with a ceiling/minimum-one mapping only while the
real stored amount exceeds its existing visibility threshold; zero charge draws
no wake. Store contraction, held fold and directed release remain separate cels.
The card's formerly small angular Vane body was also replaced with the stronger
accepted round Bastion foreground subject at its original native pixel scale.
`predator_tracking` selects existing hunt-stack stages and
must sit at the actual hunter's floor footprint facing its one real target.
The old 70% gap position belonged to the rejected comb and is inappropriate
for a pursuit floor stroke. The shared renderer owner handles that read-only
placement correction. Guard remains contact-only.

## Authoring, export and proof

`tools/author_identity_core.py` is the explicit authoring recipe. Its default
refuses artist overwrite; `--revise` was used only for this human-authorized
correction. Native pixel copying of accepted bodies and independently directed
technical drawing of their physical travel are documented honestly. Saved
Aseprite masters remain the source authority after artist editing.

Normal export uses the existing `tools/export_power_identity.py`, which opens
saved masters in native Aseprite and checks visible RGBA parity. The root
agent centrally exports the frozen family sources and updates shared metadata;
this authoring pass does not edit shared export, renderer, gameplay or tests.

The d0d37e5 rejected sources, actual historical comparison, accepted top-body
reference, native/color/grayscale six-pose and icon reviews, and twelve native
Aseprite parity results are under:
`C:\GPT GAME BUILDING\task-002c5-qa\art-correction-v2\`.

`core-review/core-native-source-parity.json` confirms each corrected master
matches its real native Aseprite export. That proves source integrity, not an
artistic grade. Runtime recordings must still verify placement, visibility and
readability. Final quality remains the human review gate.
