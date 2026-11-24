local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Capabilities = {}
LBB.Capabilities = Capabilities

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local math_floor = math.floor
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat

Capabilities.playerVector = nil
Capabilities.peers = {}
Capabilities.pendingSpellLoads = {}
Capabilities.trackingState = {
	list = {},
	byName = {},
	bySpellID = {},
	active = nil,
}

function Capabilities:Reset()
	self.playerVector = nil
	self.peers = {}
	self.pendingSpellLoads = {}
	self.trackingState = {
		list = {},
		byName = {},
		bySpellID = {},
		active = nil,
	}
end

-- Inspect talents via modern C_ClassTalents / C_Traits first, falling back to legacy talent API if available
function Capabilities:ScanTalents()
	local Compat = LBB.Compat
	local ranksByName = {}

	-- 1. Modern Dragonflight / Midnight / Forever Trait Tree API
	if _G.C_ClassTalents and _G.C_ClassTalents.GetActiveConfigID and _G.C_Traits then
		local configID = Compat.SafeCall(_G.C_ClassTalents.GetActiveConfigID, nil)
		if configID and configID > 0 and _G.C_Traits.GetConfigInfo then
			local configInfo = Compat.SafeCall(_G.C_Traits.GetConfigInfo, nil, configID)
			if configInfo and type(configInfo.treeIDs) == "table" then
				for _, treeID in ipairs(configInfo.treeIDs) do
					local nodeIDs = Compat.SafeCall(_G.C_Traits.GetTreeNodes, nil, treeID)
					if type(nodeIDs) == "table" then
						for _, nodeID in ipairs(nodeIDs) do
							local nodeInfo = Compat.SafeCall(_G.C_Traits.GetNodeInfo, nil, configID, nodeID)
							if nodeInfo and (nodeInfo.ranksPurchased or 0) > 0 then
								local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
								if not entryID and type(nodeInfo.entryIDs) == "table" then
									entryID = nodeInfo.entryIDs[1]
								end
								if entryID and _G.C_Traits.GetEntryInfo then
									local entryInfo = Compat.SafeCall(_G.C_Traits.GetEntryInfo, nil, configID, entryID)
									if entryInfo and entryInfo.definitionID and _G.C_Traits.GetDefinitionInfo then
										local defInfo = Compat.SafeCall(_G.C_Traits.GetDefinitionInfo, nil, entryInfo.definitionID)
										if defInfo then
											local tName = defInfo.overrideName
											if (not tName or tName == "") and defInfo.spellID then
												local sInfo = Compat.GetSpellInfo(defInfo.spellID)
												tName = sInfo and sInfo.name or nil
											end
											if tName and tName ~= "" then
												local r = nodeInfo.activeRank or nodeInfo.ranksPurchased or 0
												if r > (ranksByName[tName] or 0) then
													ranksByName[tName] = r
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- 2. Legacy Classic talent API fallback (only if present in client/mock)
	if _G.GetNumTalentTabs and _G.GetNumTalents and _G.GetTalentInfo then
		local numTabs = Compat.SafeCall(_G.GetNumTalentTabs, 0)
		for tab = 1, numTabs do
			local numTalents = Compat.SafeCall(_G.GetNumTalents, 0, tab)
			for idx = 1, numTalents do
				local ok, name, _, _, _, currentRank = pcall(_G.GetTalentInfo, tab, idx)
				if ok and name and not Compat.IsSecret(name) and type(currentRank) == "number" and not Compat.IsSecret(currentRank) then
					if currentRank > (ranksByName[name] or 0) then
						ranksByName[name] = currentRank
					end
				end
			end
		end
	end

	return ranksByName
end

local function findBestKnownRank(ranks, pending)
	local Compat = LBB.Compat
	if not ranks then
		return nil
	end
	for _, entry in ipairs(ranks) do
		local spellID = type(entry) == "table" and entry.spellID or entry
		local rankNum = type(entry) == "table" and (entry.rank or 1) or 1
		if Compat.IsSpellKnown(spellID) then
			local info = Compat.GetSpellInfo(spellID)
			if not info then
				pending[spellID] = true
				Compat.RequestLoadSpellData(spellID)
			end
			return {
				spellID = spellID,
				rank = rankNum,
				name = info and info.name or nil,
				iconID = info and info.iconID or nil,
			}
		end
	end
	return nil
