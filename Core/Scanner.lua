local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Scanner = {}
LBB.Scanner = Scanner

local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_min = math.min
local math_huge = math.huge
local table_insert = table.insert
local table_sort = table.sort

Scanner.MAX_AURAS = 40
Scanner.DEFAULT_REFRESH_THRESHOLD = 180 -- 3 minutes

-- Pre-combat cached aura state per unitKey (guid or unit token)
-- auraCache[unitKey] = { families = { [famID] = { expirationTime, duration, spellId, source } }, consumables = { ... }, wasDead = bool }
Scanner.auraCache = {}

function Scanner:Reset()
	self.auraCache = {}
end

local function unitCacheKey(unit, unitInfo)
	if unitInfo and unitInfo.guid then
		return unitInfo.guid
	end
	local guid = LBB.Compat.UnitGUID(unit)
	return guid or unit
end

local function matchConsumable(aura)
	local Catalog = LBB.Catalog
	for _, cid in ipairs(Catalog.CONSUMABLE_ORDER) do
		local def = Catalog.CONSUMABLES[cid]
		if def and not def.usesWeaponEnchantAPI then
			if aura.spellId and def.spellIDs and def.spellIDs[aura.spellId] then
				return cid
			end
			if aura.name and def.patterns then
				for _, pat in ipairs(def.patterns) do
					if aura.name:find(pat) then
						return cid
					end
				end
			end
		end
	end
	return nil
end

local function matchTotemOrAura(aura)
	local Catalog = LBB.Catalog
	if aura.spellId and Catalog.SPELL_ID_TO_FAMILY[aura.spellId] then
		return Catalog.SPELL_ID_TO_FAMILY[aura.spellId], nil, nil, nil, nil
	end
	if aura.name and Catalog.AURA_NAME_TO_FAMILY[aura.name] then
		return Catalog.AURA_NAME_TO_FAMILY[aura.name], nil, nil, nil, nil
	end
	-- Paladin Righteous Fury
	if (aura.spellId == Catalog.RIGHTEOUS_FURY.spellID) or (aura.name == Catalog.RIGHTEOUS_FURY.name) then
		return nil, nil, nil, true, nil
	end
	-- Paladin Seals (static catalog + dynamic "^Seal of " match for Forever seals)
	if aura.spellId and Catalog.SEAL_SPELL_ID_TO_ID[aura.spellId] then
		return nil, nil, nil, nil, Catalog.SEAL_SPELL_ID_TO_ID[aura.spellId]
	end
	if aura.name then
		local catSeal = Catalog.SEAL_BY_NAME[aura.name]
		if catSeal then
			return nil, nil, nil, nil, catSeal.id
		elseif aura.name:find("^Seal of ") then
			return nil, nil, nil, nil, "SEAL_" .. aura.name:upper():gsub("[^A-Z0-9]+", "_")
		end
	end
	-- Paladin Auras
	for aid, def in ipairs(Catalog.PALADIN_AURAS) do
		if aura.name == def.name then
			return nil, aid, nil, nil, nil
		end
		for _, sid in ipairs(def.ranks) do
			if aura.spellId == sid then
				return nil, aid, nil, nil, nil
			end
		end
	end
	-- Shaman Totems
	for tid, def in pairs(Catalog.TOTEM_BY_ID) do
		if aura.name == def.auraName or aura.name == def.name then
			return nil, nil, tid, nil, nil
		end
		for _, sid in ipairs(def.ranks) do
			if aura.spellId == sid then
				return nil, nil, tid, nil, nil
			end
		end
	end
	return nil, nil, nil, nil, nil
end

