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
Scanner.BACKOFF_DURATION = 6 -- seconds to temporarily deprioritize a failed/LoS target so buffing never gets stuck

-- Pre-combat cached aura state per unitKey (guid or unit token)
-- auraCache[unitKey] = { families = { [famID] = { expirationTime, duration, spellId, source } }, consumables = { ... }, wasDead = bool }
Scanner.auraCache = {}
Scanner.backoffTargets = {}
Scanner.lastAttempt = nil
Scanner.pendingCast = nil
Scanner.pendingSecretSuccess = nil

function Scanner:Reset()
	self.auraCache = {}
	self.backoffTargets = {}
	self.lastAttempt = nil
	self.pendingCast = nil
	self.pendingSecretSuccess = nil
end

function Scanner:MarkTargetSkipped(targetKey, duration)
	if not targetKey then
		return
	end
	local now = LBB.Compat.GetTime()
	self.backoffTargets[targetKey] = now + (duration or self.BACKOFF_DURATION)
end

function Scanner:ClearTargetSkipped(targetKey)
	if targetKey then
		self.backoffTargets[targetKey] = nil
	end
end

function Scanner:IsTargetSkipped(targetKey, now)
	if not targetKey then
		return false
	end
	local untilTime = self.backoffTargets[targetKey]
	if not untilTime then
		return false
	end
	now = now or LBB.Compat.GetTime()
	if now >= untilTime then
		self.backoffTargets[targetKey] = nil
		return false
	end
	return true
end

-- Record a user click / cast attempt on `(unit, targetName, dutyKey, spellName)`.
-- If the same target+duty is clicked again within 0.35s..3.5s out of combat and still hasn't received the buff
-- (e.g. blocked by Line of Sight or moving), temporarily rotate to the next in-range target!
-- Ignores sub-0.35s duplicate events (MouseDown + MouseUp on the same physical click) and never rotates during combat lockdown.
function Scanner:RecordCastAttempt(unit, targetName, dutyKey, spellName)
	if not unit then
		return false
	end
	local now = LBB.Compat.GetTime()
	local targetKey = targetName or unit
	local prev = self.lastAttempt
	local rotated = false
	if prev and prev.targetKey == targetKey and prev.dutyKey == dutyKey and prev.spellName == spellName then
		local dt = now - (prev.time or 0)
		if dt < 0.35 then
			-- Same physical click (MouseDown followed by MouseUp): ignore duplicate phase
			return false
		end
		if unit ~= "player" and not LBB.Compat.InCombat() and dt <= 3.5 then
			self:MarkTargetSkipped(targetKey, self.BACKOFF_DURATION)
			rotated = true
		end
	end
	self.lastAttempt = {
		unit = unit,
		targetKey = targetKey,
		dutyKey = dutyKey,
		spellName = spellName,
		time = now,
		rotated = rotated,
	}
	-- If UNIT_SPELLCAST_SUCCEEDED fired synchronously during OnClick (before PostClick) with a secret spellID,
	-- apply the optimistic combat aura cache update right now using the button's exact spellName & unit!
	if self.pendingSecretSuccess and (now - self.pendingSecretSuccess) <= 0.35 and spellName and spellName ~= "" then
		self.pendingSecretSuccess = nil
		if self:ApplyOptimisticCast(nil, spellName, unit, targetKey) then
			return true
		end
	end
	return rotated
end

-- Called immediately when UNIT_SPELLCAST_FAILED or a cast-blocking UI_ERROR_MESSAGE fires
function Scanner:OnPlayerCastFailed()
	if LBB.Compat.InCombat() then
		return false
	end
	local prev = self.lastAttempt
	if not prev or not prev.targetKey or prev.unit == "player" then
		return false
	end
	local now = LBB.Compat.GetTime()
	if (now - prev.time) <= 2.5 then
		self:MarkTargetSkipped(prev.targetKey, self.BACKOFF_DURATION)
		return true
	end
	return false
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

local function isGroupSpellForFamily(fam, spellID, spellName)
	if not fam then
		return false
	end
	if spellName and fam.groupName and spellName == fam.groupName then
		return true
	end
	if spellID and fam.groupRanks then
		for _, entry in ipairs(fam.groupRanks) do
			local sid = type(entry) == "table" and entry.spellID or entry
			if sid == spellID then
				return true
			end
		end
	end
	return false
end

function Scanner:EnsureUnitCache(unit, unitInfo)
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
	return cache
end

