local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Negotiator = {}
LBB.Negotiator = Negotiator

local pairs = pairs
local ipairs = ipairs
local math_floor = math.floor
local table_insert = table.insert
local table_sort = table.sort

-- Deterministic caster comparator:
-- 1) Higher priorityScore for `familyID`
-- 2) Higher talentRank for `familyID`
-- 3) Has group spell
-- 4) Deterministic alphabetical name / GUID tie-breaker
local function sortCastersForFamily(casters, familyID)
	local copy = {}
	for i = 1, #casters do
		copy[i] = casters[i]
	end
	table_sort(copy, function(a, b)
		local ab = a.vec and a.vec.buffs and a.vec.buffs[familyID]
		local bb = b.vec and b.vec.buffs and b.vec.buffs[familyID]
		local aScore = ab and ab.priorityScore or -1
		local bScore = bb and bb.priorityScore or -1
		if aScore ~= bScore then
			return aScore > bScore
		end
		local aTal = ab and ab.talentRank or 0
		local bTal = bb and bb.talentRank or 0
		if aTal ~= bTal then
			return aTal > bTal
		end
		local aGrp = (ab and ab.hasGroup) and 1 or 0
		local bGrp = (bb and bb.hasGroup) and 1 or 0
		if aGrp ~= bGrp then
			return aGrp > bGrp
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return (a.guid or "") < (b.guid or "")
	end)
	return copy
end

-- Partition an ordered list of subgroups evenly across `numCasters` slots.
-- Example: 8 subgroups across 3 casters -> {1,2,3}, {4,5,6}, {7,8}
function Negotiator.PartitionSubgroups(subgroups, numCasters)
	local buckets = {}
	if numCasters <= 0 or #subgroups == 0 then
		return buckets
	end
	local n = #subgroups
	local base = math_floor(n / numCasters)
	local rem = n % numCasters
	local idx = 1
	for c = 1, numCasters do
		local count = base + (c <= rem and 1 or 0)
		local slice = {}
		for _ = 1, count do
			if idx <= n then
				table_insert(slice, subgroups[idx])
				idx = idx + 1
			end
		end
		buckets[c] = slice
	end
	return buckets
end

local function collectActiveSubgroups(roster, filterFn)
	local present = {}
	for _, m in ipairs(roster) do
		local sg = m.subgroup or 1
		if not filterFn or filterFn(m) then
			present[sg] = true
		end
	end
	local list = {}
	for sg = 1, 8 do
		if present[sg] then
			table_insert(list, sg)
		end
	end
	return list
end

local function collectActiveClasses(roster)
	local present = {}
	for _, m in ipairs(roster) do
		if m.class then
			present[m.class] = true
		end
	end
	local list = {}
	for _, cls in ipairs(LBB.Catalog.CLASS_ORDER) do
		if present[cls] then
			table_insert(list, cls)
		end
	end
	return list
end

local function collectCastersByClass(roster, capabilitiesByCaster, classToken)
	local list = {}
	for _, m in ipairs(roster) do
		if m.class == classToken then
			local vec = capabilitiesByCaster[m.name]
			if vec then
				table_insert(list, {
					name = m.name,
					guid = m.guid or vec.guid or m.name,
					subgroup = m.subgroup or 1,
					role = m.role or "NONE",
					vec = vec,
				})
			end
		end
	end
	table_sort(list, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return (a.guid or "") < (b.guid or "")
	end)
	return list
end

local function filterKnowsFamily(casters, familyID)
	local out = {}
	for _, c in ipairs(casters) do
		if c.vec and c.vec.buffs and c.vec.buffs[familyID] and c.vec.buffs[familyID].known then
			table_insert(out, c)
		end
	end
	return out
end

local function assignGroupIfUnlocked(assignments, familyID, subgroup, casterName, preserveExisting)
	local existing = assignments:GetGroupBuff(familyID, subgroup)
	if existing and (existing.locked or preserveExisting) then
		return false
	end
	assignments:SetGroupBuff(familyID, subgroup, casterName, false)
	return true
end

local function assignTargetIfUnlocked(assignments, familyID, targetName, casterName, preserveExisting)
	local existing = assignments:GetTargetBuff(familyID, targetName)
	if existing and (existing.locked or preserveExisting) then
		return false
	end
	assignments:SetTargetBuff(familyID, targetName, casterName, false)
	return true
end