-- Secret-safe live unit aura scanner
function Scanner:ScanUnit(unit, unitInfo)
	local Compat = LBB.Compat
	local now = Compat.GetTime()
	local inCombat = Compat.InCombat()
	local key = unitCacheKey(unit, unitInfo)

	local cache = self.auraCache[key]
	if not cache then
		cache = {
			families = {},
			paladinAuras = {},
			righteousFury = nil,
			seals = {},
			totems = {},
			consumables = {},
			wasDead = false,
			battleRezzed = false,
		}
		self.auraCache[key] = cache
	end

	local isDead = Compat.UnitIsDeadOrGhost(unit)
	if isDead then
		-- Death wipes raid buffs; clear cached buffs so if battle-rezzed we highlight critical missing buff
		cache.families = {}
		cache.paladinAuras = {}
		cache.righteousFury = nil
		cache.seals = {}
		cache.totems = {}
		cache.wasDead = true
		cache.battleRezzed = false
		return {
			unit = unit,
			families = {},
			paladinAuras = {},
			righteousFury = nil,
			seals = {},
			totems = {},
			consumables = cache.consumables,
			restricted = false,
			battleRezzed = false,
			isDead = true,
		}
	elseif cache.wasDead then
		-- Unit transitioned from dead -> alive (e.g. Battle Rez or Rebirth!)
		cache.wasDead = false
		cache.battleRezzed = inCombat and true or false
	elseif not inCombat then
		cache.battleRezzed = false
	end

	local foundFamilies = {}
	local foundAuras = {}
	local foundRF = nil
	local foundSeals = {}
	local foundTotems = {}
	local foundConsumables = {}
	local scanRestricted = false

	for i = 1, self.MAX_AURAS do
		local aura, blocked = Compat.GetAuraDataByIndex(unit, i, "HELPFUL")
		if blocked then
			scanRestricted = true
			break
		end
		if not aura then
			break
		end
		if aura.isCompletelyHidden then
			scanRestricted = true
		else
			local famID, palAuraID, totemID, isRF, sealID = matchTotemOrAura(aura)
			local exp = aura.expirationTime
			local dur = aura.duration

			if famID then
				-- If expirationTime is secret in combat, extrapolate from cache
				if (exp == nil or dur == nil) and cache.families[famID] then
					exp = cache.families[famID].expirationTime
					dur = cache.families[famID].duration
				end
				foundFamilies[famID] = {
					present = true,
					spellId = aura.spellId,
					name = aura.name,
					expirationTime = exp or 0,
					duration = dur or 0,
					source = aura.sourceUnit,
				}
			elseif isRF then
				if (exp == nil or dur == nil) and cache.righteousFury then
					exp = cache.righteousFury.expirationTime
					dur = cache.righteousFury.duration
				end
				foundRF = {
					present = true,
					spellId = aura.spellId,
					name = aura.name,
					expirationTime = exp or 0,
					duration = dur or 1800,
				}
			elseif sealID then
				local cachedSeal = cache.seals and cache.seals[sealID]
				if (exp == nil or dur == nil) and cachedSeal then
					exp = cachedSeal.expirationTime
					dur = cachedSeal.duration
				end
				foundSeals[sealID] = {
					present = true,
					spellId = aura.spellId,
					name = aura.name,
					expirationTime = exp or 0,
					duration = dur or 30,
				}
			elseif palAuraID then
				foundAuras[palAuraID] = true
			elseif totemID then
				foundTotems[totemID] = true
			end

			local cid = matchConsumable(aura)
			if cid then
				foundConsumables[cid] = {
					present = true,
					name = aura.name,
					expirationTime = exp or 0,
					duration = dur or 0,
				}
			end
		end
	end

	-- Weapon enchant check (available for player)
	if unit == "player" then
		local hasMain, mainExp, _, _, hasOff, offExp = Compat.GetWeaponEnchantInfo()
		if hasMain or hasOff then
			local remMs = math_max(hasMain and (mainExp or 0) or 0, hasOff and (offExp or 0) or 0)
			foundConsumables.WEAPON_OIL = {
				present = true,
				name = "Weapon Enhancement",
				expirationTime = now + (remMs / 1000),
				duration = remMs / 1000,
			}
		end
	end

	if not scanRestricted then
		-- Full readable scan: update cache authoritatively
		cache.families = foundFamilies
		cache.paladinAuras = foundAuras
		cache.righteousFury = foundRF
		cache.seals = foundSeals
		cache.totems = foundTotems
		cache.consumables = foundConsumables
		if next(foundFamilies) ~= nil then
			cache.battleRezzed = false
		end
		return {
			unit = unit,
			families = foundFamilies,
			paladinAuras = foundAuras,
			righteousFury = foundRF,
			seals = foundSeals,
			totems = foundTotems,
			consumables = foundConsumables,
			restricted = false,
			battleRezzed = cache.battleRezzed,
		}
	end

	-- Combat restricted fallback: merge any readable auras with pre-combat cached entries that have not expired
	local mergedFamilies = {}
	for famID, entry in pairs(cache.families) do
		if entry.expirationTime == 0 or entry.expirationTime > now then
			mergedFamilies[famID] = entry
		end
	end
	for famID, entry in pairs(foundFamilies) do
		mergedFamilies[famID] = entry
		cache.families[famID] = entry
	end

	local mergedRF = foundRF
	if not mergedRF and cache.righteousFury and (cache.righteousFury.expirationTime == 0 or cache.righteousFury.expirationTime > now) then
		mergedRF = cache.righteousFury
	end
	if foundRF then
		cache.righteousFury = foundRF
	end

	local mergedSeals = {}
	for sid, entry in pairs(cache.seals or {}) do
		if entry.expirationTime == 0 or entry.expirationTime > now then
			mergedSeals[sid] = entry
		end
	end
	for sid, entry in pairs(foundSeals) do
		mergedSeals[sid] = entry
		cache.seals[sid] = entry
	end

	local mergedConsumables = {}
	for cid, entry in pairs(cache.consumables) do
		if entry.expirationTime == 0 or entry.expirationTime > now then
			mergedConsumables[cid] = entry
		end
	end
	for cid, entry in pairs(foundConsumables) do
		mergedConsumables[cid] = entry
		cache.consumables[cid] = entry
	end

	local mergedAuras = {}
	for aid, v in pairs(cache.paladinAuras) do
		mergedAuras[aid] = v
	end
	for aid, v in pairs(foundAuras) do
		mergedAuras[aid] = v
	end

	local mergedTotems = {}
	for tid, v in pairs(cache.totems) do
		mergedTotems[tid] = v
	end
	for tid, v in pairs(foundTotems) do
		mergedTotems[tid] = v
	end

	return {
		unit = unit,
		families = mergedFamilies,
		paladinAuras = mergedAuras,
		righteousFury = mergedRF,
		seals = mergedSeals,
		totems = mergedTotems,
		consumables = mergedConsumables,
		restricted = true,
		battleRezzed = cache.battleRezzed,
	}