function Scanner:OnPlayerSpellcastSent(unit, targetName, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	local Compat = LBB.Compat
	local cleanTarget = Compat.SafeRead(targetName, nil)
	if type(cleanTarget) == "string" and cleanTarget ~= "" then
		cleanTarget = Compat.NormalizeName(cleanTarget)
	else
		cleanTarget = nil
	end
	self.pendingCast = {
		targetName = cleanTarget,
		castGUID = Compat.SafeRead(castGUID, nil),
		spellID = Compat.SafeRead(spellID, nil),
		time = Compat.GetTime(),
	}
end

function Scanner:ApplyOptimisticCast(sid, sName, hintUnit, hintTargetName)
	local Compat = LBB.Compat
	local Catalog = LBB.Catalog
	local now = Compat.GetTime()
	local optUntil = now + 2.5
	local castInCombat = Compat.InCombat()

	if not sid and (not sName or sName == "") then
		return false
	end

	local rosterByUnit = (LBB.Assignments and LBB.Assignments.rosterByUnit) or {}
	local rosterByName = (LBB.Assignments and LBB.Assignments.rosterByName) or {}
	local roster = (LBB.Assignments and LBB.Assignments.roster) or {}
	local playerMember = rosterByUnit["player"]
	if not playerMember then
		local pName = Compat.GetFullUnitName("player")
		playerMember = pName and rosterByName[pName] or nil
	end

	-- Paladin Judgement (20271) consumes active Seal in Classic / Forever
	if sid == 20271 or sName == "Judgement" or sName == "Judgment" then
		local pCache = self:EnsureUnitCache("player", playerMember)
		pCache.seals = {}
		return true
	end

	local famID, palAuraID, totemID, isRF, sealID = matchTotemOrAura({
		spellId = sid,
		name = sName,
	})
	if not (famID or palAuraID or totemID or isRF or sealID) then
		return false
	end

	if sealID then
		local pCache = self:EnsureUnitCache("player", playerMember)
		pCache.seals = {
			[sealID] = {
				present = true,
				spellId = sid,
				name = sName,
				expirationTime = now + 30,
				duration = 30,
				optimisticUntil = optUntil,
				castInCombat = castInCombat,
			},
		}
		return true
	elseif isRF then
		local pCache = self:EnsureUnitCache("player", playerMember)
		pCache.righteousFury = {
			present = true,
			spellId = sid,
			name = sName or Catalog.RIGHTEOUS_FURY.name,
			expirationTime = now + 1800,
			duration = 1800,
			optimisticUntil = optUntil,
			castInCombat = castInCombat,
		}
		return true
	elseif palAuraID then
		local pCache = self:EnsureUnitCache("player", playerMember)
		pCache.paladinAuras = { [palAuraID] = true }
		return true
	elseif totemID then
		local pCache = self:EnsureUnitCache("player", playerMember)
		pCache.totems[totemID] = true
		local mySub = (playerMember and playerMember.subgroup) or 1
		for _, m in ipairs(roster) do
			if (m.subgroup or 1) == mySub and m.online and m.alive then
				local c = self:EnsureUnitCache(m.unit, m)
				c.totems[totemID] = true
			end
		end
		return true
	end

	-- Buff family cast (single or group)
	local fam = Catalog.GetFamily(famID)
	local isGroup = isGroupSpellForFamily(fam, sid, sName)
	local dur = isGroup and 1800 or ((fam and fam.class == "PALADIN") and 600 or (famID == "BATTLE_SHOUT" and 120 or 1800))
	local exp = now + dur

	-- Resolve intended target member from hint -> pendingCast -> lastAttempt -> player
	local targetMember = nil
	local targetUnit = hintUnit
	if hintTargetName and rosterByName[hintTargetName] then
		targetMember = rosterByName[hintTargetName]
	elseif hintUnit and rosterByUnit[hintUnit] then
		targetMember = rosterByUnit[hintUnit]
	end
	if not targetMember and self.pendingCast and (now - (self.pendingCast.time or 0)) <= 3.0 then
		if self.pendingCast.targetName then
			targetMember = rosterByName[self.pendingCast.targetName]
		end
	end
	if not targetMember and self.lastAttempt and (now - (self.lastAttempt.time or 0)) <= 3.5 then
		targetUnit = targetUnit or self.lastAttempt.unit
		targetMember = (self.lastAttempt.targetKey and rosterByName[self.lastAttempt.targetKey])
			or (targetUnit and rosterByUnit[targetUnit])
	end
	if not targetMember then
		targetMember = playerMember
		targetUnit = targetUnit or "player"
	else
		targetUnit = targetMember.unit or targetUnit or "player"
	end

	local function applyFamilyToUnit(u, m)
		local c = self:EnsureUnitCache(u, m)
		c.families[famID] = {
			present = true,
			spellId = sid,
			name = sName or (fam and fam.name) or famID,
			expirationTime = exp,
			duration = dur,
			source = "player",
			optimisticUntil = optUntil,
			castInCombat = castInCombat,
		}
		c.battleRezzed = false
		if m and m.name then
			self:ClearTargetSkipped(m.name)
		end
		if u then
			self:ClearTargetSkipped(u)
		end
	end

	if famID == "BATTLE_SHOUT" then
		applyFamilyToUnit("player", playerMember)
		local mySub = (playerMember and playerMember.subgroup) or 1
		for _, m in ipairs(roster) do
			if (m.subgroup or 1) == mySub and m.online and m.alive then
				applyFamilyToUnit(m.unit, m)
			end
		end
	elseif isGroup and fam then
		local tClass = targetMember and targetMember.class
		local tSub = (targetMember and targetMember.subgroup) or 1
		local appliedAny = false
		for _, m in ipairs(roster) do
			if m.online and m.alive then
				if (fam.scope == "CLASS" and tClass and m.class == tClass)
					or (fam.scope ~= "CLASS" and (m.subgroup or 1) == tSub and Catalog.MatchesUnitFilter(fam, m)) then
					applyFamilyToUnit(m.unit, m)
					appliedAny = true
				end
			end
		end
		if not appliedAny then
			applyFamilyToUnit(targetUnit, targetMember)
		end
	else
		applyFamilyToUnit(targetUnit, targetMember)
	end

	return true
end

-- Optimistically update auraCache when player finishes casting a buff/seal/totem/Judgement.
-- Critical during combat in Midnight (12.1.5 / 16001) when C_UnitAuras or spellID returns secret values!
function Scanner:OnPlayerSpellcastSucceeded(unit, castGUID, spellID)
	local Compat = LBB.Compat
	if Compat.SafeRead(unit, nil) ~= "player" then
		return false
	end
	local now = Compat.GetTime()
	local sid = Compat.SafeRead(spellID, nil)
	local cguid = Compat.SafeRead(castGUID, nil)
	local sInfo = sid and Compat.GetSpellInfo(sid) or nil
	local sName = sInfo and sInfo.name or nil

	local hintUnit, hintTarget = nil, nil
	if self.pendingCast and ((cguid and self.pendingCast.castGUID == cguid) or (now - (self.pendingCast.time or 0)) <= 3.0) then
		hintTarget = self.pendingCast.targetName
	end

	-- If Midnight returned a secret spellID in combat, fall back to the spellName & unit recorded by our BuffStrip click!
	if not sid and not sName then
		if self.lastAttempt and self.lastAttempt.spellName and (now - (self.lastAttempt.time or 0)) <= 2.5 then
			sName = self.lastAttempt.spellName
			hintUnit = self.lastAttempt.unit
			hintTarget = hintTarget or self.lastAttempt.targetKey
		else
			-- UNIT_SPELLCAST_SUCCEEDED fired synchronously during OnClick before PostClick ran: defer to PostClick!
			self.pendingSecretSuccess = now
			return false
		end
	end

	return self:ApplyOptimisticCast(sid, sName, hintUnit, hintTarget)
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
	local spiritOfRedemption = false

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
			-- Holy Priest Spirit of Redemption (27827): cannot be buffed while in angel form
			if aura.spellId == 27827 or aura.name == "Spirit of Redemption" then
				spiritOfRedemption = true
			end
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
		-- During combat, preserve buffs explicitly cast by the player during this combat while unexpired
		-- (handles Midnight secret/hidden combat-applied auras and the UNIT_SPELLCAST_SUCCEEDED -> UNIT_AURA window).
		-- When combat ends (`not inCombat`), live C_UnitAuras reconciles everything authoritatively!
		if inCombat then
			local function keepInCombat(entry)
				if not entry then
					return false
				end
				if entry.optimisticUntil and now < entry.optimisticUntil then
					return true
				end
				if entry.castInCombat and (entry.expirationTime == 0 or (entry.expirationTime or 0) > now) then
					return true
				end
				return false
			end
			for famID, entry in pairs(cache.families) do
				if not foundFamilies[famID] and keepInCombat(entry) then
					foundFamilies[famID] = entry
				end
			end
			if not foundRF and keepInCombat(cache.righteousFury) then
				foundRF = cache.righteousFury
			end
			for sid, entry in pairs(cache.seals or {}) do
				if not foundSeals[sid] and keepInCombat(entry) then
					foundSeals[sid] = entry
				end
			end
		end
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
			unbuffable = spiritOfRedemption,
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
	local singleSpellName, singleSpellID, groupSpellName, groupSpellID, hasGroup, icon, groupThreshold, nativeSpellIDs
	local fam = duty.familyID and Catalog.GetFamily(duty.familyID) or nil

	if duty.kind == "PALADIN_AURA" then
		local def = Catalog.PALADIN_AURAS[duty.auraID]
		local known = playerVec and playerVec.auras and playerVec.auras[duty.auraID]
		singleSpellName = (known and known.name) or (def and def.name)
		singleSpellID = (known and known.spellID) or (def and def.ranks and def.ranks[1])
		icon = (known and known.icon) or (def and def.icon)
	elseif duty.kind == "RIGHTEOUS_FURY" then
		local def = Catalog.RIGHTEOUS_FURY
		local known = playerVec and playerVec.righteousFury
		singleSpellName = (known and known.name) or duty.spellName or def.name
		singleSpellID = (known and known.spellID) or duty.spellID or def.spellID
		icon = (known and known.icon) or duty.icon or def.icon
		nativeSpellIDs = (known and known.allSpellIDs) or { [def.spellID] = true }
	elseif duty.kind == "PALADIN_SEAL" then
		local known = playerVec and playerVec.seals and duty.sealID and playerVec.seals[duty.sealID]
		local def = duty.sealID and Catalog.SEAL_BY_ID[duty.sealID]
		singleSpellName = (known and known.name) or duty.spellName or (def and def.name)
		singleSpellID = (known and known.spellID) or duty.spellID or (def and def.ranks and def.ranks[1])
		icon = (known and known.icon) or duty.icon or (def and def.icon) or 132325
		nativeSpellIDs = (known and known.allSpellIDs) or duty.allSpellIDs or (duty.spellID and { [duty.spellID] = true }) or {}
		-- Seals last 30s; warn only under 6s instead of 180s
		refreshThreshold = math_min(refreshThreshold, 6)
	elseif duty.kind == "SHAMAN_TOTEM" then
		local def = Catalog.TOTEM_BY_ID[duty.totemID]
		local known = playerVec and playerVec.totems and playerVec.totems[duty.element] and playerVec.totems[duty.element][duty.totemID]
		singleSpellName = (known and known.name) or (def and def.name)
		singleSpellID = (known and known.spellID) or (def and def.ranks and def.ranks[1])
		icon = (known and known.icon) or (def and def.icon)
	elseif fam then
		local known = playerVec and playerVec.buffs and playerVec.buffs[duty.familyID]
		singleSpellName = (known and known.bestSingleName) or fam.name
		singleSpellID = (known and known.bestSingleID) or (fam.singleRanks and fam.singleRanks[1] and fam.singleRanks[1].spellID)
		groupSpellName = (known and known.hasGroup and known.bestGroupName) or nil
		groupSpellID = (known and known.hasGroup and known.bestGroupID) or nil
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
	local inRangeExpiringCount = 0
	local inRangeNeedCount = 0
	local shortestRemaining = math_huge
	local candidates = {}
	local allTargets = {}
	local anyInRangeUnit = nil

	for _, m in ipairs(targets) do
		local unit = m.unit
		if unit and Compat.UnitExists(unit) and Compat.UnitIsDeadOrGhost(unit) then
			self:ScanUnit(unit, m)
		elseif unit and m.online and m.alive and Compat.IsUnitBuffable(unit) then
			local scan = self:ScanUnit(unit, m)
			if not scan.unbuffable then
				totalEligible = totalEligible + 1

				local inRange
				if unit == "player" or duty.kind == "PALADIN_AURA" or duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL" or duty.kind == "SHAMAN_TOTEM" or duty.familyID == "BATTLE_SHOUT" then
					inRange = true
				else
					inRange = Compat.IsSpellInRange(singleSpellName, unit, singleSpellID)
				end
				if inRange ~= false and not anyInRangeUnit then
					anyInRangeUnit = unit
				end

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
				local tKey = m.name or unit
				local targetEntry = {
					member = m,
					unit = unit,
					name = m.name,
					targetKey = tKey,
					present = present,
					needsCast = needsCast,
					remaining = remaining,
					inRange = inRange,
					backedOff = self:IsTargetSkipped(tKey, now),
					rolePriority = roleWeight(m.role),
				}
				table_insert(allTargets, targetEntry)

				if not needsCast then
					buffedCount = buffedCount + 1
					-- Buff landed: clear any temporary LoS/cast-failure backoff for this target
					self:ClearTargetSkipped(tKey)
				else
					if not present then
						missingCount = missingCount + 1
						if inRange ~= false then
							inRangeMissingCount = inRangeMissingCount + 1
						end
					else
						expiringCount = expiringCount + 1
						if inRange ~= false then
							inRangeExpiringCount = inRangeExpiringCount + 1
						end
					end
					if inRange ~= false then
						inRangeNeedCount = inRangeNeedCount + 1
					end

					table_insert(candidates, targetEntry)
				end
			end
		end
	end

	-- Deterministic priority ordering for next cast target:
	-- 1. In-range (true [2] > nil/unknown [1] > false/out-of-range [0])
	--    -> An IN-RANGE player ALWAYS beats an OUT-OF-RANGE player so you never get stuck!
	-- 2. Not in temporary LoS / failed-cast backoff (rotates past pillar-blocked targets automatically!)
	-- 3. Completely missing before expiring
	-- 4. Higher role priority (Tank > Healer > DPS)
	-- 5. Shorter remaining time
	-- 6. Alphabetical name
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
		if a.backedOff ~= b.backedOff then
			return (not a.backedOff) and b.backedOff
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

	-- Pre-combat staging target order across ALL eligible members of this duty (even when currently healthy!):
	-- Ensures SecureActionButton `unit1`/`unit2` stay aimed at the in-range duty member whose buff will expire FIRST
	-- (or the Tank/teammate of that duty) rather than resetting to "player" or locking to an out-of-range unit before combat starts!
	local selfPlayerName = playerVec and playerVec.name or nil
	local function isPlayerEntry(entry)
		return entry.unit == "player" or (selfPlayerName ~= nil and entry.name == selfPlayerName)
	end

	table_sort(allTargets, function(a, b)
		local ar, br = rangeScore(a.inRange), rangeScore(b.inRange)
		if ar ~= br then
			return ar > br
		end
		if a.backedOff ~= b.backedOff then
			return (not a.backedOff) and b.backedOff
		end
		if a.needsCast ~= b.needsCast then
			return a.needsCast and (not b.needsCast)
		end
		if a.present ~= b.present then
			return (not a.present) and b.present
		end
		-- When both targets are currently healthy and were buffed in the same session (within 60s of each other),
		-- prioritize higher role (Tank > Healer > DPS) and teammates ahead of self ("player") so entering combat
		-- doesn't default to "player" just because the player buffed themselves 2 seconds before their group!
		local remDiff = (a.remaining or 0) - (b.remaining or 0)
		if remDiff < 0 then
			remDiff = -remDiff
		end
		if not a.needsCast and not b.needsCast and remDiff <= 60 then
			local aSelf, bSelf = isPlayerEntry(a), isPlayerEntry(b)
			if aSelf ~= bSelf then
				return (not aSelf) and bSelf
			end
			if a.rolePriority ~= b.rolePriority then
				return a.rolePriority > b.rolePriority
			end
		end
		if a.remaining ~= b.remaining then
			return a.remaining < b.remaining
		end
		if a.rolePriority ~= b.rolePriority then
			return a.rolePriority > b.rolePriority
		end
		local aSelf, bSelf = isPlayerEntry(a), isPlayerEntry(b)
		if aSelf ~= bSelf then
			return (not aSelf) and bSelf
		end
		return (a.name or "") < (b.name or "")
	end)

	local combatUnitTokens = {}
	local seenCombatUnits = {}
	for _, entry in ipairs(allTargets) do
		if entry.unit and not seenCombatUnits[entry.unit] then
			seenCombatUnits[entry.unit] = true
			table_insert(combatUnitTokens, entry.unit)
		end
	end
	local combatUnits = table.concat(combatUnitTokens, ",")

	local nextTarget = candidates[1] or nil
	local combatTarget = allTargets[1] or nil
	-- If nextTarget is nil (duty is healthy) or nextTarget is out of range while an in-range duty member exists,
	-- stage `effectiveTarget` to the best in-range duty member (`combatTarget`) so entering combat never locks the button to "player" or an OOR unit.
	local effectiveTarget
	if nextTarget and nextTarget.inRange ~= false then
		effectiveTarget = nextTarget
	elseif combatTarget and combatTarget.inRange ~= false then
		effectiveTarget = combatTarget
	else
		effectiveTarget = nextTarget or combatTarget
	end

	local needCount = missingCount + expiringCount
	local allOutOfRange = (needCount > 0 and inRangeNeedCount == 0)
	local groupAnchorUnit = (effectiveTarget and effectiveTarget.inRange ~= false and effectiveTarget.unit)
		or anyInRangeUnit
		or (effectiveTarget and effectiveTarget.unit)
		or "player"
	local recommendGroup = (hasGroup and groupSpellName ~= nil and inRangeNeedCount >= (groupThreshold or 2))

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
		singleSpellID = singleSpellID,
		groupSpellName = groupSpellName,
		groupSpellID = groupSpellID,
		groupAnchorUnit = groupAnchorUnit,
		hasGroup = hasGroup,
		nativeSpellIDs = nativeSpellIDs,
		hasClassOverride = duty.hasClassOverride and true or false,
		totalEligible = totalEligible,
		buffedCount = buffedCount,
		missingCount = missingCount,
		expiringCount = expiringCount,
		needCount = needCount,
		inRangeMissingCount = inRangeMissingCount,
		inRangeExpiringCount = inRangeExpiringCount,
		inRangeNeedCount = inRangeNeedCount,
		allOutOfRange = allOutOfRange,
		shortestRemaining = shortestRemaining,
		nextTarget = nextTarget,
		combatTarget = combatTarget,
		effectiveTarget = effectiveTarget,
		combatUnits = combatUnits,
		allTargets = allTargets,
		recommendGroup = recommendGroup,
		reagentCount = reagentCount,
		lowReagent = lowReagent,
		candidates = candidates,
	}
