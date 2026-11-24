local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Assignments = {}
LBB.Assignments = Assignments

local pairs = pairs
local ipairs = ipairs
local type = type
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat

local function deepCopy(val)
	if type(val) ~= "table" then
		return val
	end
	local out = {}
	for k, v in pairs(val) do
		out[k] = deepCopy(v)
	end
	return out
end

function Assignments:Reset()
	self.roster = {}
	self.rosterByName = {}
	self.rosterByUnit = {}

	-- groupBuffs[familyID][subgroup] = { caster = name, locked = bool }
	self.groupBuffs = {}
	-- classBuffs[casterName][classToken] = { familyID = famID or nil, locked = bool }
	self.classBuffs = {}
	-- targetBuffs[familyID][targetName] = { caster = name, locked = bool }
	self.targetBuffs = {}
	-- roleBuffs[familyID][roleKey] = { caster = name, locked = bool }
	self.roleBuffs = {}
	-- paladinNormalOverrides[casterName][targetName] = { familyID = famID, class = classToken, locked = bool }
	self.paladinNormalOverrides = {}
	-- paladinAuras[casterName] = { auraID = 1..7 or 0, locked = bool }
	self.paladinAuras = {}
	-- shamanTotems[subgroup][casterName] = { EARTH = id, FIRE = id, WATER = id, AIR = id, locked = { ... } }
	self.shamanTotems = {}

	self.lastMultiCasterRaidSig = nil
	self.restoredFromDB = false
end

Assignments:Reset()

function Assignments:SnapshotState()
	return {
		groupBuffs = deepCopy(self.groupBuffs),
		classBuffs = deepCopy(self.classBuffs),
		targetBuffs = deepCopy(self.targetBuffs),
		roleBuffs = deepCopy(self.roleBuffs),
		paladinNormalOverrides = deepCopy(self.paladinNormalOverrides),
		paladinAuras = deepCopy(self.paladinAuras),
		shamanTotems = deepCopy(self.shamanTotems),
		lastMultiCasterRaidSig = self.lastMultiCasterRaidSig,
	}
end

function Assignments:ApplySnapshot(snap, skipPaladins)
	if type(snap) ~= "table" then
		return false
	end
	self.groupBuffs = deepCopy(snap.groupBuffs or {})
	self.targetBuffs = deepCopy(snap.targetBuffs or {})
	self.roleBuffs = deepCopy(snap.roleBuffs or {})
	self.shamanTotems = deepCopy(snap.shamanTotems or {})
	if not skipPaladins then
		self.classBuffs = deepCopy(snap.classBuffs or {})
		self.paladinNormalOverrides = deepCopy(snap.paladinNormalOverrides or {})
		self.paladinAuras = deepCopy(snap.paladinAuras or {})
	end
	if snap.lastMultiCasterRaidSig ~= nil then
		self.lastMultiCasterRaidSig = snap.lastMultiCasterRaidSig
	end
	return true
end

function Assignments:SaveToCharDB()
	if not LBB.CharDB then
		LBB.CharDB = {}
	end
	LBB.CharDB.savedAssignments = self:SnapshotState()
	return LBB.CharDB.savedAssignments
end

function Assignments:LoadFromCharDB(skipPaladins)
	if not (LBB.CharDB and type(LBB.CharDB.savedAssignments) == "table") then
		return false
	end
	self:ApplySnapshot(LBB.CharDB.savedAssignments, skipPaladins)
	self.restoredFromDB = true
	return true
end

-- Compute deterministic multi-caster raid signature for the local player's class.
-- Returns nil when solo, in a 5-man party, or sole synced caster of their class in the raid.
function Assignments:ComputeMultiCasterRaidSignature(roster, capabilitiesByCaster, playerClass, forceInRaid)
	local inRaid = forceInRaid
	if inRaid == nil then
		inRaid = _G.IsInRaid and LBB.Compat.SafeCall(_G.IsInRaid, false) or false
	end
	if not inRaid or not playerClass then
		return nil
	end
	local casters = {}
	local seen = {}
	for _, m in ipairs(roster or {}) do
		if m.class == playerClass and m.name and not seen[m.name] then
			if not capabilitiesByCaster or capabilitiesByCaster[m.name] then
				seen[m.name] = true
				table_insert(casters, m.name)
			end
		end
	end
	if #casters < 2 then
		return nil
	end
	table_sort(casters)
	return "RAID:" .. playerClass .. ":" .. table_concat(casters, ",")
end

-- Named Presets (Solo, Dungeon, Raid, or custom names) persisted per character
function Assignments:GetPresetsTable()
	if not LBB.CharDB then
		LBB.CharDB = {}
	end
	if type(LBB.CharDB.presets) ~= "table" then
		LBB.CharDB.presets = {}
	end
	return LBB.CharDB.presets
end

