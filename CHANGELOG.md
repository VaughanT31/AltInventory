# Changelog

## 1.7.1

- **Classic currencies:** they're now saved on Mists of Pandaria Classic, Burning Crusade Anniversary and Classic Era. 1.7.0 looked for each currency's ID in the wrong place there and saved none.
- Shift-clicking a result in the search window puts its link in chat the current way, so it keeps working when the game removes the old way.

## 1.7.0

- **Every version of WoW:** the same addon now runs on Retail, WoW Forever, Mists of Pandaria Classic, Burning Crusade Anniversary and Classic Era (Hardcore and Season of Discovery too). Tooltips, search, gold and play time work on all of them.
- **Classic:** your keyring is counted on Classic Era and Burning Crusade, and every currency counts per character, since Classic has none shared across your account (Badges of Justice, Justice and Valor Points and so on). The Warband Bank only shows where the game has one (Retail and WoW Forever), and play time groups by character, class and faction on Classic Era, which has no specs.
- **WoW Forever:** its larger character and Warband Bank (up to nine tabs each) are counted in full.

## 1.6.1

- Fixed: an error at logout ("attempt to concatenate a nil value") while saving your play time. The game sometimes no longer knows your realm name by then, so the character is now remembered from login.

## 1.6.0

- **Play time:** a new tab in the Alt Inventory window shows how long you've played, by character, class, role or faction, as bars with each one's share and the total. Hover a bar for the time and how many characters it counts.
- Each character's time is read when you log into it, without the usual /played lines in chat, and kept up to date while you play. Characters you haven't logged into since updating show as not recorded yet.

## 1.5.0

- **Gold on every character:** hover the minimap button for each character's gold, the Warband Bank's and the total. `/altinv` lists it too.
- **Currencies you can transfer:** hover a currency that can be moved between characters (in the currency tab or a link) to see how much each character has, with the total. The search window finds them by name as well, with a *Currencies* filter, so you can see who has the most before using the game's Transfer.
- Characters' gold and currencies update the next time you log into each one.

## 1.4.0

- **Minimap button:** click it to open the search window. Drag it around the minimap to move it, or hide it with `/altinv minimap`.
- **Addon list:** Alt Inventory is also in the minimap's addon list button, which opens the search too.

## 1.3.0

- **Search all your characters:** a new search window finds any item by name across every character's bags, bank and mail, and the Warband Bank, with a count per character. Filter by character or place, sort by name or total, shift-click to link an item. Open it from the magnifier in your bags' search box (it brings along what you typed there) or with `/altinv search` and `/altinv find <text>`.
- **Mail is tracked:** items attached to letters in each character's mailbox now count, in tooltips and in search, with the same "(3d ago)" age note as banks.
- `/altinv` also says when each character's mailbox was last opened.

## 1.1.0

- `/altinv` lists tracked characters, `/altinv remove Name` forgets one.
- Bank and Warband Bank counts more than a day old show their age.
