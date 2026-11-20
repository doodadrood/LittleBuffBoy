# LittleBuffBoy

A lightweight, standalone, all-class buff, Shaman totem, consumable, and minimap tracking coordinator for **World of Warcraft: Forever** (`## Interface: 16001`, 12.1.5 / Midnight API) with native **PallyPower (`PLPWR`)** interoperability.

## Features

- **All-Class Buff & Totem Coordination:** Supports Priest (Fortitude, Divine Spirit, Shadow Protection), Mage (Arcane Intellect, Dampen/Amplify Magic), Druid (Mark/Gift of the Wild, Thorns), Paladin (Blessings & Auras), Warlock (Soulstone, Blood Pact, Detect Invisibility, Unending Breath), Warrior (Battle Shout), and Shaman (4-element party totems).
- **Live Spell, Talent & Tracking Discovery:** Uses modern `C_SpellBook.IsSpellKnown`, `C_Spell.GetSpellInfo`, `C_Traits` / `C_ClassTalents`, and `C_Minimap` APIs with async `SPELL_DATA_LOAD_RESULT` handling.
- **Autonomous Zero-Conflict Negotiation:** Deterministic multi-caster consensus solver over `"LBB1"` splits duties automatically by talent weights and raid subgroups (2-Priest family split, 3+ Priest subgroup split, Shaman Melee/Caster party presets, solo fallback) while preserving manual `locked` overrides.
- **Native PallyPower (`PLPWR`) Bridge:** Speaks native `PLPWR` (`SELF`, `ASELF`, `ASSIGN`, `MASSIGN`, `NASSIGN`, `PASSIGN`, `AASSIGN`, `REQ`, `SYMCOUNT`, `FREEASSIGN`, `CLEAR`) and automatically yields Paladin Blessing control if standalone `PallyPower` is loaded.
- **Midnight Engine & Combat Safe:** Strictly uses modern `C_` APIs (zero `COMBAT_LOG_EVENT_UNFILTERED`), guards aura reads with `issecretvalue()`, and queues `SecureActionButtonTemplate` attribute mutations during `InCombatLockdown()` for immediate flush on `PLAYER_REGEN_ENABLED`.
- **Clean, Compact UX:**
  - **Buff Strip & Smart Auto-Buff Keybind:** Movable, lockable, scalable (`0.7x–1.4x`) dark-slate strip with optional Fade/Auto-Hide when all buffs are healthy, plus a dedicated **Smart Auto-Buff** tile & WoW keybinding (`Bindings.xml`) to spam one hotkey through every missing duty in priority order without dropping your target.
  - **Persistent Assignments & Named Presets:** Automatically saves and restores your buff, aura, override, and totem setup across reloads/logouts (while auto-negotiating fresh when joining a new multi-caster raid), plus 1-click **Saved Presets** (`Solo`, `Dungeon`, `Raid`, or custom names).
  - **Assignment Matrix (`/lbb`):** Tabbed grid for Group Buffs, Paladin Blessings & Aura column (with inline Per-Player Overrides and 1-click **Apply to ALL Classes / ALL Groups** shortcuts), Paladin Righteous Fury & Seal controls, Shaman Totems, and Consumables — Left-click opens a selection dropdown, Mousewheel cycles, Right-click clears, and Shift+Click locks.
  - **Minimap Icon (Collector-Friendly):** Custom Judgement Paladin minimap icon (`Media/MinimapIcon.tga`) with native `LibDBIcon-1.0` / `LibDataBroker-1.1` and `Minimap` collector compatibility (works cleanly with **OneForAll**, MBB, HidingBar, and Blizzard Addon Compartment).
  - **Paladin Tank/Self Support:** Opt-in Righteous Fury & Seal tracking (auto-prompts Tank Paladins, supports Forever's *Seal of Fury* + dynamic spellbook Seals, uses Blizzard's `CustomAuraContainerTemplate` native overlay in combat with safe fallback, and yields cleanly if standalone PallyPower is loaded).
  - **Raid Frame Micro-Indicators:** Minimal 6x6px corner pips on Blizzard `CompactUnitFrame` frames with calm combat behavior.
  - **Smart Reminders:** One-click **"Restore Tracking"** pill for profession & Hunter tracking, plus a Ready Check / Manual Nudge bar with **Smart Whisper** (concise individual whispers, never `/raid` spam).

## Slash Commands

- `/lbb` or `/lbb ui` — Toggle Assignment Matrix
- `/lbb lock` — Lock / unlock Buff Strip
- `/lbb auto` — Run deterministic Auto-Assign / Re-Negotiate
- `/lbb reset` — Clear manual locks and re-negotiate
- `/lbb preset <save|load|delete> <name>` — Manage saved character presets
- `/lbb scale <0.7-1.4>` — Adjust Buff Strip scale
- `/lbb minimap` — Toggle Minimap icon visibility
- `/lbb nudge` — Toggle Ready Check & Smart Whisper Nudge bar
- `/lbb sync` — Broadcast capabilities and request sync from peers
- `/lbb rf` — Toggle Paladin Righteous Fury tracking
- `/lbb seal` — Cycle Paladin Seal tracking (or disable)
- `/lbb status` — Print diagnostic summary
- `/lbb options` — Open Options window

## Running Unit Tests

```bash
./scripts/run_tests.sh
```

Uses **Busted** (Lua 5.1) when installed, or automatically falls back to `luajit tests/busted_runner.lua`. GitHub Actions runs tests on every push/PR and gates CurseForge releases via `BigWigsMods/packager@v2`.