function Assignments:SavePreset(name)
	if type(name) ~= "string" then
		return false
	end
	name = name:match("^%s*(.-)%s*$")
	if name == "" then
		return false
	end
	local presets = self:GetPresetsTable()
	presets[name] = {
		name = name,
		assignments = self:SnapshotState(),
		paladinSelf = deepCopy(self:GetPaladinSelfConfig()),
		personalBuffs = deepCopy(self:GetPersonalConfig()),
		savedAt = LBB.Compat.GetTime(),
	}
	LBB.CharDB.activePresetName = name
	self:SaveToCharDB()
	return true
end

function Assignments:LoadPreset(name, skipPaladins)
	local presets = self:GetPresetsTable()
	local preset = presets[name]
	if not preset then
		return false
	end
	self:ApplySnapshot(preset.assignments, skipPaladins)
	if preset.paladinSelf and not skipPaladins then
		local cfg = self:GetPaladinSelfConfig()
		cfg.trackRF = preset.paladinSelf.trackRF and true or false
		cfg.trackSeal = preset.paladinSelf.trackSeal and true or false
		cfg.sealID = preset.paladinSelf.sealID
		cfg.sealName = preset.paladinSelf.sealName
		cfg.tankPrompted = true
	end
	if type(preset.personalBuffs) == "table" then
		LBB.CharDB = LBB.CharDB or {}
		LBB.CharDB.personalBuffs = deepCopy(preset.personalBuffs)
	end
	LBB.CharDB.activePresetName = name
	self:SaveToCharDB()
	return true
end

function Assignments:DeletePreset(name)
	local presets = self:GetPresetsTable()
	if not presets[name] then
		return false
	end
	presets[name] = nil
	if LBB.CharDB and LBB.CharDB.activePresetName == name then
		LBB.CharDB.activePresetName = nil
	end
	return true
end

function Assignments:ListPresets()
	local presets = self:GetPresetsTable()
	local names = {}
	for k in pairs(presets) do
		table_insert(names, k)
	end
	table_sort(names)
	return names
end

-- Unlock stale solo/previous-raid entries when entering a brand-new multi-caster raid
-- so auto-negotiation can split duties fresh across the new raid's casters.
function Assignments:UnlockForFreshRaid(playerName, playerClass, skipPaladins)
	if not playerName or not playerClass then
		return
	end
	if playerClass == "PALADIN" and not skipPaladins then
		if self.classBuffs[playerName] then
			for cls, entry in pairs(self.classBuffs[playerName]) do
				entry.locked = false
			end
		end
		if self.paladinAuras[playerName] then
			self.paladinAuras[playerName].locked = false
		end
	elseif playerClass == "SHAMAN" then
		for _, byCaster in pairs(self.shamanTotems) do
			local entry = byCaster[playerName]
			if entry and entry.locked then
				for _, el in ipairs(LBB.Catalog.TOTEM_ELEMENTS) do
					entry.locked[el] = false
				end
			end
		end
	else
		for famID, subs in pairs(self.groupBuffs) do
			local fam = LBB.Catalog.GetFamily(famID)
			if fam and fam.class == playerClass then
				for _, entry in pairs(subs) do
					if entry.caster == playerName then
						entry.locked = false
					end
				end
			end
		end
		for famID, targets in pairs(self.targetBuffs) do
			local fam = LBB.Catalog.GetFamily(famID)
			if fam and fam.class == playerClass then
				for _, entry in pairs(targets) do
					if entry.caster == playerName then
						entry.locked = false
					end
				end
			end
		end
		for famID, roles in pairs(self.roleBuffs) do
			local fam = LBB.Catalog.GetFamily(famID)
			if fam and fam.class == playerClass then
				for _, entry in pairs(roles) do
					if entry.caster == playerName then
						entry.locked = false
					end
				end
			end
		end
	end
end

function Assignments:ClearAll(preserveLocks, skipPaladins)
	if not preserveLocks then
		self.groupBuffs = {}
		self.targetBuffs = {}
		self.roleBuffs = {}
		self.shamanTotems = {}
		if not skipPaladins then
			self.classBuffs = {}
			self.paladinNormalOverrides = {}
			self.paladinAuras = {}
		end
		return
	end

	for famID, subs in pairs(self.groupBuffs) do
		for sg, entry in pairs(subs) do
			if not entry.locked then
				subs[sg] = nil
			end
		end
	end
	if not skipPaladins then
		for caster, byClass in pairs(self.classBuffs) do
			for cls, entry in pairs(byClass) do
				if not entry.locked then
					byClass[cls] = nil
				end
			end
		end
		for caster, entry in pairs(self.paladinAuras) do
			if not entry.locked then
				self.paladinAuras[caster] = nil
			end
		end
	end
	for famID, targets in pairs(self.targetBuffs) do
		for targetName, entry in pairs(targets) do
			if not entry.locked then
				targets[targetName] = nil
			end
		end
	end
	for famID, roles in pairs(self.roleBuffs) do
		for roleKey, entry in pairs(roles) do
			if not entry.locked then
				roles[roleKey] = nil
			end
		end
	end
	for sg, byCaster in pairs(self.shamanTotems) do
		for caster, entry in pairs(byCaster) do
			for _, el in ipairs(LBB.Catalog.TOTEM_ELEMENTS) do
				if not (entry.locked and entry.locked[el]) then
					entry[el] = nil
				end
			end
		end
	end
