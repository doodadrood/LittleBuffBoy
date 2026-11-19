# LittleBuffBoy Agent Instructions

- **Target Engine:** World of Warcraft: Forever (`## Interface: 16001`, 12.1.5 / Midnight API, Lua 5.1).
- **Modern APIs Only:** Never use removed Classic globals (`GetSpellInfo`, `UnitBuff`, `UnitDebuff`, `COMBAT_LOG_EVENT_UNFILTERED`). Always use `C_Spell`, `C_SpellBook`, `C_UnitAuras`, `C_Minimap`, `C_ChatInfo`, `C_Item`, `C_AddOns`.
- **Midnight Secret-Value & Combat Safety:** Always guard aura and unit reads with `LBB.IsSecret(...)` / `LBB.SafeCall(...)`. Never mutate `SecureActionButtonTemplate` attributes during `InCombatLockdown()`; always route through `LBB.SetSecureAttribute(...)` or `LBB.RunOutOfCombat(...)`.
- **Tests:** Run `./scripts/run_tests.sh` (uses `busted` when installed, falling back to `luajit tests/busted_runner.lua`) after every change.
- **Releases:** Follow `.agents/skills/cut-release/SKILL.md`. Keep `LittleBuffBoy.toc` and `LittleBuffBoy_Camelot.toc` synchronized.
