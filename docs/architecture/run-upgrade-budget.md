# Run upgrade budget: clarified scope

The human clarified that a future XP or Run-currency budget should support
buying several upgrades and spending on rerolls **within the current Run**.
That budget remains planned. This feedback checkpoint implements temporary
reroll charges only; it adds no permanent power upgrade or permanent starting
reroll purchase system.

## Current implementation

The existing XP progression still opens a deterministic three-card draft and
commits one acquisition or rank investment. Rank III still resolves through the
existing mutation choice. Rerolling changes the pending offer; it does not grant
another investment or spend XP.

- Each Run starts with one charge and may hold six.
- One valid reroll spends one charge. A replacement must change at least one
  eligible card, rather than merely shuffle the same three cards.
- The offer is deterministic from Run seed, draft ID and reroll revision.
  Seed, draft ID and revision checks reject obsolete buttons and duplicate
  callbacks. A mutation choice cannot be rerolled.
- Actual threat clears 1, 4, 7 and subsequent every-third clears, plus boss
  clears, can place a physical reroll chip on the arena floor. At most two
  chips coexist, and their lifetime is 180 seconds of advancing battle time.
- Driving within 14 world units of a chip, using the player's actual swept
  movement segment, collects one charge once. Pause and draft screens freeze
  pickup time; collection is refused when charges are already full.
- Restarting or clearing the Run resets charges, receipts and pending chips.
  Charges do not enter the permanent parts collection save.

`scripts/run_context.gd` owns the charge and draft transactions.
`scripts/run_pickups.gd` observes real battle movement and clears without
changing physics, the Threat Director or the RPM economy. `scripts/main.gd`
routes the current Run's transactions; `scripts/menus.gd` presents a focusable
reroll button and HUD charge count.

## Planned budget boundary

A later explicitly scoped implementation may turn earned XP or another
temporary Run resource into a spendable upgrade budget. The human's intended
choice is whether to develop several powers or spend some of that same Run's
resources seeking a better offer.

Such a budget should remain owned by the live `RunContext`, with atomic spends
and deterministic offer revisions. Reopening a draft or resuming after pause
must not mint currency, repeat a purchase or invalidate a committed mutation.
Purchases should operate on the existing owned-family/rank/mutation model.
The seven-family limit and legal rank progression remain explicit constraints.

Prices, earning rates, carryover, multiple-purchase interaction and any
conversion between XP and currency are undecided. This document establishes
scope, not an implemented economy or a hidden placeholder pricing schema.
Permanent part ownership remains a separate collection system; this planned
Run budget must not silently modify it.

Task 002C.5 remains **PENDING HOME HUMAN PLAYTEST**. The current reroll mechanic
and any future budget require human review rather than implying acceptance of
the provisional Run progression or balance.