end

function Assignments:SetRoster(members)
	self.roster = {}
	self.rosterByName = {}
	self.rosterByUnit = {}
	for _, m in ipairs(members or {}) do
		local entry = {
			name = m.name,
			unit = m.unit,
			class = m.class,
			subgroup = m.subgroup or 1,
			role = m.role or (m.isMainTank and "TANK" or "NONE"),
			isMainTank = m.isMainTank and true or false,
			isMainAssist = m.isMainAssist and true or false,
			guid = m.guid or m.name,
			online = (m.online ~= false),
			alive = (m.alive ~= false),
			isLeader = m.isLeader and true or false,
			isAssist = m.isAssist and true or false,
		}
		table_insert(self.roster, entry)
		if entry.name then
			self.rosterByName[entry.name] = entry
		end
		if entry.unit then
			self.rosterByUnit[entry.unit] = entry
		end
	end
	table_sort(self.roster, function(a, b)
		if a.subgroup ~= b.subgroup then
			return a.subgroup < b.subgroup
		end
		return (a.name or "") < (b.name or "")
	end)
	return self.roster
end

function Assignments:RefreshRosterFromGame()
	local Compat = LBB.Compat
	local inCombat = Compat.InCombat()
	local prevByUnit = self.rosterByUnit or {}
	local prevRoster = self.roster or {}
	local members = {}
	local inRaid = _G.IsInRaid and Compat.SafeCall(_G.IsInRaid, false)
	local numGroup = _G.GetNumGroupMembers and Compat.SafeCall(_G.GetNumGroupMembers, 0) or 0

	if inRaid and numGroup > 0 then
		for i = 1, numGroup do
			local unit = "raid" .. i
			local prev = prevByUnit[unit]
			if Compat.UnitExists(unit) or (inCombat and prev) then
				local name, rank, subgroup, fileName, online, isDead, raidRole, combatRole = nil, 0, 1, nil, true, false, nil, nil
				if _G.GetRaidRosterInfo then
					local ok, n, r, sg, _, _, cls, _, onl, dead, rRole, _, cRole = pcall(_G.GetRaidRosterInfo, i)
					if ok and n and not Compat.IsSecret(n) then
						name = Compat.NormalizeName(n)
						rank = Compat.SafeRead(r, 0)
						subgroup = Compat.SafeRead(sg, 1)
						fileName = Compat.SafeRead(cls, nil)
						online = Compat.SafeRead(onl, true)
						isDead = Compat.SafeRead(dead, false)
						raidRole = Compat.SafeRead(rRole, nil)
						combatRole = Compat.SafeRead(cRole, nil)
					end
				end
				name = name or Compat.GetFullUnitName(unit) or (prev and prev.name)
				if not fileName then
					local _, cls = Compat.UnitClass(unit)
					fileName = cls or (prev and prev.class)
				end
				if name and fileName then
					local isMT = (raidRole == "MAINTANK") or Compat.GetPartyAssignment("MAINTANK", unit) or (inCombat and prev and prev.isMainTank) or false
					local isMA = (raidRole == "MAINASSIST") or Compat.GetPartyAssignment("MAINASSIST", unit) or (inCombat and prev and prev.isMainAssist) or false
					local role = Compat.UnitGroupRolesAssigned(unit)
					if not role or role == "NONE" then
						if isMT or combatRole == "TANK" then
							role = "TANK"
						elseif combatRole == "HEALER" then
							role = "HEALER"
						elseif combatRole == "DAMAGER" then
							role = "DAMAGER"
						elseif prev and prev.role then
							role = prev.role
						end
					end
					table_insert(members, {
						name = name,
						unit = unit,
						class = fileName,
						subgroup = subgroup or (prev and prev.subgroup) or 1,
						role = role or "NONE",
						isMainTank = isMT,
						isMainAssist = isMA,
						guid = Compat.UnitGUID(unit) or (prev and prev.guid) or name,
						online = online and Compat.UnitIsConnected(unit),
						alive = (not isDead) and (not Compat.UnitIsDeadOrGhost(unit)),
						isLeader = (rank == 2) or (inCombat and prev and prev.isLeader) or false,
						isAssist = (rank == 1) or (inCombat and prev and prev.isAssist) or false,
					})
				end
			end
		end
	else
		-- Solo or 5-man party
		local units = { "player" }
		local partyCount = numGroup > 1 and 4 or 0
		if partyCount == 0 and inCombat and #prevRoster > 1 then
			partyCount = 4
		end
		for i = 1, partyCount do
			local u = "party" .. i
			if Compat.UnitExists(u) or (inCombat and prevByUnit[u]) then
				table_insert(units, u)
			end
		end
		for _, unit in ipairs(units) do
			local prev = prevByUnit[unit]
			if Compat.UnitExists(unit) or (inCombat and prev) then
				local name = Compat.GetFullUnitName(unit) or (prev and prev.name)
				local _, cls = Compat.UnitClass(unit)
				cls = cls or (prev and prev.class)
				if name and cls then
					local isMT = Compat.GetPartyAssignment("MAINTANK", unit) or (inCombat and prev and prev.isMainTank) or false
					local isMA = Compat.GetPartyAssignment("MAINASSIST", unit) or (inCombat and prev and prev.isMainAssist) or false
					local role = Compat.UnitGroupRolesAssigned(unit)
					if not role or role == "NONE" then
						if isMT then
							role = "TANK"
						elseif prev and prev.role then
							role = prev.role
						end
					end
					table_insert(members, {
						name = name,
						unit = unit,
						class = cls,
						subgroup = (prev and prev.subgroup) or 1,
						role = role or "NONE",
						isMainTank = isMT,
						isMainAssist = isMA,
						guid = Compat.UnitGUID(unit) or (prev and prev.guid) or name,
						online = Compat.UnitIsConnected(unit),
						alive = not Compat.UnitIsDeadOrGhost(unit),
						isLeader = _G.UnitIsGroupLeader and Compat.SafeCall(_G.UnitIsGroupLeader, prev and prev.isLeader or false, unit) or false,
						isAssist = _G.UnitIsGroupAssistant and Compat.SafeCall(_G.UnitIsGroupAssistant, prev and prev.isAssist or false, unit) or false,
					})
				end
			end
		end
	end

	-- Guard against complete roster loss if Midnight combat secrets blocked unit queries mid-fight
	if inCombat and #members <= 1 and #prevRoster > #members then
		return self.roster
	end

	return self:SetRoster(members)