end

function Scanner:GetRemainingSeconds(auraEntry, now)
	if not auraEntry or not auraEntry.present then
		return 0
	end
	now = now or LBB.Compat.GetTime()
	local exp = auraEntry.expirationTime or 0
	if exp == 0 then
		-- Permanent / aura without finite timer (e.g. Blood Pact, Paladin Aura)
		return 3600
	end
	return math_max(0, exp - now)
end

local function roleWeight(role)
	if role == "TANK" then
		return 3
	elseif role == "HEALER" then
		return 2
	end
	return 1
end

local function collectDutyTargets(duty, roster)
	local Catalog = LBB.Catalog
	local targets = {}

	if duty.kind == "PALADIN_AURA" or duty.kind == "SHAMAN_TOTEM" or duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL" then
		for _, m in ipairs(roster) do
			if m.name == duty.caster then
				table_insert(targets, m)
				break
			end
		end
		if #targets == 0 and LBB.Compat.UnitExists("player") then
			table_insert(targets, {
				name = duty.caster,
				unit = "player",
				online = true,
				alive = not LBB.Compat.UnitIsDeadOrGhost("player"),
			})
		end
		return targets
	end

	local fam = Catalog.GetFamily(duty.familyID)
	if not fam then
		return targets
	end

	if duty.kind == "GROUP_BUFF" then
		local allowedSubs = {}
		for _, sg in ipairs(duty.subgroups or {}) do
			allowedSubs[sg] = true
		end
		for _, m in ipairs(roster) do
			if allowedSubs[m.subgroup or 1] and Catalog.MatchesUnitFilter(fam, m) then
				table_insert(targets, m)
			end
		end
	elseif duty.kind == "CLASS_BUFF" then
		local allowedClasses = {}
		for _, cls in ipairs(duty.classes or {}) do
			allowedClasses[cls] = true
		end
		local excluded = duty.excludedTargets or {}
		local includedOverrides = {}
		for _, tName in ipairs(duty.overrideTargets or {}) do
			includedOverrides[tName] = true
		end
		local seen = {}
		for _, m in ipairs(roster) do
			local matchClass = allowedClasses[m.class] and not excluded[m.name]
			local matchOverride = includedOverrides[m.name] == true
			if (matchClass or matchOverride) and not seen[m.name] then
				seen[m.name] = true
				table_insert(targets, m)
			end
		end
	elseif duty.kind == "TARGET_BUFF" then
		local allowedNames = {}
		for _, tName in ipairs(duty.targets or {}) do
			allowedNames[tName] = true
		end
		for _, m in ipairs(roster) do
			if allowedNames[m.name] then
				table_insert(targets, m)
			end
		end
	end

	return targets
end

