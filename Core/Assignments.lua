local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Assignments = {}
LBB.Assignments = Assignments

local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort

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
	-- paladinNormalOverrides[casterName][targetName] = { familyID = famID, class = classToken, locked = bool }
	self.paladinNormalOverrides = {}
	-- paladinAuras[casterName] = { auraID = 1..7 or 0, locked = bool }
	self.paladinAuras = {}
	-- shamanTotems[subgroup][casterName] = { EARTH = id, FIRE = id, WATER = id, AIR = id, locked = { ... } }
	self.shamanTotems = {}
end

Assignments:Reset()

function Assignments:ClearAll(preserveLocks, skipPaladins)
	if not preserveLocks then
		self.groupBuffs = {}
		self.targetBuffs = {}
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
			role = m.role or "NONE",
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
	local members = {}
	local inRaid = _G.IsInRaid and Compat.SafeCall(_G.IsInRaid, false)
	local numGroup = _G.GetNumGroupMembers and Compat.SafeCall(_G.GetNumGroupMembers, 0) or 0

	if inRaid and numGroup > 0 then
		for i = 1, numGroup do
			local unit = "raid" .. i
			if Compat.UnitExists(unit) then
				local name, rank, subgroup, _, _, fileName, _, online, isDead = nil, 0, 1, nil, nil, nil, nil, true, false
				if _G.GetRaidRosterInfo then
					local ok, n, r, sg, _, _, cls, _, onl, dead = pcall(_G.GetRaidRosterInfo, i)
					if ok and n and not Compat.IsSecret(n) then
						name = Compat.NormalizeName(n)
						rank = Compat.SafeRead(r, 0)
						subgroup = Compat.SafeRead(sg, 1)
						fileName = Compat.SafeRead(cls, nil)
						online = Compat.SafeRead(onl, true)
						isDead = Compat.SafeRead(dead, false)
					end
				end
				name = name or Compat.GetFullUnitName(unit)
				if not fileName then
					local _, cls = Compat.UnitClass(unit)
					fileName = cls
				end
				if name and fileName then
					table_insert(members, {
						name = name,
						unit = unit,
						class = fileName,
						subgroup = subgroup or 1,
						role = Compat.UnitGroupRolesAssigned(unit),
						guid = Compat.UnitGUID(unit) or name,
						online = online and Compat.UnitIsConnected(unit),
						alive = (not isDead) and (not Compat.UnitIsDeadOrGhost(unit)),
						isLeader = (rank == 2),
						isAssist = (rank == 1),
					})
				end
			end
		end
	else
		-- Solo or 5-man party
		local units = { "player" }
		if numGroup > 1 then
			for i = 1, 4 do
				local u = "party" .. i
				if Compat.UnitExists(u) then
					table_insert(units, u)
				end
			end
		end
		for _, unit in ipairs(units) do
			if Compat.UnitExists(unit) then
				local name = Compat.GetFullUnitName(unit)
				local _, cls = Compat.UnitClass(unit)
				if name and cls then
					table_insert(members, {
						name = name,
						unit = unit,
						class = cls,
						subgroup = 1,
						role = Compat.UnitGroupRolesAssigned(unit),
						guid = Compat.UnitGUID(unit) or name,
						online = Compat.UnitIsConnected(unit),
						alive = not Compat.UnitIsDeadOrGhost(unit),
						isLeader = _G.UnitIsGroupLeader and Compat.SafeCall(_G.UnitIsGroupLeader, false, unit) or false,
						isAssist = _G.UnitIsGroupAssistant and Compat.SafeCall(_G.UnitIsGroupAssistant, false, unit) or false,
					})
				end
			end
		end
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

	-- 3. Target-scoped buffs (Thorns, Soulstone, Dampen/Amplify, etc.)
	for _, famID in ipairs(Catalog.FAMILY_ORDER) do
		local fam = Catalog.GetFamily(famID)
		if fam and fam.scope == "TARGET" then
			local tMap = self.targetBuffs[famID]
			if tMap then
				local targets = {}
				local anyLocked = false
				for targetName, e in pairs(tMap) do
					if e and e.caster == playerName then
						table_insert(targets, targetName)
						if e.locked then
							anyLocked = true
						end
					end
				end
				table_sort(targets)
				if #targets > 0 then
					table_insert(duties, {
						key = "TARGET:" .. famID,
						kind = "TARGET_BUFF",
						familyID = famID,
						caster = playerName,
						targets = targets,
						locked = anyLocked,
						reagentItemID = fam.reagentItemID,
					})
				end
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

	for famID, targets in pairs(self.targetBuffs) do
		local e = targets[unitInfo.name]
		if e and e.caster == playerName then
			add(famID)
		end
	end

	return list
end