end

-- Setters & Lock helpers

function Assignments:SetGroupBuff(familyID, subgroup, casterName, locked)
	if not familyID or not subgroup then
		return
	end
	self.groupBuffs[familyID] = self.groupBuffs[familyID] or {}
	if not casterName or casterName == "" then
		if locked then
			self.groupBuffs[familyID][subgroup] = { caster = nil, locked = true }
		else
			self.groupBuffs[familyID][subgroup] = nil
		end
		return
	end
	self.groupBuffs[familyID][subgroup] = {
		caster = casterName,
		locked = locked and true or false,
	}
end

function Assignments:SetAllGroupBuffs(familyID, casterName, locked)
	if not familyID then
		return
	end
	for sg = 1, 8 do
		self:SetGroupBuff(familyID, sg, casterName, locked)
	end
	self:SaveToCharDB()
end

function Assignments:SetAllClassBuffs(casterName, familyID, locked)
	if not casterName then
		return
	end
	for _, cls in ipairs(LBB.Catalog.CLASS_ORDER) do
		self:SetClassBuff(casterName, cls, familyID, locked)
	end
	self:SaveToCharDB()
end

function Assignments:GetGroupBuff(familyID, subgroup)
	return self.groupBuffs[familyID] and self.groupBuffs[familyID][subgroup] or nil
end

function Assignments:SetGroupBuffLock(familyID, subgroup, locked)
	if self.groupBuffs[familyID] and self.groupBuffs[familyID][subgroup] then
		self.groupBuffs[familyID][subgroup].locked = locked and true or false
	end
end

function Assignments:SetClassBuff(casterName, classToken, familyID, locked)
	if not casterName or not classToken then
		return
	end
	self.classBuffs[casterName] = self.classBuffs[casterName] or {}
	if not familyID or familyID == "" then
		if locked then
			self.classBuffs[casterName][classToken] = { familyID = nil, locked = true }
		else
			self.classBuffs[casterName][classToken] = nil
		end
		return
	end
	self.classBuffs[casterName][classToken] = {
		familyID = familyID,
		locked = locked and true or false,
	}
end

function Assignments:GetClassBuff(casterName, classToken)
	return self.classBuffs[casterName] and self.classBuffs[casterName][classToken] or nil
end

function Assignments:SetTargetBuff(familyID, targetName, casterName, locked)
	if not familyID or not targetName then
		return
	end
	self.targetBuffs[familyID] = self.targetBuffs[familyID] or {}
	if not casterName or casterName == "" then
		if locked then
			self.targetBuffs[familyID][targetName] = { caster = nil, locked = true }
		else
			self.targetBuffs[familyID][targetName] = nil
		end
		return
	end
	self.targetBuffs[familyID][targetName] = {
		caster = casterName,
		locked = locked and true or false,
	}
end

function Assignments:GetTargetBuff(familyID, targetName)
	return self.targetBuffs[familyID] and self.targetBuffs[familyID][targetName] or nil
end