-- Evaluate a duty across the roster and pick the best next target to cast on
function Scanner:EvaluateDuty(duty, roster, options)
	local Compat = LBB.Compat
	local Catalog = LBB.Catalog
	local now = Compat.GetTime()
	local refreshThreshold = (options and options.refreshThreshold) or (LBB.DB and LBB.DB.refreshThreshold) or self.DEFAULT_REFRESH_THRESHOLD

	local playerVec = LBB.Capabilities:GetPlayerVector()
	local singleSpellName, groupSpellName, hasGroup, icon, groupThreshold, nativeSpellIDs
	local fam = duty.familyID and Catalog.GetFamily(duty.familyID) or nil

	if duty.kind == "PALADIN_AURA" then
		local def = Catalog.PALADIN_AURAS[duty.auraID]
		local known = playerVec and playerVec.auras and playerVec.auras[duty.auraID]
		singleSpellName = (known and known.name) or (def and def.name)
		icon = (known and known.icon) or (def and def.icon)
	elseif duty.kind == "RIGHTEOUS_FURY" then
		local def = Catalog.RIGHTEOUS_FURY
		local known = playerVec and playerVec.righteousFury
		singleSpellName = (known and known.name) or duty.spellName or def.name
		icon = (known and known.icon) or duty.icon or def.icon
		nativeSpellIDs = (known and known.allSpellIDs) or { [def.spellID] = true }
	elseif duty.kind == "PALADIN_SEAL" then
		local known = playerVec and playerVec.seals and duty.sealID and playerVec.seals[duty.sealID]
		local def = duty.sealID and Catalog.SEAL_BY_ID[duty.sealID]
		singleSpellName = (known and known.name) or duty.spellName or (def and def.name)
		icon = (known and known.icon) or duty.icon or (def and def.icon) or 132325
		nativeSpellIDs = (known and known.allSpellIDs) or duty.allSpellIDs or (duty.spellID and { [duty.spellID] = true }) or {}
		-- Seals last 30s; warn only under 6s instead of 180s
		refreshThreshold = math_min(refreshThreshold, 6)
	elseif duty.kind == "SHAMAN_TOTEM" then
		local def = Catalog.TOTEM_BY_ID[duty.totemID]
		local known = playerVec and playerVec.totems and playerVec.totems[duty.element] and playerVec.totems[duty.element][duty.totemID]
		singleSpellName = (known and known.name) or (def and def.name)
		icon = (known and known.icon) or (def and def.icon)
	elseif fam then
		local known = playerVec and playerVec.buffs and playerVec.buffs[duty.familyID]
		singleSpellName = (known and known.bestSingleName) or fam.name
		groupSpellName = (known and known.hasGroup and known.bestGroupName) or nil
		hasGroup = known and known.hasGroup or false
		icon = (known and known.icon) or fam.icon
		groupThreshold = (options and options.groupThreshold) or (LBB.DB and LBB.DB.groupThreshold) or fam.groupThreshold or 2
	end

	local targets = collectDutyTargets(duty, roster)
	local totalEligible = 0
	local buffedCount = 0
	local missingCount = 0
	local expiringCount = 0
	local inRangeMissingCount = 0
	local shortestRemaining = math_huge
	local candidates = {}

	for _, m in ipairs(targets) do
		local unit = m.unit
		if unit and Compat.UnitExists(unit) and Compat.UnitIsDeadOrGhost(unit) then
			self:ScanUnit(unit, m)
		elseif unit and m.online and m.alive and Compat.UnitExists(unit) then
			totalEligible = totalEligible + 1
			local scan = self:ScanUnit(unit, m)

			local present = false
			local remaining = 0
			if duty.kind == "PALADIN_AURA" then
				present = scan.paladinAuras[duty.auraID] == true
				remaining = present and 3600 or 0
			elseif duty.kind == "RIGHTEOUS_FURY" then
				local rf = scan.righteousFury
				if rf and rf.present then
					present = true
					remaining = self:GetRemainingSeconds(rf, now)
				end
			elseif duty.kind == "PALADIN_SEAL" then
				local s = duty.sealID and scan.seals and scan.seals[duty.sealID]
				if s and s.present then
					present = true
					remaining = self:GetRemainingSeconds(s, now)
				end
			elseif duty.kind == "SHAMAN_TOTEM" then
				present = scan.totems[duty.totemID] == true
				remaining = present and 120 or 0
			else
				local a = scan.families[duty.familyID]
				if a and a.present then
					present = true
					remaining = self:GetRemainingSeconds(a, now)
				end
			end

			if present then
				if remaining < shortestRemaining then
					shortestRemaining = remaining
				end
			else
				shortestRemaining = 0
			end

			local needsCast = (not present) or (remaining < refreshThreshold)
			if not present then
				missingCount = missingCount + 1
			elseif remaining < refreshThreshold then
				expiringCount = expiringCount + 1
			else
				buffedCount = buffedCount + 1
			end

			if needsCast then
				local inRange
				if unit == "player" then
					inRange = true
				elseif singleSpellName then
					inRange = Compat.IsSpellInRange(singleSpellName, unit)
				end
				if inRange == true then
					inRangeMissingCount = inRangeMissingCount + 1
				end
				table_insert(candidates, {
					member = m,
					unit = unit,
					name = m.name,
					present = present,
					remaining = remaining,
					inRange = inRange,
					rolePriority = roleWeight(m.role),
				})
			end
		end
	end

	-- Deterministic priority ordering for next cast target:
	-- 1. In-range (true > nil > false)
	-- 2. Completely missing before expiring
	-- 3. Higher role priority (Tank > Healer > DPS)
	-- 4. Shorter remaining time
	-- 5. Alphabetical name
	local function rangeScore(r)
		if r == true then
			return 2
		elseif r == nil then
			return 1
		end
		return 0
	end

	table_sort(candidates, function(a, b)
		local ar, br = rangeScore(a.inRange), rangeScore(b.inRange)
		if ar ~= br then
			return ar > br
		end
		if a.present ~= b.present then
			return (not a.present) and b.present
		end
		if a.rolePriority ~= b.rolePriority then
			return a.rolePriority > b.rolePriority
		end
		if a.remaining ~= b.remaining then
			return a.remaining < b.remaining
		end
		return (a.name or "") < (b.name or "")
	end)

	local nextTarget = candidates[1] or nil
	local needCount = missingCount + expiringCount
	local recommendGroup = (hasGroup and groupSpellName ~= nil and needCount >= (groupThreshold or 2))

	local reagentCount = nil
	local lowReagent = false
	if duty.reagentItemID then
		reagentCount = Compat.GetItemCount(duty.reagentItemID)
		local lowThresh = (fam and fam.reagentLowThreshold) or 20
		lowReagent = (reagentCount < lowThresh)
	end

	if shortestRemaining == math_huge then
		shortestRemaining = nil
	end

	return {
		duty = duty,
		icon = icon,
		singleSpellName = singleSpellName,
		groupSpellName = groupSpellName,
		hasGroup = hasGroup,
		nativeSpellIDs = nativeSpellIDs,
		hasClassOverride = duty.hasClassOverride and true or false,
		totalEligible = totalEligible,
		buffedCount = buffedCount,
		missingCount = missingCount,
		expiringCount = expiringCount,
		needCount = needCount,
		inRangeMissingCount = inRangeMissingCount,
		shortestRemaining = shortestRemaining,
		nextTarget = nextTarget,
		recommendGroup = recommendGroup,
		reagentCount = reagentCount,
		lowReagent = lowReagent,
		candidates = candidates,
	}