end

function Capabilities:ClassifyTracking(name)
	local Catalog = LBB.Catalog
	if not name then
		return "OTHER"
	end
	for category, list in pairs(Catalog.TRACKING_PATTERNS) do
		for _, pattern in ipairs(list) do
			if name == pattern or name:find(pattern, 1, true) then
				return category
			end
		end
	end
	return "OTHER"
end

function Capabilities:ScanTracking()
	local Compat = LBB.Compat
	local state = {
		list = {},
		byName = {},
		bySpellID = {},
		active = nil,
	}
	local count = Compat.GetNumTrackingTypes()
	for i = 1, count do
		local info = Compat.GetTrackingInfo(i)
		if info and info.name then
			local entry = {
				index = i,
				name = info.name,
				texture = info.texture,
				active = info.active and true or false,
				spellID = info.spellID,
				category = self:ClassifyTracking(info.name),
				rawCategory = info.category,
			}
			table_insert(state.list, entry)
			state.byName[entry.name] = entry
			if entry.spellID then
				state.bySpellID[entry.spellID] = entry
			end
			if entry.active then
				state.active = entry
			end
		end
	end
	self.trackingState = state
	return state
end

function Capabilities:RefreshReagents()
	if not self.playerVector then
		return self:ScanPlayer()
	end
	local Compat = LBB.Compat
	local Catalog = LBB.Catalog
	local vec = self.playerVector
	local families = Catalog.GetClassFamilies(vec.class)
	vec.reagents = vec.reagents or {}
	for _, famID in ipairs(families) do
		local fam = Catalog.GetFamily(famID)
		if fam and fam.reagentItemID then
			vec.reagents[fam.reagentItemID] = Compat.GetItemCount(fam.reagentItemID)
		end
	end
	vec.symbols = vec.reagents[21177] or 0
	return vec
end