end

-- Cross-duty priority scoring for Smart Auto-Buff:
-- Strictly prioritizes IN-RANGE actionable duties across all classes/groups BEFORE any out-of-range duty,
-- and deprioritizes temporarily backed-off (LoS/failed) targets so pressing Auto-Buff never gets stuck!
local function dutyAutoPriority(duty, eval)
	local nt = eval.nextTarget
	if not nt or eval.needCount == 0 then
		return 0
	end

	-- 1. Self / party-foundation buffs (always on "player", always in range)
	if not nt.present then
		if duty.kind == "PALADIN_AURA" or duty.kind == "RIGHTEOUS_FURY" then
			return 110
		elseif duty.kind == "SHAMAN_TOTEM" or duty.familyID == "BATTLE_SHOUT" then
			return 100
		elseif duty.kind == "PALADIN_SEAL" then
			return 95
		end
	end

	local roleBonus = nt.rolePriority or 1
	-- Slight bonus (+2) for class-wide duties without single-only override so Greater Blessings cast before single overrides
	local scopeBonus = (duty.kind == "CLASS_BUFF" and #(duty.classes or {}) > 0) and 2 or 0

	-- 2. In-range & NOT backed-off targets (Missing > Expiring, both ahead of ANY out-of-range duty!)
	if nt.inRange == true and not nt.backedOff then
		if not nt.present then
			return 80 + roleBonus + scopeBonus
		else
			return 55 + roleBonus + scopeBonus
		end
	end

	-- 3. Unknown range (visible, e.g. combat secret range) & NOT backed-off
	if nt.inRange == nil and not nt.backedOff then
		if not nt.present then
			return 68 + roleBonus + scopeBonus
		else
			return 45 + roleBonus + scopeBonus
		end
	end

	-- 4. In-range targets that were temporarily backed-off (retry once all other in-range duties are done)
	if nt.inRange ~= false and nt.backedOff then
		if not nt.present then
			return 35 + roleBonus
		else
			return 25 + roleBonus
		end
	end

	-- 5. Out-of-range targets (ONLY selected when zero in-range duties need casting anywhere!)
	if not nt.present then
		return 15 + roleBonus
	end
	return 5 + roleBonus
end

-- Score healthy duties for pre-combat staging on LittleBuffBoyAutoBuffBtn when no in-range duty needs an immediate cast:
-- Picks the in-range duty whose buff will expire FIRST during combat (e.g. 30s Seal, 2m Totem/Shout, or shortest-timer party/class buff)
-- and avoids pre-staging an already-active permanent Paladin Aura (which would toggle off if pressed).
local function dutyCombatStagingScore(duty, eval)
	local ct = eval.effectiveTarget or eval.combatTarget
	if not ct then
		return 0
	end
	if duty.kind == "PALADIN_AURA" and eval.missingCount == 0 then
		return 1
	end
	local inRangeBonus = (ct.inRange ~= false) and 10000 or 100
	local rem = eval.shortestRemaining or ct.remaining or 1800
	local timeUrgency = math_max(0, 3600 - math_min(3600, rem))
	local roleBonus = ct.rolePriority or 1
	return inRangeBonus + timeUrgency + roleBonus
end

-- Pick the single highest-priority next action across ALL of a player's active duties
-- (Powers the one-click Smart Buff tile & WoW Keybinding in Bindings.xml)
function Scanner:GetBestAutoBuffAction(duties, roster, options)
	local totalMissing = 0
	local totalExpiring = 0
	local totalInRangeNeed = 0
	local bestEval = nil
	local bestScore = 0
	local bestInRangeEval = nil
	local bestInRangeScore = 0
	local bestCombatStagingEval = nil
	local bestCombatStagingScore = -1
	local fallbackEval = nil
	local allEvals = {}

	for _, duty in ipairs(duties or {}) do
		local eval = self:EvaluateDuty(duty, roster, options)
		if eval.totalEligible > 0 then
			if not fallbackEval then
				fallbackEval = eval
			end
			totalMissing = totalMissing + (eval.missingCount or 0)
			totalExpiring = totalExpiring + (eval.expiringCount or 0)
			totalInRangeNeed = totalInRangeNeed + (eval.inRangeNeedCount or 0)

			local stageScore = dutyCombatStagingScore(duty, eval)
			if stageScore > bestCombatStagingScore then
				bestCombatStagingScore = stageScore
				bestCombatStagingEval = eval
			end

			local autoScore = 0
			if eval.needCount > 0 then
				autoScore = dutyAutoPriority(duty, eval)
				if autoScore > bestScore then
					bestScore = autoScore
					bestEval = eval
				elseif autoScore == bestScore and bestEval then
					local remA = eval.shortestRemaining or 0
					local remB = bestEval.shortestRemaining or 0
					if remA < remB then
						bestEval = eval
					end
				end

				if eval.inRangeNeedCount > 0 then
					if autoScore > bestInRangeScore then
						bestInRangeScore = autoScore
						bestInRangeEval = eval
					elseif autoScore == bestInRangeScore and bestInRangeEval then
						local remA = eval.shortestRemaining or 0
						local remB = bestInRangeEval.shortestRemaining or 0
						if remA < remB then
							bestInRangeEval = eval
						end
					end
				end
			end

			table_insert(allEvals, {
				duty = duty,
				eval = eval,
				autoScore = autoScore,
				stageScore = stageScore,
			})
		end
	end

	-- Sort all duties by in-combat priority so LittleBuffBoyAutoBuffBtn can cycle through ALL buffs & targets in combat!
	table_sort(allEvals, function(a, b)
		local aNeed = (a.eval.inRangeNeedCount or 0) > 0
		local bNeed = (b.eval.inRangeNeedCount or 0) > 0
		if aNeed ~= bNeed then
			return aNeed and (not bNeed)
		end
		if a.autoScore ~= b.autoScore then
			return a.autoScore > b.autoScore
		end
		if a.stageScore ~= b.stageScore then
			return a.stageScore > b.stageScore
		end
		return (a.eval.shortestRemaining or 9999) < (b.eval.shortestRemaining or 9999)
	end)

	local function isSelfOnlyDuty(duty)
		local k = duty.kind
		return k == "PALADIN_AURA" or k == "SHAMAN_TOTEM" or k == "RIGHTEOUS_FURY" or k == "PALADIN_SEAL" or duty.familyID == "BATTLE_SHOUT"
	end

	-- Build two-pass multi-duty Left-Click combat_queue (`spell|unit|selfFlag;...`):
	-- Pass 1: Every currently missing/expiring buff+target across ALL duties (so Click 1 = Righteous Fury, Click 2 = Wisdom on party1, Click 3 = Wisdom on party2, etc.)
	-- Pass 2: Remaining healthy duties+targets (so even if you enter combat healthy and buffs drop later, cycling still covers everyone!)
	local queueEntries = {}
	local seenQueue = {}
	local function addQueueEntry(spellName, unitToken, selfFlag)
		if not spellName or spellName == "" or not unitToken or unitToken == "" then
			return
		end
		-- Sanitize delimiters
		local cleanSpell = spellName:gsub("[|;]", "")
		local key = cleanSpell .. "|" .. unitToken
		if not seenQueue[key] then
			seenQueue[key] = true
			table_insert(queueEntries, cleanSpell .. "|" .. unitToken .. "|" .. (selfFlag and "1" or "0"))
		end
	end

	for pass = 1, 2 do
		for _, item in ipairs(allEvals) do
			local duty = item.duty
			local eval = item.eval
			local skipActiveAura = (duty.kind == "PALADIN_AURA" and eval.missingCount == 0 and #allEvals > 1)
			if not skipActiveAura and eval.singleSpellName and eval.singleSpellName ~= "" then
				if isSelfOnlyDuty(duty) then
					local needsNow = (eval.needCount or 0) > 0
					if (pass == 1 and needsNow) or (pass == 2 and not needsNow) then
						addQueueEntry(eval.singleSpellName, "player", true)
					end
				else
					for _, t in ipairs(eval.allTargets or {}) do
						local needsNow = t.needsCast and (t.inRange ~= false)
						if (pass == 1 and needsNow) or (pass == 2 and not needsNow) then
							addQueueEntry(eval.singleSpellName, t.unit, false)
						end
					end
				end
			end
		end
	end
	local combatQueue = table.concat(queueEntries, ";")

	-- Build multi-duty Right-Click combat_group_queue (`spell|u1,u2,...|selfFlag;...`):
	-- One click per self-buff / per class (for Greater Blessings) / per subgroup (for Prayers/Gifts/Brilliance)!
	local groupEntries = {}
	local seenGroup = {}
	local function addGroupEntry(spellName, unitListStr, selfFlag)
		if not spellName or spellName == "" or not unitListStr or unitListStr == "" then
			return
		end
		local cleanSpell = spellName:gsub("[|;]", "")
		local key = cleanSpell .. "|" .. unitListStr
		if not seenGroup[key] then
			seenGroup[key] = true
			table_insert(groupEntries, cleanSpell .. "|" .. unitListStr .. "|" .. (selfFlag and "1" or "0"))
		end
	end

	for _, item in ipairs(allEvals) do
		local duty = item.duty
		local eval = item.eval
		local skipActiveAura = (duty.kind == "PALADIN_AURA" and eval.missingCount == 0 and #allEvals > 1)
		if not skipActiveAura then
			if isSelfOnlyDuty(duty) then
				addGroupEntry(eval.singleSpellName, "player", true)
			elseif eval.hasGroup and eval.groupSpellName and eval.groupSpellName ~= "" then
				if duty.kind == "CLASS_BUFF" then
					local byClsOrder = {}
					local byClsUnits = {}
					for _, t in ipairs(eval.allTargets or {}) do
						local cls = (t.member and t.member.class) or "OTHER"
						if not byClsUnits[cls] then
							byClsUnits[cls] = {}
							table_insert(byClsOrder, cls)
						end
						table_insert(byClsUnits[cls], t.unit)
					end
					for _, cls in ipairs(byClsOrder) do
						addGroupEntry(eval.groupSpellName, table.concat(byClsUnits[cls], ","), false)
					end
				elseif duty.kind == "GROUP_BUFF" then
					local bySubOrder = {}
					local bySubUnits = {}
					for _, t in ipairs(eval.allTargets or {}) do
						local sg = (t.member and t.member.subgroup) or 1
						if not bySubUnits[sg] then
							bySubUnits[sg] = {}
							table_insert(bySubOrder, sg)
						end
						table_insert(bySubUnits[sg], t.unit)
					end
					for _, sg in ipairs(bySubOrder) do
						addGroupEntry(eval.groupSpellName, table.concat(bySubUnits[sg], ","), false)
					end
				else
					addGroupEntry(eval.groupSpellName, eval.combatUnits or eval.groupAnchorUnit or "player", false)
				end
			else
				addGroupEntry(eval.singleSpellName, eval.combatUnits or eval.groupAnchorUnit or "player", false)
			end
		end
	end
	local combatGroupQueue = table.concat(groupEntries, ";")

	-- Prefer an actionable in-range duty first; if all in-range duties are currently healthy (even if an OOR player is missing),
	-- pre-stage the button to `bestCombatStagingEval` (the in-range duty whose buff will expire FIRST during combat!).
	local chosen = bestInRangeEval or bestCombatStagingEval or bestEval or fallbackEval
	local targetUnit = "player"
	local groupUnit = "player"
	local combatUnits = "player"
	local targetName = nil
	if chosen then
		if not isSelfOnlyDuty(chosen.duty) then
			local et = chosen.effectiveTarget or chosen.nextTarget or chosen.combatTarget
			targetUnit = (et and et.unit) or "player"
			groupUnit = chosen.groupAnchorUnit or targetUnit
			combatUnits = chosen.combatUnits or targetUnit
			targetName = et and et.name or nil
		end
	end

	local totalNeed = totalMissing + totalExpiring
	return {
		hasAction = bestEval ~= nil,
		allHealthy = (totalNeed == 0),
		allOutOfRange = (totalNeed > 0 and totalInRangeNeed == 0),
		totalMissing = totalMissing,
		totalExpiring = totalExpiring,
		totalInRangeNeed = totalInRangeNeed,
		nextDuty = chosen and chosen.duty or nil,
		nextEval = chosen,
		unit = targetUnit,
		groupUnit = groupUnit,
		combatUnits = combatUnits,
		combatQueue = combatQueue,
		combatGroupQueue = combatGroupQueue,
		targetName = targetName,
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
