# Alt Inventory

A lightweight World of Warcraft addon that shows, in an item's tooltip, how many of that item each of your alts is holding, broken down by Bags, Character Bank, Mail and Warband Bank. A search window finds any item across all of them by name.

**New here?** The [wiki](wiki/Home.md) explains every feature step by step (also on the [website](https://ctrlshiftzed.com/wiki/alt-inventory/)). Questions it doesn't answer: ask on [Discord](https://discord.gg/wz7fw6jM9Z).

Built as a minimal alternative to TradeSkillMaster's inventory tooltip, without TSM's memory footprint or crash surface.

- **Target patch:** 12.1.0 and up (Midnight)
- **Interface version:** `120100`

## Game versions

One download runs on every version: Retail, WoW Forever, Mists of Pandaria Classic, Burning Crusade Anniversary and Classic Era (Hardcore and Season of Discovery too). Each version keeps its own saved data, as the game does. On Classic the keyring is counted (Classic Era and Burning Crusade), every currency counts per character, and the Warband Bank only shows where the game has one (Retail and WoW Forever).

## What it does

Mouse over an item and Alt Inventory appends lines to the tooltip listing each character that holds it and where:

```
Alt Inventory              Total: 47
Fatheed                    Bags: 12, Bank: 20
Bankalt                    Bank: 10
Warband Bank               5
```

Four storage locations are tracked: Bags, Character Bank, Mail (items attached to letters) and Warband (account) Bank. No auction house, no vendor pricing, deliberately narrow scope.

It also keeps each character's gold (hover the minimap button for every character's gold, the Warband Bank's and the total) and their currencies that can be transferred between characters: hover one to see how much each character has, or search for it by name with the *Currencies* filter.

The window's *Play time* tab shows how long you've played on each character, and added up by class, role (from each character's current spec) or faction. A character's time is read when you log into it.

## Search

Click the magnifier in your bags' search box or the Alt Inventory button on the minimap (also in the minimap's addon list), or type `/altinv search`, and type part of an item's name. Every match across all your characters is listed with a count per character and place. Filter by character or by place (bags, bank, mail, warband), sort by name or total, and shift-click to link an item in chat. A number searches by item ID, and you can drop an item on the search box.

## How it works

The game only exposes the currently logged-in character's inventory, so:

- A character's data only exists after they've logged in with the addon installed.
- Bank and Warband Bank counts only update once that bank UI has been opened at least once on that character, and Mail once the mailbox has been opened.
- Warband Bank is account-wide and stored once, shown as a single line.

This is a hard API limitation, not a design choice, it's the same reason Altoholic, DataStore, and TSM all require you to visit each alt.

Data is written to a `SavedVariables` table (`AltInventoryDB`) on logout and loaded by every character on login. That's the mechanism by which one character "sees" another's items.

Bank, Mail and Warband Bank counts more than a day old show their age in the tooltip, for example `Bank: 20 (12d ago)`, so you know when a count may be out of date.

## Commands

- `/altinv`, rescan now and list every tracked character with their gold and when their bank and mailbox were last opened.
- `/altinv search`, open the search window. `/altinv find potion` opens it searching for "potion".
- `/altinv remove Name` (or `Name-Realm`), forget a deleted or transferred character.
- `/altinv minimap`, show or hide the minimap button.

## Installation

1. Copy the `altinventory` folder into your WoW `Interface/AddOns/` directory.
2. Make sure the folder is named `AltInventory` (matching the `.toc` file name) if your AddOns folder expects that.
3. Restart WoW or reload UI (`/reload`).
4. Log in on each alt at least once, and open their bank (and Warband Bank) at least once, to populate their data.

## Files

- `AltInventory.toc`, addon metadata, interface version, saved variables declaration.
- `Core.lua`, saved-variable storage and scanning (bags, bank, mail, warband, item names).
- `Tooltip.lua`, the tooltip lines.
- `Search.lua`, finding items by name.
- `UI/SearchWindow.lua`, the search window and the bag search button.
- `UI/MinimapButton.lua`, the minimap button and the addon list entry.
- `AltInventory.lua`, events and the slash command.
- `icon.tga`, addon icon shown in the in-game AddOn List.

## License

MIT, see [LICENSE](LICENSE).