function Capabilities:ScanPlayer()
	local Compat = LBB.Compat
	local Catalog = LBB.Catalog
	local prev = self.playerVector

	local playerName = Compat.GetFullUnitName("player") or (prev and prev.name) or "Player"
	local _, classToken = Compat.UnitClass("player")
	classToken = classToken or (prev and prev.class) or "PRIEST"
	local guid = Compat.UnitGUID("player") or (prev and prev.guid) or playerName

	local talents = self:ScanTalents()
	local families = Catalog.GetClassFamilies(classToken)
	local knownBuffs = {}
	local reagents = {}

	for _, famID in ipairs(families) do
		local fam = Catalog.GetFamily(famID)
		if fam then
			local single = findBestKnownRank(fam.singleRanks, self.pendingSpellLoads)
			local group = findBestKnownRank(fam.groupRanks, self.pendingSpellLoads)
			if single or group then
				local talentRank = 0
				local weightPerRank = 0
				if fam.talent then
					talentRank = talents[fam.talent.name] or 0
					weightPerRank = fam.talent.weightPerRank or 10
					if fam.talentGated and talentRank == 0 then
						talentRank = 1
					end
				end
				local bestRank = single and single.rank or (group and group.rank or 1)
				local hasGroup = group ~= nil
				local priorityScore = (bestRank * 10) + (hasGroup and 15 or 0) + (talentRank * weightPerRank)

				knownBuffs[famID] = {
					familyID = famID,
					known = true,
					bestSingleID = single and single.spellID or nil,
					bestSingleRank = single and single.rank or 0,
					bestSingleName = (single and single.name) or fam.name,
					bestGroupID = group and group.spellID or nil,
					bestGroupRank = group and group.rank or 0,
					bestGroupName = (group and group.name) or fam.groupName,
					hasGroup = hasGroup,
					icon = (single and single.iconID) or (group and group.iconID) or fam.icon,
					talentRank = talentRank,
					priorityScore = priorityScore,
				}
			end
			if fam.reagentItemID and reagents[fam.reagentItemID] == nil then
				reagents[fam.reagentItemID] = Compat.GetItemCount(fam.reagentItemID)
			end
		end
	end

	-- Paladin Auras, Righteous Fury & Seals (static catalog + dynamic C_SpellBook scan for Forever seals)
	local knownAuras = {}
	local righteousFury = nil
	local knownSeals = {}
	local knownSealsList = {}

	if classToken == "PALADIN" then
		for auraID, auraDef in ipairs(Catalog.PALADIN_AURAS) do
			local best = findBestKnownRank(auraDef.ranks, self.pendingSpellLoads)
			if best then
				knownAuras[auraID] = {
					auraID = auraID,
					id = auraDef.id,
					spellID = best.spellID,
					name = best.name or auraDef.name,
					icon = best.iconID or auraDef.icon,
					rank = best.rank,
				}
			end
		end

		-- Righteous Fury (25780)
		local rfDef = Catalog.RIGHTEOUS_FURY
		local rfBest = findBestKnownRank(rfDef.ranks, self.pendingSpellLoads)
		if rfBest then
			righteousFury = {
				known = true,
				spellID = rfBest.spellID,
				name = rfBest.name or rfDef.name,
				icon = rfBest.iconID or rfDef.icon,
				allSpellIDs = { [rfBest.spellID] = true },
			}
		end

		-- Known Seals from catalog
		local sealsByName = {}
		local function registerKnownSeal(id, name, shortName, spellID, icon, allIDs)
			local existing = sealsByName[name]
			if existing then
				existing.allSpellIDs[spellID] = true
				if allIDs then
					for sid in pairs(allIDs) do
						existing.allSpellIDs[sid] = true
					end
				end
				return
			end
			local idSet = { [spellID] = true }
			if allIDs then
				for sid in pairs(allIDs) do
					idSet[sid] = true
				end
			end
			local entry = {
				id = id,
				name = name,
				shortName = shortName or name:gsub("^Seal of the ", "So"):gsub("^Seal of ", "So"):sub(1, 5),
				spellID = spellID,
				icon = icon or 132325,
				allSpellIDs = idSet,
			}
			knownSeals[id] = entry
			sealsByName[name] = entry
			table_insert(knownSealsList, entry)
		end

		for _, sealDef in ipairs(Catalog.PALADIN_SEALS) do
			local best = findBestKnownRank(sealDef.ranks, self.pendingSpellLoads)
			if best then
				local allIDs = {}
				for _, sid in ipairs(sealDef.ranks) do
					allIDs[sid] = true
				end
				registerKnownSeal(
					sealDef.id,
					best.name or sealDef.name,
					sealDef.shortName,
					best.spellID,
					best.iconID or sealDef.icon,
					allIDs
				)
			end
		end

		-- Dynamic C_SpellBook scan for any Forever-exclusive Seal spells / extra ranks (e.g. Seal of Fury Rank 1)
		if _G.C_SpellBook and _G.C_SpellBook.GetNumSpellBookSkillLines and _G.C_SpellBook.GetSpellBookSkillLineInfo and _G.C_SpellBook.GetSpellBookItemInfo then
			local bank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player) or 0
			local numLines = Compat.SafeCall(_G.C_SpellBook.GetNumSpellBookSkillLines, 0)
			for lineIdx = 1, numLines do
				local lineInfo = Compat.SafeCall(_G.C_SpellBook.GetSpellBookSkillLineInfo, nil, lineIdx)
				if type(lineInfo) == "table" and lineInfo.itemIndexOffset and lineInfo.numSpellBookItems then
					local offset = lineInfo.itemIndexOffset
					for slot = offset + 1, offset + lineInfo.numSpellBookItems do
						local itemInfo = Compat.SafeCall(_G.C_SpellBook.GetSpellBookItemInfo, nil, slot, bank)
						if type(itemInfo) == "table" and itemInfo.spellID and itemInfo.spellID > 0 then
							local sInfo = Compat.GetSpellInfo(itemInfo.spellID)
							if sInfo and sInfo.name and sInfo.name:find("^Seal of ") then
								local catDef = Catalog.SEAL_BY_NAME[sInfo.name]
								local sealID = (catDef and catDef.id) or ("SEAL_" .. sInfo.name:upper():gsub("[^A-Z0-9]+", "_"))
								registerKnownSeal(
									sealID,
									sInfo.name,
									catDef and catDef.shortName or nil,
									itemInfo.spellID,
									sInfo.iconID or (catDef and catDef.icon),
									nil
								)
							end
						end
					end
				end
			end
		end
	end

	-- Shaman Totems
	local knownTotems = {}
	if classToken == "SHAMAN" then
		for _, element in ipairs(Catalog.TOTEM_ELEMENTS) do
			knownTotems[element] = {}
			for _, totemDef in ipairs(Catalog.SHAMAN_TOTEMS[element]) do
				local best = findBestKnownRank(totemDef.ranks, self.pendingSpellLoads)
				if best then
					knownTotems[element][totemDef.id] = {
						id = totemDef.id,
						element = element,
						spellID = best.spellID,
						name = best.name or totemDef.name,
						shortName = totemDef.shortName,
						icon = best.iconID or totemDef.icon,
					}
				end
			end
		end
	end

	-- All-Class Personal Self-Buffs (Inner Fire, Shadowform, Shaman Imbues & Shields, Mage/Warlock Armors, Soul Link, Druid Self-Thorns/Omen, Hunter Aspects, etc.)
	local knownPersonal = {}
	local personalSlots = Catalog.PERSONAL_SLOTS and Catalog.PERSONAL_SLOTS[classToken] or nil
	if personalSlots then
		local spellBookItems = nil
		local function getSpellBookItems()
			if spellBookItems then
				return spellBookItems
			end
			spellBookItems = {}
			if _G.C_SpellBook and _G.C_SpellBook.GetNumSpellBookSkillLines and _G.C_SpellBook.GetSpellBookSkillLineInfo and _G.C_SpellBook.GetSpellBookItemInfo then
				local bank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player) or 0
				local numLines = Compat.SafeCall(_G.C_SpellBook.GetNumSpellBookSkillLines, 0)
				for lineIdx = 1, numLines do
					local lineInfo = Compat.SafeCall(_G.C_SpellBook.GetSpellBookSkillLineInfo, nil, lineIdx)
					if type(lineInfo) == "table" and lineInfo.itemIndexOffset and lineInfo.numSpellBookItems then
						local offset = lineInfo.itemIndexOffset
						for slot = offset + 1, offset + lineInfo.numSpellBookItems do
							local itemInfo = Compat.SafeCall(_G.C_SpellBook.GetSpellBookItemInfo, nil, slot, bank)
							if type(itemInfo) == "table" and itemInfo.spellID and itemInfo.spellID > 0 then
								local sInfo = Compat.GetSpellInfo(itemInfo.spellID)
								if sInfo and sInfo.name then
									table_insert(spellBookItems, {
										spellID = itemInfo.spellID,
										name = sInfo.name,
										iconID = sInfo.iconID,
									})
								end
							end
						end
					end
				end
			end
			return spellBookItems
		end

		for _, slotDef in ipairs(personalSlots) do
			local slotBucket = {
				slotID = slotDef.slotID,
				byID = {},
				byName = {},
				list = {},
			}
			local function registerPersonalOpt(optID, name, shortName, spellID, icon, duration, allIDs, dedupeFamilyID)
				local existing = slotBucket.byName[name]
				if existing then
					existing.allSpellIDs[spellID] = true
					if allIDs then
						for sid in pairs(allIDs) do
							existing.allSpellIDs[sid] = true
						end
					end
					return
				end
				local idSet = { [spellID] = true }
				if allIDs then
					for sid in pairs(allIDs) do
						idSet[sid] = true
					end
				end
				local entry = {
					id = optID,
					name = name,
					shortName = shortName or name:sub(1, 6),
					spellID = spellID,
					icon = icon or 134400,
					duration = duration or 1800,
					dedupeFamilyID = dedupeFamilyID,
					allSpellIDs = idSet,
				}
				slotBucket.byID[optID] = entry
				slotBucket.byName[name] = entry
				table_insert(slotBucket.list, entry)
			end

			for _, optDef in ipairs(slotDef.options or {}) do
				local best = findBestKnownRank(optDef.ranks, self.pendingSpellLoads)
				if best then
					local allIDs = {}
					for _, sid in ipairs(optDef.ranks or {}) do
						allIDs[sid] = true
					end
					registerPersonalOpt(
						optDef.id,
						best.name or optDef.name,
						optDef.shortName,
						best.spellID,
						best.iconID or optDef.icon,
						optDef.duration,
						allIDs,
						optDef.dedupeFamilyID
					)
				end
			end

			if slotDef.dynamicPattern then
				for _, sb in ipairs(getSpellBookItems()) do
					if sb.name:find(slotDef.dynamicPattern) and not sb.name:find("^Improved ") then
						local catOpt = Catalog.PERSONAL_NAME_TO_OPT[sb.name]
						local optID = (catOpt and catOpt.id) or ("DYN_" .. sb.name:upper():gsub("[^A-Z0-9]+", "_"))
						registerPersonalOpt(
							optID,
							sb.name,
							catOpt and catOpt.shortName or nil,
							sb.spellID,
							sb.iconID or (catOpt and catOpt.icon),
							(catOpt and catOpt.duration) or (slotDef.isPermanentToggle and 0 or 1800),
							nil,
							catOpt and catOpt.dedupeFamilyID or nil
						)
					end
				end
			end

			knownPersonal[slotDef.slotID] = slotBucket
		end
	end

	self:ScanTracking()

	if Compat.InCombat() and prev and prev.class == classToken then
		if next(knownBuffs) == nil and prev.buffs then
			knownBuffs = prev.buffs
		end
		if next(knownAuras) == nil and prev.auras then
			knownAuras = prev.auras
		end
		if not righteousFury and prev.righteousFury then
			righteousFury = prev.righteousFury
		end
		if #knownSealsList == 0 and prev.sealsList and #prev.sealsList > 0 then
			knownSeals = prev.seals or knownSeals
			knownSealsList = prev.sealsList
		end
		if next(knownPersonal) == nil and prev.personal then
			knownPersonal = prev.personal
		end
	end

	local vec = {
		name = playerName,
		guid = guid,
		class = classToken,
		source = "LBB",
		buffs = knownBuffs,
		auras = knownAuras,
		righteousFury = righteousFury,
		seals = knownSeals,
		sealsList = knownSealsList,
		personal = knownPersonal,
		totems = knownTotems,
		reagents = reagents,
		symbols = reagents[21177] or 0,
		updatedAt = Compat.GetTime(),
	}

	self.playerVector = vec
	self.peers[playerName] = vec
	return vec