end

local function dutyAutoPriority(duty, eval)
	if eval.missingCount > 0 then
		if duty.kind == "PALADIN_AURA" or duty.kind == "RIGHTEOUS_FURY" then
			return 100
		elseif duty.kind == "SHAMAN_TOTEM" or duty.familyID == "BATTLE_SHOUT" then
			return 90
		elseif duty.kind == "PALADIN_SEAL" then
			return 85
		elseif eval.nextTarget and eval.nextTarget.inRange == true then
			return 70 + (eval.nextTarget.rolePriority or 1)
		elseif eval.nextTarget and eval.nextTarget.inRange == nil then
			return 60 + (eval.nextTarget.rolePriority or 1)
		else
			return 40 + (eval.nextTarget and eval.nextTarget.rolePriority or 1)
		end
	elseif eval.expiringCount > 0 then
		if duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL" then
			return 35
		elseif eval.nextTarget and eval.nextTarget.inRange ~= false then
			return 25 + (eval.nextTarget.rolePriority or 1)
		else
			return 10
		end
	end
	return 0
end

-- Pick the single highest-priority next action across ALL of a player's active duties
-- (Powers the one-click Smart Buff tile & WoW Keybinding in Bindings.xml)
function Scanner:GetBestAutoBuffAction(duties, roster, options)
	local totalMissing = 0
	local totalExpiring = 0
	local bestEval = nil
	local bestScore = 0
	local fallbackEval = nil

	for _, duty in ipairs(duties or {}) do
		local eval = self:EvaluateDuty(duty, roster, options)
		if eval.totalEligible > 0 then
			if not fallbackEval then
				fallbackEval = eval
			end
			totalMissing = totalMissing + (eval.missingCount or 0)
			totalExpiring = totalExpiring + (eval.expiringCount or 0)
			if eval.needCount > 0 then
				local score = dutyAutoPriority(duty, eval)
				if score > bestScore then
					bestScore = score
					bestEval = eval
				elseif score == bestScore and bestEval then
					local remA = eval.shortestRemaining or 0
					local remB = bestEval.shortestRemaining or 0
					if remA < remB then
						bestEval = eval
					end
				end
			end
		end
	end

	local chosen = bestEval or fallbackEval
	local targetUnit = "player"
	if chosen then
		local k = chosen.duty.kind
		if k ~= "PALADIN_AURA" and k ~= "SHAMAN_TOTEM" and k ~= "RIGHTEOUS_FURY" and k ~= "PALADIN_SEAL" and chosen.duty.familyID ~= "BATTLE_SHOUT" then
			targetUnit = (chosen.nextTarget and chosen.nextTarget.unit) or "player"
		end
	end

	return {
		hasAction = bestEval ~= nil,
		allHealthy = (totalMissing == 0 and totalExpiring == 0),
		totalMissing = totalMissing,
		totalExpiring = totalExpiring,
		nextDuty = chosen and chosen.duty or nil,
		nextEval = chosen,
		unit = targetUnit,
		singleSpell = chosen and chosen.singleSpellName or "",
		groupSpell = chosen and ((chosen.hasGroup and chosen.groupSpellName) or chosen.singleSpellName) or "",
		icon = chosen and chosen.icon or "Interface\\AddOns\\LittleBuffBoy\\Media\\MinimapIcon",
		recommendGroup = chosen and chosen.recommendGroup or false,
	}