-- 1. Priests:
--    1 Priest  -> covers all known buffs across all active subgroups
--    2 Priests -> split by buff family (highest Imp. Fort takes Fort; Spirit/ShadowProt go to the other Priest if known)
--    3+ Priests -> partition raid subgroups evenly per buff family
local function solvePriests(roster, capabilitiesByCaster, assignments, preserveExisting)
	local priests = collectCastersByClass(roster, capabilitiesByCaster, "PRIEST")
	if #priests == 0 then
		return
	end

	local allSubgroups = collectActiveSubgroups(roster)
	local manaSubgroups = collectActiveSubgroups(roster, function(m)
		return LBB.Catalog.ClassUsesMana(m.class)
	end)

	local fortCasters = sortCastersForFamily(filterKnowsFamily(priests, "FORTITUDE"), "FORTITUDE")
	local spiritCasters = sortCastersForFamily(filterKnowsFamily(priests, "SPIRIT"), "SPIRIT")
	local sprotCasters = sortCastersForFamily(filterKnowsFamily(priests, "SHADOW_PROT"), "SHADOW_PROT")

	if #priests == 1 then
		local p = priests[1]
		if #fortCasters == 1 then
			for _, sg in ipairs(allSubgroups) do
				assignGroupIfUnlocked(assignments, "FORTITUDE", sg, p.name, preserveExisting)
			end
		end
		if #spiritCasters == 1 then
			for _, sg in ipairs(manaSubgroups) do
				assignGroupIfUnlocked(assignments, "SPIRIT", sg, p.name, preserveExisting)
			end
		end
		if #sprotCasters == 1 then
			for _, sg in ipairs(allSubgroups) do
				assignGroupIfUnlocked(assignments, "SHADOW_PROT", sg, p.name, preserveExisting)
			end
		end
		return
	end

	if #priests == 2 then
		-- Family-level split
		local fortOwner = fortCasters[1]
		if fortOwner then
			for _, sg in ipairs(allSubgroups) do
				assignGroupIfUnlocked(assignments, "FORTITUDE", sg, fortOwner.name, preserveExisting)
			end
		end

		-- Prefer a Priest who knows Divine Spirit and is NOT the Fortitude owner
		local spiritOwner = nil
		for _, c in ipairs(spiritCasters) do
			if not fortOwner or c.name ~= fortOwner.name then
				spiritOwner = c
				break
			end
		end
		if not spiritOwner then
			spiritOwner = spiritCasters[1]
		end
		if spiritOwner then
			for _, sg in ipairs(manaSubgroups) do
				assignGroupIfUnlocked(assignments, "SPIRIT", sg, spiritOwner.name, preserveExisting)
			end
		end

		-- Assign Shadow Protection to the non-Fortitude Priest if possible
		local sprotOwner = nil
		for _, c in ipairs(sprotCasters) do
			if not fortOwner or c.name ~= fortOwner.name then
				sprotOwner = c
				break
			end
		end
		if not sprotOwner then
			sprotOwner = sprotCasters[1]
		end
		if sprotOwner then
			for _, sg in ipairs(allSubgroups) do
				assignGroupIfUnlocked(assignments, "SHADOW_PROT", sg, sprotOwner.name, preserveExisting)
			end
		end
		return
	end

	-- 3+ Priests: partition raid subgroups evenly so reagents & mana are shared fairly
	if #fortCasters > 0 then
		local buckets = Negotiator.PartitionSubgroups(allSubgroups, #fortCasters)
		for i, caster in ipairs(fortCasters) do
			for _, sg in ipairs(buckets[i] or {}) do
				assignGroupIfUnlocked(assignments, "FORTITUDE", sg, caster.name, preserveExisting)
			end
		end
	end

	if #spiritCasters > 0 then
		local buckets = Negotiator.PartitionSubgroups(manaSubgroups, #spiritCasters)
		for i, caster in ipairs(spiritCasters) do
			for _, sg in ipairs(buckets[i] or {}) do
				assignGroupIfUnlocked(assignments, "SPIRIT", sg, caster.name, preserveExisting)
			end
		end
	end

	if #sprotCasters > 0 then
		-- Rotate caster order by 1 so the Priest with the smallest Fort slice takes the first Shadow Prot slice
		local rotated = {}
		local count = #sprotCasters
		for i = 1, count do
			local idx = ((i) % count) + 1
			rotated[i] = sprotCasters[idx]
		end
		local buckets = Negotiator.PartitionSubgroups(allSubgroups, #rotated)
		for i, caster in ipairs(rotated) do
			for _, sg in ipairs(buckets[i] or {}) do
				assignGroupIfUnlocked(assignments, "SHADOW_PROT", sg, caster.name, preserveExisting)
			end
		end
	end
end

-- 2. Druids: split Mark/Gift of the Wild evenly by subgroup + assign Thorns to tanks/melee
local function solveDruids(roster, capabilitiesByCaster, assignments, preserveExisting)
	local druids = collectCastersByClass(roster, capabilitiesByCaster, "DRUID")
	if #druids == 0 then
		return
	end

	local allSubgroups = collectActiveSubgroups(roster)
	local motwCasters = sortCastersForFamily(filterKnowsFamily(druids, "MOTW"), "MOTW")
	if #motwCasters > 0 then
		local buckets = Negotiator.PartitionSubgroups(allSubgroups, #motwCasters)
		for i, caster in ipairs(motwCasters) do
			for _, sg in ipairs(buckets[i] or {}) do
				assignGroupIfUnlocked(assignments, "MOTW", sg, caster.name, preserveExisting)
			end
		end
	end

	local thornsCasters = sortCastersForFamily(filterKnowsFamily(druids, "THORNS"), "THORNS")
	if #thornsCasters > 0 then
		-- Prioritize explicit TANKS first, then Warriors / Druid tanks
		local targets = {}
		for _, m in ipairs(roster) do
			if m.role == "TANK" then
				table_insert(targets, m)
			end
		end
		if #targets == 0 then
			for _, m in ipairs(roster) do
				if m.class == "WARRIOR" or (m.class == "PALADIN" and m.role == "TANK") then
					table_insert(targets, m)
				end
			end
		end
		if #targets == 0 and #roster == 1 then
			table_insert(targets, roster[1])
		end
		for idx, target in ipairs(targets) do
			local caster = thornsCasters[((idx - 1) % #thornsCasters) + 1]
			assignTargetIfUnlocked(assignments, "THORNS", target.name, caster.name, preserveExisting)
		end
	end
end

-- 3. Mages: split Arcane Intellect/Brilliance evenly across mana-containing subgroups
local function solveMages(roster, capabilitiesByCaster, assignments, preserveExisting)
	local mages = collectCastersByClass(roster, capabilitiesByCaster, "MAGE")
	if #mages == 0 then
		return
	end
	local manaSubgroups = collectActiveSubgroups(roster, function(m)
		return LBB.Catalog.ClassUsesMana(m.class)
	end)
	local aiCasters = sortCastersForFamily(filterKnowsFamily(mages, "INTELLECT"), "INTELLECT")
	if #aiCasters > 0 then
		local buckets = Negotiator.PartitionSubgroups(manaSubgroups, #aiCasters)
		for i, caster in ipairs(aiCasters) do
			for _, sg in ipairs(buckets[i] or {}) do
				assignGroupIfUnlocked(assignments, "INTELLECT", sg, caster.name, preserveExisting)
			end
		end
	end
end

-- 4. Paladins: talent-prioritized non-overlapping Blessings + party Auras (unless yielded to PallyPower)
local function solvePaladins(roster, capabilitiesByCaster, assignments, options)
	if options and options.pallyPowerYield then
		return
	end
	local paladins = collectCastersByClass(roster, capabilitiesByCaster, "PALADIN")
	if #paladins == 0 then
		return
	end

	local Catalog = LBB.Catalog
	local activeClasses = collectActiveClasses(roster)

	local preserveExisting = options and options.preserveExisting and true or false
	-- For each class present in raid/party, assign distinct blessings across Paladins by talent priority
	for _, cls in ipairs(activeClasses) do
		local priorities = Catalog.PALADIN_CLASS_PRIORITIES[cls] or { "BOK", "BOW", "BOM", "BOSALV", "BOL", "BOSANC" }
		local usedBlessings = {}
		local assignedPaladins = {}

		-- First respect any locked (or preserved restored) assignments on this class
		for _, p in ipairs(paladins) do
			local existing = assignments:GetClassBuff(p.name, cls)
			if existing and (existing.locked or preserveExisting) then
				assignedPaladins[p.name] = true
				if existing.familyID then
					usedBlessings[existing.familyID] = true
				end
			end
		end

		-- Assign remaining blessings in priority order, picking the highest-talent Paladin for each blessing
		for _, famID in ipairs(priorities) do
			if not usedBlessings[famID] then
				local candidates = {}
				for _, p in ipairs(paladins) do
					if not assignedPaladins[p.name] and p.vec and p.vec.buffs and p.vec.buffs[famID] and p.vec.buffs[famID].known then
						table_insert(candidates, p)
					end
				end
				if #candidates > 0 then
					local ordered = sortCastersForFamily(candidates, famID)
					local winner = ordered[1]
					assignments:SetClassBuff(winner.name, cls, famID, false)
					usedBlessings[famID] = true
					assignedPaladins[winner.name] = true
				end
			end
		end
	end

	-- Paladin Auras per party (non-overlapping)
	local paladinsBySubgroup = {}
	for _, p in ipairs(paladins) do
		paladinsBySubgroup[p.subgroup] = paladinsBySubgroup[p.subgroup] or {}
		table_insert(paladinsBySubgroup[p.subgroup], p)
	end
	local auraPriority = { 1, 3, 2, 7, 4, 5, 6 } -- Devo, Conc, Ret, Sanctity, Resistance auras
	for _, groupPaladins in pairs(paladinsBySubgroup) do
		local usedAuras = {}
		for _, p in ipairs(groupPaladins) do
			local existing = assignments:GetPaladinAura(p.name)
			if existing and (existing.locked or preserveExisting) then
				if existing.auraID and existing.auraID > 0 then
					usedAuras[existing.auraID] = true
				end
			end
		end
		for _, p in ipairs(groupPaladins) do
			local existing = assignments:GetPaladinAura(p.name)
			if not (existing and (existing.locked or preserveExisting)) then
				local chosen = nil
				for _, aid in ipairs(auraPriority) do
					if not usedAuras[aid] and p.vec and p.vec.auras and p.vec.auras[aid] then
						chosen = aid
						break
					end
				end
				if chosen then
					assignments:SetPaladinAura(p.name, chosen, false)
					usedAuras[chosen] = true
				end
			end
		end
	end
end

-- 5. Shamans: non-overlapping 4-totem sets per party (Melee vs Caster party role)
local function determinePartyRole(roster, subgroup)
	local Catalog = LBB.Catalog
	local meleeCount, casterCount = 0, 0
	for _, m in ipairs(roster) do
		if (m.subgroup or 1) == subgroup then
			local info = Catalog.CLASS_INFO[m.class]
			if info then
				if info.isMelee and not info.isCaster then
					meleeCount = meleeCount + 2
				elseif info.isCaster and not info.isMelee then
					casterCount = casterCount + 2
				elseif m.class == "WARRIOR" or m.class == "ROGUE" or m.class == "HUNTER" then
					meleeCount = meleeCount + 2
				else
					casterCount = casterCount + 1
				end
			end
		end
	end
	return (meleeCount >= casterCount) and "MELEE" or "CASTER"
end

local function solveShamans(roster, capabilitiesByCaster, assignments, preserveExisting)
	local shamans = collectCastersByClass(roster, capabilitiesByCaster, "SHAMAN")
	if #shamans == 0 then
		return
	end
	local Catalog = LBB.Catalog
	local bySubgroup = {}
	for _, s in ipairs(shamans) do
		bySubgroup[s.subgroup] = bySubgroup[s.subgroup] or {}
		table_insert(bySubgroup[s.subgroup], s)
	end

	for sg, partyShamans in pairs(bySubgroup) do
		local partyRole = determinePartyRole(roster, sg)
		local preset = Catalog.SHAMAN_ROLE_PRESETS[partyRole] or Catalog.SHAMAN_ROLE_PRESETS.MELEE

		for _, element in ipairs(Catalog.TOTEM_ELEMENTS) do
			local usedTotems = {}
			-- Preserve locked (or restored) totems in this party/element first
			for _, s in ipairs(partyShamans) do
				local existing = assignments:GetShamanTotems(sg, s.name)
				local keep = existing and ((existing.locked and existing.locked[element]) or (preserveExisting and existing[element] ~= nil))
				if keep and existing[element] then
					usedTotems[existing[element]] = true
				end
			end

			for _, s in ipairs(partyShamans) do
				local existing = assignments:GetShamanTotems(sg, s.name)
				local keep = existing and ((existing.locked and existing.locked[element]) or (preserveExisting and existing[element] ~= nil))
				if not keep then
					local knownEl = s.vec and s.vec.totems and s.vec.totems[element]
					local chosen = nil
					if knownEl then
						for _, tid in ipairs(preset[element] or {}) do
							if knownEl[tid] and not usedTotems[tid] then
								chosen = tid
								break
							end
						end
					end
					assignments:SetShamanTotem(sg, s.name, element, chosen, false)
					if chosen then
						usedTotems[chosen] = true
					end
				end
			end
		end
	end
end

-- 6. Warriors: highest-talent Battle Shout per party
local function solveWarriors(roster, capabilitiesByCaster, assignments, preserveExisting)
	local warriors = collectCastersByClass(roster, capabilitiesByCaster, "WARRIOR")
	if #warriors == 0 then
		return
	end
	local bySubgroup = {}
	for _, w in ipairs(warriors) do
		if w.vec and w.vec.buffs and w.vec.buffs.BATTLE_SHOUT and w.vec.buffs.BATTLE_SHOUT.known then
			bySubgroup[w.subgroup] = bySubgroup[w.subgroup] or {}
			table_insert(bySubgroup[w.subgroup], w)
		end
	end
	for sg, partyWarriors in pairs(bySubgroup) do
		local ordered = sortCastersForFamily(partyWarriors, "BATTLE_SHOUT")
		if ordered[1] then
			assignGroupIfUnlocked(assignments, "BATTLE_SHOUT", sg, ordered[1].name, preserveExisting)
		end
	end
end

-- 7. Warlocks: Blood Pact per party + Soulstone on primary healer/tank
local function solveWarlocks(roster, capabilitiesByCaster, assignments, preserveExisting)
	local warlocks = collectCastersByClass(roster, capabilitiesByCaster, "WARLOCK")
	if #warlocks == 0 then
		return
	end

	-- Blood Pact per party
	local bySubgroup = {}
	for _, wl in ipairs(warlocks) do
		if wl.vec and wl.vec.buffs and wl.vec.buffs.BLOOD_PACT and wl.vec.buffs.BLOOD_PACT.known then
			bySubgroup[wl.subgroup] = bySubgroup[wl.subgroup] or {}
			table_insert(bySubgroup[wl.subgroup], wl)
		end
	end
	for sg, partyLocks in pairs(bySubgroup) do
		local ordered = sortCastersForFamily(partyLocks, "BLOOD_PACT")
		if ordered[1] then
			assignGroupIfUnlocked(assignments, "BLOOD_PACT", sg, ordered[1].name, preserveExisting)
		end
	end

	-- Soulstone on healers first, then tanks
	local ssCasters = sortCastersForFamily(filterKnowsFamily(warlocks, "SOULSTONE"), "SOULSTONE")
	if #ssCasters > 0 then
		local targets = {}
		for _, m in ipairs(roster) do
			if m.role == "HEALER" then
				table_insert(targets, m)
			end
		end
		for _, m in ipairs(roster) do
			if m.role == "TANK" then
				table_insert(targets, m)
			end
		end
		if #targets == 0 then
			for _, m in ipairs(roster) do
				if m.class == "PRIEST" or m.class == "PALADIN" or m.class == "DRUID" or m.class == "SHAMAN" then
					table_insert(targets, m)
				end
			end
		end
		if #targets == 0 and #roster == 1 then
			table_insert(targets, roster[1])
		end
		for i = 1, #ssCasters do
			local target = targets[i]
			if target then
				assignTargetIfUnlocked(assignments, "SOULSTONE", target.name, ssCasters[i].name, preserveExisting)
			end
		end
	end
end

-- Main deterministic consensus entrypoint
function Negotiator.Solve(roster, capabilitiesByCaster, assignments, options)
	roster = roster or {}
	capabilitiesByCaster = capabilitiesByCaster or {}
	options = options or {}
	local preserveExisting = options.preserveExisting and true or false

	if not preserveExisting then
		-- Clear unlocked assignments while strictly preserving all locked overrides
		-- (and preserving Paladin assignments when yielding control to PallyPower)
		assignments:ClearAll(true, options.pallyPowerYield and true or false)
	end

	solvePriests(roster, capabilitiesByCaster, assignments, preserveExisting)
	solveDruids(roster, capabilitiesByCaster, assignments, preserveExisting)
	solveMages(roster, capabilitiesByCaster, assignments, preserveExisting)
	solvePaladins(roster, capabilitiesByCaster, assignments, options)
	solveShamans(roster, capabilitiesByCaster, assignments, preserveExisting)
	solveWarriors(roster, capabilitiesByCaster, assignments, preserveExisting)
	solveWarlocks(roster, capabilitiesByCaster, assignments, preserveExisting)

	return assignments
end