end

function Capabilities:OnSpellDataLoaded(spellID, success)
	if not spellID or not self.pendingSpellLoads[spellID] then
		return false
	end
	self.pendingSpellLoads[spellID] = nil
	if not success or not self.playerVector then
		return false
	end
	local info = LBB.Compat.GetSpellInfo(spellID)
	if not info then
		return false
	end
	local updated = false
	for _, b in pairs(self.playerVector.buffs) do
		if b.bestSingleID == spellID then
			b.bestSingleName = info.name
			b.icon = info.iconID or b.icon
			updated = true
		end
		if b.bestGroupID == spellID then
			b.bestGroupName = info.name
			updated = true
		end
	end
	for _, a in pairs(self.playerVector.auras or {}) do
		if a.spellID == spellID then
			a.name = info.name
			a.icon = info.iconID or a.icon
			updated = true
		end
	end
	if self.playerVector.righteousFury and self.playerVector.righteousFury.spellID == spellID then
		self.playerVector.righteousFury.name = info.name
		self.playerVector.righteousFury.icon = info.iconID or self.playerVector.righteousFury.icon
		updated = true
	end
	for _, s in pairs(self.playerVector.seals or {}) do
		if s.spellID == spellID then
			s.name = info.name
			s.icon = info.iconID or s.icon
			updated = true
		end
	end
	for _, elementMap in pairs(self.playerVector.totems or {}) do
		for _, t in pairs(elementMap) do
			if t.spellID == spellID then
				t.name = info.name
				t.icon = info.iconID or t.icon
				updated = true
			end
		end
	end
	for _, slotBucket in pairs(self.playerVector.personal or {}) do
		for _, p in ipairs(slotBucket.list or {}) do
			if p.spellID == spellID then
				p.name = info.name
				p.icon = info.iconID or p.icon
				updated = true
			end
		end
	end
	return updated