function Assignments:SetRoleBuff(familyID, roleKey, casterName, locked)
	if not familyID or not roleKey then
		return
	end
	self.roleBuffs[familyID] = self.roleBuffs[familyID] or {}
	if not casterName or casterName == "" then
		if locked then
			self.roleBuffs[familyID][roleKey] = { caster = nil, locked = true }
		else
			self.roleBuffs[familyID][roleKey] = nil
		end
		return
	end
	self.roleBuffs[familyID][roleKey] = {
		caster = casterName,
		locked = locked and true or false,
	}
end

function Assignments:GetRoleBuff(familyID, roleKey)
	return self.roleBuffs[familyID] and self.roleBuffs[familyID][roleKey] or nil
end

function Assignments:SetPaladinNormalOverride(casterName, targetName, classToken, familyID, locked)
	if not casterName or not targetName then
		return
	end
	self.paladinNormalOverrides[casterName] = self.paladinNormalOverrides[casterName] or {}
	if not familyID or familyID == "" then
		self.paladinNormalOverrides[casterName][targetName] = nil
		return
	end
	self.paladinNormalOverrides[casterName][targetName] = {
		familyID = familyID,
		class = classToken,
		locked = locked ~= false,
	}
end

function Assignments:GetPaladinNormalOverride(casterName, targetName)
	return self.paladinNormalOverrides[casterName] and self.paladinNormalOverrides[casterName][targetName] or nil
end

function Assignments:GetPaladinNormalOverridesForClass(casterName, classToken)
	local out = {}
	local byTarget = self.paladinNormalOverrides[casterName]
	if not byTarget then
		return out
	end
	for targetName, entry in pairs(byTarget) do
		local member = self.rosterByName[targetName]
		local cls = entry.class or (member and member.class)
		if cls == classToken and entry.familyID then
			table_insert(out, {
				target = targetName,
				class = cls,
				familyID = entry.familyID,
				locked = entry.locked and true or false,
			})
		end
	end
	table_sort(out, function(a, b)
		return a.target < b.target
	end)
	return out
end

function Assignments:ClearPaladinNormalOverridesForClass(casterName, classToken)
	local byTarget = self.paladinNormalOverrides[casterName]
	if not byTarget then
		return
	end
	for targetName, entry in pairs(byTarget) do
		local member = self.rosterByName[targetName]
		local cls = entry.class or (member and member.class)
		if cls == classToken then
			byTarget[targetName] = nil
		end
	end
end

-- Per-character All-Class Personal Self-Buff config (Inner Fire, Shadowform, Imbues, Shields, Armors, Soul Link, Aspects, Self-Thorns, etc.)
function Assignments:GetPersonalConfig()
	if not LBB.CharDB then
		LBB.CharDB = {}
	end
	if type(LBB.CharDB.personalBuffs) ~= "table" then
		LBB.CharDB.personalBuffs = {}
	end
	return LBB.CharDB.personalBuffs
end

function Assignments:GetPersonalSlot(slotID)
	if not slotID then
		return nil
	end
	local cfg = self:GetPersonalConfig()
	return cfg[slotID]
end

function Assignments:SetPersonalToggle(slotID, enabled, optEntry)
	if not slotID then
		return nil
	end
	local cfg = self:GetPersonalConfig()
	if not enabled then
		cfg[slotID] = {
			enabled = false,
			optionID = nil,
			optionName = nil,
		}
	else
		cfg[slotID] = {
			enabled = true,
			optionID = optEntry and optEntry.id or nil,
			optionName = optEntry and optEntry.name or nil,
		}
	end
	return cfg[slotID]
end

function Assignments:SetPersonalChoice(slotID, optEntry)
	if not slotID then
		return nil
	end
	local cfg = self:GetPersonalConfig()
	if not optEntry then
		cfg[slotID] = {
			enabled = false,
			optionID = nil,
			optionName = nil,
		}
	else
		cfg[slotID] = {
			enabled = true,
			optionID = optEntry.id,
			optionName = optEntry.name,
		}
	end
	return cfg[slotID]
end

-- Per-character Paladin Self-Buff config (Righteous Fury & Seal opt-in)
function Assignments:GetPaladinSelfConfig()
	if not LBB.CharDB then
		LBB.CharDB = {}
	end
	if not LBB.CharDB.paladinSelf then
		LBB.CharDB.paladinSelf = {
			trackRF = false,
			trackSeal = false,
			sealID = nil,
			sealName = nil,
			tankPrompted = false,
		}
	end
	return LBB.CharDB.paladinSelf
end

function Assignments:SetRighteousFuryEnabled(enabled)
	local cfg = self:GetPaladinSelfConfig()
	cfg.trackRF = enabled and true or false
	cfg.tankPrompted = true
	return cfg
end