end

-- Build a full Ready Check / Nudge report across all assigned duties + player consumables
function Scanner:BuildReadinessReport(roster, assignments)
	local Catalog = LBB.Catalog
	local Compat = LBB.Compat
	local report = {
		missingByCaster = {}, -- [casterName] = { { familyName, missingCount, totalCount } }
		consumables = {},     -- [memberName] = { WELL_FED = bool, FLASK_ELIXIR = bool, WEAPON_OIL = bool }
		playerConsumables = {},
		totalMissingBuffs = 0,
	}

	-- Scan consumables for roster
	for _, m in ipairs(roster) do
		if m.unit and m.online and m.alive and Compat.UnitExists(m.unit) then
			local scan = self:ScanUnit(m.unit, m)
			local cState = {
				WELL_FED = scan.consumables.WELL_FED ~= nil,
				FLASK_ELIXIR = scan.consumables.FLASK_ELIXIR ~= nil,
				WEAPON_OIL = scan.consumables.WEAPON_OIL ~= nil,
			}
			report.consumables[m.name] = cState
			if m.unit == "player" then
				report.playerConsumables = cState
			end
		end
	end

	-- Gather all casters who have duties in assignments
	local casters = {}
	local seen = {}
	local function addCaster(name)
		if name and not seen[name] then
			seen[name] = true
			table_insert(casters, name)
		end
	end
	for _, subs in pairs(assignments.groupBuffs or {}) do
		for _, e in pairs(subs) do
			addCaster(e.caster)
		end
	end
	for caster in pairs(assignments.classBuffs or {}) do
		addCaster(caster)
	end
	for _, tMap in pairs(assignments.targetBuffs or {}) do
		for _, e in pairs(tMap) do
			addCaster(e.caster)
		end
	end
	table_sort(casters)

	for _, casterName in ipairs(casters) do
		local duties = assignments:GetPlayerDuties(casterName)
		for _, duty in ipairs(duties) do
			if duty.familyID then
				local eval = self:EvaluateDuty(duty, roster)
				if eval.missingCount > 0 then
					local fam = Catalog.GetFamily(duty.familyID)
					report.missingByCaster[casterName] = report.missingByCaster[casterName] or {}
					table_insert(report.missingByCaster[casterName], {
						familyID = duty.familyID,
						familyName = (fam and fam.shortName) or duty.familyID,
						fullName = (fam and fam.name) or duty.familyID,
						missingCount = eval.missingCount,
						totalCount = eval.totalEligible,
					})
					report.totalMissingBuffs = report.totalMissingBuffs + eval.missingCount
				end
			end
		end
	end

	return report
end
