# Alt Inventory

A lightweight World of Warcraft addon that shows, in an item's tooltip, how many of that item each of your alts is holding, broken down by Bags, Character Bank, and Warband Bank.

Built as a minimal alternative to TradeSkillMaster's inventory tooltip, without TSM's memory footprint or crash surface.

- **Target patch:** 11.x / 12.x retail (The War Within)
- **Interface version:** `120100`

## What it does

Mouse over an item and Alt Inventory appends lines to the tooltip listing each character that holds it and where:

```
Alt Inventory              Total: 47
Fatheed                    Bags: 12, Bank: 20
Bankalt                    Bank: 10
Warband Bank               5
```

Only three storage locations are tracked: Bags, Character Bank, and Warband (account) Bank. No auction house, no mail, no vendor pricing, deliberately narrow scope.

## How it works

The game only exposes the currently logged-in character's inventory, so:

- A character's data only exists after they've logged in with the addon installed.
- Bank and Warband Bank counts only update once that bank UI has been opened at least once on that character.
- Warband Bank is account-wide and stored once, shown as a single line.

This is a hard API limitation, not a design choice, it's the same reason Altoholic, DataStore, and TSM all require you to visit each alt.

Data is written to a `SavedVariables` table (`AltInventoryDB`) on logout and loaded by every character on login. That's the mechanism by which one character "sees" another's items.

## Installation

1. Copy the `altinventory` folder into your WoW `Interface/AddOns/` directory.
2. Make sure the folder is named `AltInventory` (matching the `.toc` file name) if your AddOns folder expects that.
3. Restart WoW or reload UI (`/reload`).
4. Log in on each alt at least once, and open their bank (and Warband Bank) at least once, to populate their data.

## Files

- `AltInventory.toc`, addon metadata, interface version, saved variables declaration.
- `AltInventory.lua`, scanning, saved-variable storage, and tooltip hook.
- `icon.tga`, addon icon shown in the in-game AddOn List.

## License

MIT, see [LICENSE](LICENSE).