end

function Capabilities:GetPlayerVector()
	if not self.playerVector then
		return self:ScanPlayer()
	end
	return self.playerVector
end

function Capabilities:SetPeerVector(name, vec)
	if not name or not vec then
		return
	end
	vec.name = name
	self.peers[name] = vec
end

function Capabilities:GetPeerVector(name)
	return self.peers[name]
end

function Capabilities:GetAllVectors()
	return self.peers
end

function Capabilities:RemoveMissingPeers(activeNames)
	local playerName = self.playerVector and self.playerVector.name
	for name in pairs(self.peers) do
		if name ~= playerName and not activeNames[name] then
			self.peers[name] = nil
		end
	end
end

-- Compact CAP serialization for LBB1 protocol
-- Format: class~famID:rank:talent:hasGroup:score,famID2:...~aura1,aura2~totem1,totem2~symCount
function Capabilities:SerializeVector(vec)
	vec = vec or self:GetPlayerVector()
	if not vec then
		return ""
	end
	local buffParts = {}
	local famKeys = {}
	for famID in pairs(vec.buffs or {}) do
		table_insert(famKeys, famID)
	end
	table_sort(famKeys)
	for _, famID in ipairs(famKeys) do
		local b = vec.buffs[famID]
		if b and b.known then
			table_insert(buffParts, string.format("%s:%d:%d:%d:%d",
				famID,
				b.bestSingleRank or 1,
				b.talentRank or 0,
				b.hasGroup and 1 or 0,
				math_floor(b.priorityScore or 10)
			))
		end
	end

	local auraParts = {}
	for auraID = 1, 8 do
		if vec.auras and vec.auras[auraID] then
			table_insert(auraParts, tostring(auraID))
		end
	end

	local totemParts = {}
	for _, element in ipairs(LBB.Catalog.TOTEM_ELEMENTS) do
		local elMap = vec.totems and vec.totems[element]
		if elMap then
			local tKeys = {}
			for tid in pairs(elMap) do
				table_insert(tKeys, tid)
			end
			table_sort(tKeys)
			for _, tid in ipairs(tKeys) do
				table_insert(totemParts, tid)
			end
		end
	end

	return table_concat({
		vec.class or "UNKNOWN",
		table_concat(buffParts, ","),
		table_concat(auraParts, ","),
		table_concat(totemParts, ","),
		tostring(vec.symbols or 0),
	}, "~")
