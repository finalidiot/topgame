# A physical workbench hub — future presentation direction

This is a future front-end concept, not a new hub implemented in 003A.1. The
current correction makes WORKSHOP enter the owned collection/build/equip screen
directly, with a labelled return to Shop or the hub. Shop keeps two independent
packet cards and the existing durable purchase/opening transactions.

A later presentation milestone could make the main hub feel like a real place:
the player's equipped top on a workbench, owned parts in drawers, sealed packets
at the merchant counter, tools and mechanical detail, and a small practice arena.
Each physical destination should communicate the action before interaction.

Keep the existing destinations and state ownership. Drawers open Workshop;
sealed packets open Shop; the practice arena opens a clearly named practice mode;
the current top leads to launching its owned build. Presentation must not silently
start a Run, equip a part, spend currency, or bypass a saved packet receipt.

Keyboard and controller need a visible, stable focus order and platform-correct
Confirm/Back hints. Mouse and Android touch need explicit targets rather than
hidden scenery hotspots. Use the authored pixel language, nearest-neighbour
scaling and readable landscape safe areas. Back returns directly to the originating
destination; an obvious route always returns to the hub.

Prototype one coherent bench scene only after human approval of this direction.
Keep collection/economy/save schema, crash recovery, controller actions and Android
hold-and-drag combat controls separate from the scene's visual treatment. Do not
add another progression system or redesign packet opening as part of that prototype.