function Assignments:SetSelectedSeal(sealEntry)
	local cfg = self:GetPaladinSelfConfig()
	if not sealEntry then
		cfg.trackSeal = false
		cfg.sealID = nil
		cfg.sealName = nil
	else
		cfg.trackSeal = true
		cfg.sealID = sealEntry.id
		cfg.sealName = sealEntry.name
		cfg.tankPrompted = true
	end
	return cfg
end

function Assignments:EnableProtSelfDefaults()
	local cfg = self:GetPaladinSelfConfig()
	local vec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector()
	cfg.tankPrompted = true
	if vec and vec.righteousFury and vec.righteousFury.known then
		cfg.trackRF = true
	end
	if vec and vec.sealsList and #vec.sealsList > 0 then
		-- Prefer Seal of Fury (Forever tank seal), else Seal of Righteousness, else first known seal
		local pick = vec.seals.SEAL_OF_FURY or vec.seals.SEAL_OF_RIGHTEOUSNESS or vec.sealsList[1]
		if pick then
			cfg.trackSeal = true
			cfg.sealID = pick.id
			cfg.sealName = pick.name
		end
	end
	return cfg
end

function Assignments:DismissProtRFPrompt()
	local cfg = self:GetPaladinSelfConfig()
	cfg.tankPrompted = true
end

function Assignments:ShouldPromptProtRF()
	local vec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector()
	if not vec or vec.class ~= "PALADIN" then
		return false
	end
	if not (vec.righteousFury and vec.righteousFury.known) then
		return false
	end
	if LBB.Comms and LBB.Comms:IsPallyPowerLoaded() then
		return false
	end
	local cfg = self:GetPaladinSelfConfig()
	if cfg.tankPrompted or cfg.trackRF then
		return false
	end
	local role = LBB.Compat.UnitGroupRolesAssigned("player")
	if role ~= "TANK" then
		local m = self.rosterByName[vec.name]
		role = m and m.role or "NONE"
	end
	return role == "TANK"
end

function Assignments:SetPaladinAura(casterName, auraID, locked)
	if not casterName then
		return
	end
	if not auraID or auraID == 0 then
		if locked then
			self.paladinAuras[casterName] = { auraID = 0, locked = true }
		else
			self.paladinAuras[casterName] = nil
		end
		return
	end
	self.paladinAuras[casterName] = {
		auraID = auraID,
		locked = locked and true or false,
	}
end

function Assignments:GetPaladinAura(casterName)
	return self.paladinAuras[casterName]
end

function Assignments:SetShamanTotem(subgroup, casterName, element, totemID, locked)
	if not subgroup or not casterName or not element then
		return
	end
	self.shamanTotems[subgroup] = self.shamanTotems[subgroup] or {}
	local entry = self.shamanTotems[subgroup][casterName]
	if not entry then
		entry = { locked = {} }
		self.shamanTotems[subgroup][casterName] = entry
	end
	entry[element] = totemID
	if locked ~= nil then
		entry.locked[element] = locked and true or false
	end
end

function Assignments:GetShamanTotems(subgroup, casterName)
	return self.shamanTotems[subgroup] and self.shamanTotems[subgroup][casterName] or nil
end