end

function Capabilities:DeserializeVector(name, serialized)
	if type(serialized) ~= "string" or serialized == "" then
		return nil
	end
	local parts = {}
	local startIdx = 1
	while true do
		local pos = serialized:find("~", startIdx, true)
		if not pos then
			table_insert(parts, serialized:sub(startIdx))
			break
		end
		table_insert(parts, serialized:sub(startIdx, pos - 1))
		startIdx = pos + 1
	end

	local classToken = parts[1] or "UNKNOWN"
	local buffsStr = parts[2] or ""
	local aurasStr = parts[3] or ""
	local totemsStr = parts[4] or ""
	local symCount = tonumber(parts[5]) or 0

	local Catalog = LBB.Catalog
	local buffs = {}
	if buffsStr ~= "" then
		for token in buffsStr:gmatch("[^,]+") do
			local famID, r, t, g, score = token:match("^([^:]+):(%d+):(%d+):(%d+):(%d+)$")
			if famID and Catalog.GetFamily(famID) then
				local fam = Catalog.GetFamily(famID)
				buffs[famID] = {
					familyID = famID,
					known = true,
					bestSingleRank = tonumber(r) or 1,
					bestSingleName = fam.name,
					bestGroupName = fam.groupName,
					talentRank = tonumber(t) or 0,
					hasGroup = (tonumber(g) == 1),
					priorityScore = tonumber(score) or 10,
					icon = fam.icon,
				}
			end
		end
	end

	local auras = {}
	if aurasStr ~= "" then
		for aStr in aurasStr:gmatch("[^,]+") do
			local aid = tonumber(aStr)
			local def = aid and Catalog.PALADIN_AURAS[aid]
			if def then
				auras[aid] = {
					auraID = aid,
					id = def.id,
					name = def.name,
					icon = def.icon,
					rank = 1,
				}
			end
		end
	end

	local totems = {}
	if classToken == "SHAMAN" then
		for _, el in ipairs(Catalog.TOTEM_ELEMENTS) do
			totems[el] = {}
		end
		if totemsStr ~= "" then
			for tid in totemsStr:gmatch("[^,]+") do
				local def = Catalog.TOTEM_BY_ID[tid]
				if def then
					totems[def.element][tid] = {
						id = tid,
						element = def.element,
						name = def.name,
						shortName = def.shortName,
						icon = def.icon,
					}
				end
			end
		end
	end

	return {
		name = name,
		guid = name,
		class = classToken,
		source = "LBB",
		buffs = buffs,
		auras = auras,
		totems = totems,
		symbols = symCount,
		updatedAt = LBB.Compat.GetTime(),
	}
end
