# Questions and fixes

*Answers to the things people ask most.*

**My alt's items don't show up.**

Log in on that character once with Alt Inventory installed. The game only shares the inventory of the character you're playing, so each one needs a visit.

**Bank or Warband Bank counts are missing or old.**

Open the bank (and the Warband Bank) once on that character. Counts more than a day old show their age, like `(12d ago)`.

**Items in the mail aren't counted.**

Open the mailbox once on that character. Mail is read when the mailbox is open.

**I renamed a character and now it shows twice.**

From 1.10.1 Alt Inventory spots a rename when you log in on that character and drops the old name. If the old name was saved before 1.10.1, type `/altinv remove OldName` once.

**How do I remove a character I deleted?**

Type `/altinv remove Name`, or `/altinv remove Name-Realm` if you have the same name on two realms.

**Two of my WoW Forever characters with the same first name show as one.**

Update to 2.0.1 or later and log in on each of them once: they're saved under their full name from then on. Open the bank and mailbox once on each too, so their counts are their own again. To forget one, type `/altinv remove First Surname`.

**Last played shows "-" for a character.**

Last played is saved from 2.0 on. Log in on that character once and it fills in.

**The minimap button is gone.**

Type `/altinv minimap` to show it again. It's also in the minimap's addon list.

**My characters don't show up, or nothing is saved.**

Type `/altinv debug` and paste the lines it prints into a comment on CurseForge or on [Discord](https://discord.gg/wz7fw6jM9Z). They show the addon and game version, what the game reports for your character, what's saved and any error at login, which is everything needed to track it down. Saved data is written when you log out or type `/reload`, so if the game closes unexpectedly that session isn't kept.

**Does it slow the game down?**

No. It was built as a light alternative to TradeSkillMaster's inventory tooltip: it only reads your bags when they change, and the tooltip lines are a quick lookup.

**Does it show auction or vendor prices?**

No, it only counts what you hold. For prices, have a look at [Auction Coach](https://ctrlshiftzed.com/auction-coach).

---

Previous: [Commands](Commands.md) | [Wiki home](Home.md)

Didn't find your answer? Ask in the [CtrlShiftZed Discord](https://discord.gg/wz7fw6jM9Z).