-- Build active duty list for a specific player (consumed by BuffStrip, Scanner, RaidIndicators)
function Assignments:GetPlayerDuties(playerName)
	local Catalog = LBB.Catalog
	local duties = {}
	if not playerName then
		return duties
	end

	-- 1. Group-scoped buffs (combine multiple subgroups for the same buff family into one clean HUD duty)
	for _, famID in ipairs(Catalog.FAMILY_ORDER) do
		local fam = Catalog.GetFamily(famID)
		if fam and (fam.scope == "GROUP" or fam.scope == "PARTY") then
			local subs = self.groupBuffs[famID]
			if subs then
				local mySubgroups = {}
				local anyLocked = false
				for sg = 1, 8 do
					local e = subs[sg]
					if e and e.caster == playerName then
						table_insert(mySubgroups, sg)
						if e.locked then
							anyLocked = true
						end
					end
				end
				if #mySubgroups > 0 then
					table_insert(duties, {
						key = "GROUP:" .. famID,
						kind = "GROUP_BUFF",
						familyID = famID,
						caster = playerName,
						subgroups = mySubgroups,
						locked = anyLocked,
						reagentItemID = fam.reagentItemID,
					})
				end
			end
		end
	end

	-- 2. Paladin Class Blessings + Per-Player Overrides (PallyPower NASSIGN compatible)
	local myClasses = self.classBuffs[playerName]
	local myOverrides = self.paladinNormalOverrides[playerName]
	if myClasses or myOverrides then
		local byFamily = {}
		local familyOrder = {}
		local function ensureFamily(famID)
			if not byFamily[famID] then
				byFamily[famID] = {
					classes = {},
					excludedTargets = {},
					overrideTargets = {},
					hasClassOverride = false,
					locked = false,
				}
				table_insert(familyOrder, famID)
			end
			return byFamily[famID]
		end

		if myClasses then
			for _, cls in ipairs(Catalog.CLASS_ORDER) do
				local e = myClasses[cls]
				if e and e.familyID then
					local bucket = ensureFamily(e.familyID)
					table_insert(bucket.classes, cls)
					if e.locked then
						bucket.locked = true
					end
				end
			end
		end

		if myOverrides then
			local sortedTargets = {}
			for tName in pairs(myOverrides) do
				table_insert(sortedTargets, tName)
			end
			table_sort(sortedTargets)
			for _, tName in ipairs(sortedTargets) do
				local ov = myOverrides[tName]
				if ov and ov.familyID then
					local member = self.rosterByName[tName]
					local cls = ov.class or (member and member.class)
					local classDefault = cls and myClasses and myClasses[cls] and myClasses[cls].familyID or nil

					-- Exclude overridden player from their class-default blessing duty
					if classDefault and classDefault ~= ov.familyID and byFamily[classDefault] then
						byFamily[classDefault].excludedTargets[tName] = true
						byFamily[classDefault].hasClassOverride = true
					end

					-- Attach player to their overridden blessing duty
					local targetBucket = ensureFamily(ov.familyID)
					table_insert(targetBucket.overrideTargets, tName)
					if classDefault and classDefault ~= ov.familyID then
						targetBucket.hasClassOverride = true
					end
					if ov.locked then
						targetBucket.locked = true
					end
				end
			end
		end

		for _, famID in ipairs(familyOrder) do
			local fam = Catalog.GetFamily(famID)
			local bucket = byFamily[famID]
			table_insert(duties, {
				key = "CLASS:" .. famID,
				kind = "CLASS_BUFF",
				familyID = famID,
				caster = playerName,
				classes = bucket.classes,
				excludedTargets = bucket.excludedTargets,
				overrideTargets = bucket.overrideTargets,
				hasClassOverride = bucket.hasClassOverride,
				locked = bucket.locked,
				reagentItemID = fam and fam.reagentItemID or nil,
			})
		end
	end

	-- 3. Role-scoped & Target-scoped buffs (Thorns on Tanks, Fear Ward, Soulstone, Dampen/Amplify, etc.)
	for _, famID in ipairs(Catalog.FAMILY_ORDER) do
		local fam = Catalog.GetFamily(famID)
		if fam and fam.scope == "TARGET" then
			local roles = {}
			local targets = {}
			local anyLocked = false

			local rMap = self.roleBuffs[famID]
			if rMap then
				for _, rKey in ipairs(Catalog.ROLE_ORDER or {}) do
					local re = rMap[rKey]
					if re and re.caster == playerName then
						table_insert(roles, rKey)
						if re.locked then
							anyLocked = true
						end
					end
				end
			end

			local tMap = self.targetBuffs[famID]
			if tMap then
				for targetName, e in pairs(tMap) do
					if e and e.caster == playerName then
						table_insert(targets, targetName)
						if e.locked then
							anyLocked = true
						end
					end
				end
				table_sort(targets)
			end

			if #roles > 0 or #targets > 0 then
				table_insert(duties, {
					key = "TARGET:" .. famID,
					kind = "TARGET_BUFF",
					familyID = famID,
					caster = playerName,
					roles = roles,
					targets = targets,
					locked = anyLocked,
					reagentItemID = fam.reagentItemID,
				})
			end
		end
	end

	-- 4. Paladin Aura
	local auraEntry = self.paladinAuras[playerName]
	if auraEntry and auraEntry.auraID and auraEntry.auraID > 0 then
		table_insert(duties, {
			key = "AURA:" .. tostring(auraEntry.auraID),
			kind = "PALADIN_AURA",
			auraID = auraEntry.auraID,
			caster = playerName,
			locked = auraEntry.locked and true or false,
		})
	end

	-- 4b. Paladin Personal Self-Buffs: Righteous Fury & Seal (opt-in per character)
	local localVec = LBB.Capabilities and LBB.Capabilities.playerVector
	if localVec and localVec.name == playerName and localVec.class == "PALADIN" then
		local selfCfg = self:GetPaladinSelfConfig()
		if selfCfg.trackRF and localVec.righteousFury and localVec.righteousFury.known then
			table_insert(duties, {
				key = "SELF:RIGHTEOUS_FURY",
				kind = "RIGHTEOUS_FURY",
				caster = playerName,
				spellID = localVec.righteousFury.spellID,
				spellName = localVec.righteousFury.name,
				icon = localVec.righteousFury.icon,
			})
		end
		if selfCfg.trackSeal and (selfCfg.sealID or selfCfg.sealName) then
			local sealInfo = (selfCfg.sealID and localVec.seals and localVec.seals[selfCfg.sealID]) or nil
			if not sealInfo and selfCfg.sealName and localVec.sealsList then
				for _, s in ipairs(localVec.sealsList) do
					if s.name == selfCfg.sealName then
						sealInfo = s
						break
					end
				end
			end
			if sealInfo then
				table_insert(duties, {
					key = "SELF:SEAL",
					kind = "PALADIN_SEAL",
					caster = playerName,
					sealID = sealInfo.id,
					spellID = sealInfo.spellID,
					spellName = sealInfo.name,
					icon = sealInfo.icon,
					allSpellIDs = sealInfo.allSpellIDs,
				})
			end
		end
	end

	-- 4c. All-Class Personal Self-Buffs (Inner Fire, Shadowform, Shaman Imbues/Shields, Mage/Warlock Armors, Soul Link, Aspects, Self-Thorns, etc.)
	if localVec and localVec.name == playerName and localVec.personal then
		local activeFamilies = {}
		for _, d in ipairs(duties) do
			if d.familyID then
				activeFamilies[d.familyID] = true
			end
		end
		local slotDefs = Catalog.PERSONAL_SLOTS and Catalog.PERSONAL_SLOTS[localVec.class] or {}
		local pCfg = self:GetPersonalConfig()
		for _, slotDef in ipairs(slotDefs) do
			local cfgEntry = pCfg[slotDef.slotID]
			local slotBucket = localVec.personal[slotDef.slotID]
			if cfgEntry and cfgEntry.enabled and slotBucket and slotBucket.list and #slotBucket.list > 0 then
				local optInfo = nil
				if slotDef.mode == "TOGGLE" then
					optInfo = (cfgEntry.optionID and slotBucket.byID[cfgEntry.optionID]) or slotBucket.list[1]
				else
					optInfo = (cfgEntry.optionID and slotBucket.byID[cfgEntry.optionID])
						or (cfgEntry.optionName and slotBucket.byName[cfgEntry.optionName])
				end
				if optInfo and not (optInfo.dedupeFamilyID and activeFamilies[optInfo.dedupeFamilyID]) then
					table_insert(duties, {
						key = "SELF:" .. slotDef.slotID,
						kind = "PERSONAL_BUFF",
						slotID = slotDef.slotID,
						slotLabel = slotDef.label,
						optionID = optInfo.id,
						caster = playerName,
						spellID = optInfo.spellID,
						spellName = optInfo.name,
						shortName = optInfo.shortName,
						icon = optInfo.icon,
						defaultDuration = optInfo.duration or 1800,
						checkType = slotDef.checkType or "AURA",
						isPermanentToggle = slotDef.isPermanentToggle and true or false,
						requiresPet = slotDef.requiresPet and true or false,
						allSpellIDs = optInfo.allSpellIDs,
					})
				end
			end
		end
	end

	-- 5. Shaman Totems
	local member = self.rosterByName[playerName]
	local mySubgroup = member and member.subgroup or 1
	local totemEntry = self:GetShamanTotems(mySubgroup, playerName)
	if totemEntry then
		for _, element in ipairs(Catalog.TOTEM_ELEMENTS) do
			local tid = totemEntry[element]
			if tid and Catalog.TOTEM_BY_ID[tid] then
				table_insert(duties, {
					key = "TOTEM:" .. element,
					kind = "SHAMAN_TOTEM",
					element = element,
					totemID = tid,
					subgroup = mySubgroup,
					caster = playerName,
					locked = totemEntry.locked and totemEntry.locked[element] or false,
				})
			end
		end
	end

	return duties
end

-- Determine which buff families are assigned to `playerName` for a specific unit
function Assignments:GetAssignedFamiliesForUnit(playerName, unitInfo)
	local list = {}
	if not playerName or not unitInfo then
		return list
	end
	local seen = {}
	local function add(famID)
		if famID and not seen[famID] then
			seen[famID] = true
			table_insert(list, famID)
		end
	end

	local Catalog = LBB.Catalog
	for famID, subs in pairs(self.groupBuffs) do
		local e = subs[unitInfo.subgroup or 1]
		if e and e.caster == playerName then
			local fam = Catalog.GetFamily(famID)
			if fam and Catalog.MatchesUnitFilter(fam, unitInfo) then
				add(famID)
			end
		end
	end

	-- Paladin normal override takes precedence over class blessing if set
	local normOverride = self.paladinNormalOverrides[playerName] and self.paladinNormalOverrides[playerName][unitInfo.name]
	if normOverride and normOverride.familyID then
		add(normOverride.familyID)
	else
		local clsEntry = self.classBuffs[playerName] and self.classBuffs[playerName][unitInfo.class]
		if clsEntry and clsEntry.familyID then
			add(clsEntry.familyID)
		end
	end

	for famID, roles in pairs(self.roleBuffs) do
		for roleKey, e in pairs(roles) do
			if e and e.caster == playerName and Catalog.MatchesRoleFilter(roleKey, unitInfo) then
				add(famID)
			end
		end
	end

	for famID, targets in pairs(self.targetBuffs) do
		local e = targets[unitInfo.name]
		if e and e.caster == playerName then
			add(famID)
		end
	end

	return list
end
