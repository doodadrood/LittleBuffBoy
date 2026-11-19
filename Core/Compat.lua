local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Compat = {}
LBB.Compat = Compat

local type = type
local pcall = pcall
local tostring = tostring
local select = select
local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert
local table_wipe = table.wipe or function(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

local function isValidSpellArg(spell)
	local t = type(spell)
	if t == "number" then
		return spell > 0
	elseif t == "string" then
		return spell ~= ""
	end
	return false
end

function Compat.IsSecret(val)
	local fn = _G.issecretvalue
	if fn then
		local ok, res = pcall(fn, val)
		if ok and res then
			return true
		end
	end
	return false
end

function Compat.SafeRead(val, default)
	if val == nil or Compat.IsSecret(val) then
		return default
	end
	return val
end

function Compat.SafeCall(fn, default, ...)
	if type(fn) ~= "function" then
		return default
	end
	local ok, v = pcall(fn, ...)
	if not ok or v == nil or Compat.IsSecret(v) then
		return default
	end
	return v
end

function Compat.GetTime()
	if _G.GetTime then
		return _G.GetTime()
	end
	return 0
end

function Compat.InCombat()
	return Compat.SafeCall(_G.InCombatLockdown, false) and true or false
end

-- Spells (Modern C_Spell / C_SpellBook APIs only)

function Compat.GetSpellInfo(spell)
	if not isValidSpellArg(spell) then
		return nil
	end
	if not (_G.C_Spell and _G.C_Spell.GetSpellInfo) then
		return nil
	end
	local ok, info = pcall(_G.C_Spell.GetSpellInfo, spell)
	if not ok or type(info) ~= "table" or Compat.IsSecret(info) then
		return nil
	end
	local name = Compat.SafeRead(info.name, nil)
	if not name then
		return nil
	end
	return {
		name = name,
		iconID = Compat.SafeRead(info.iconID, nil),
		originalIconID = Compat.SafeRead(info.originalIconID, nil),
		castTime = Compat.SafeRead(info.castTime, 0),
		minRange = Compat.SafeRead(info.minRange, 0),
		maxRange = Compat.SafeRead(info.maxRange, 0),
		spellID = Compat.SafeRead(info.spellID, type(spell) == "number" and spell or nil),
	}
end

function Compat.RequestLoadSpellData(spellID)
	if type(spellID) ~= "number" or spellID <= 0 then
		return false
	end
	if _G.C_Spell and _G.C_Spell.RequestLoadSpellData then
		local ok = pcall(_G.C_Spell.RequestLoadSpellData, spellID)
		return ok and true or false
	end
	return false
end

function Compat.IsSpellKnown(spellID, isPet)
	if type(spellID) ~= "number" or spellID <= 0 then
		return false
	end
	if not (_G.C_SpellBook and _G.C_SpellBook.IsSpellKnown) then
		return false
	end
	local bank = nil
	if _G.Enum and _G.Enum.SpellBookSpellBank then
		bank = isPet and _G.Enum.SpellBookSpellBank.Pet or _G.Enum.SpellBookSpellBank.Player
	end
	local ok, known
	if bank ~= nil then
		ok, known = pcall(_G.C_SpellBook.IsSpellKnown, spellID, bank)
	else
		ok, known = pcall(_G.C_SpellBook.IsSpellKnown, spellID)
	end
	if not ok or Compat.IsSecret(known) then
		return false
	end
	return known and true or false
end

function Compat.IsSpellInRange(spell, unit)
	if not isValidSpellArg(spell) or type(unit) ~= "string" then
		return nil
	end
	if not (_G.C_Spell and _G.C_Spell.IsSpellInRange) then
		return nil
	end
	local ok, res = pcall(_G.C_Spell.IsSpellInRange, spell, unit)
	if not ok or Compat.IsSecret(res) then
		return nil
	end
	if res == true or res == 1 then
		return true
	elseif res == false or res == 0 then
		return false
	end
	return nil
end

function Compat.GetSpellCooldown(spell)
	if not isValidSpellArg(spell) then
		return nil
	end
	if not (_G.C_Spell and _G.C_Spell.GetSpellCooldown) then
		return nil
	end
	local ok, cd = pcall(_G.C_Spell.GetSpellCooldown, spell)
	if not ok or type(cd) ~= "table" or Compat.IsSecret(cd) then
		return nil
	end
	return {
		startTime = Compat.SafeRead(cd.startTime, 0),
		duration = Compat.SafeRead(cd.duration, 0),
		isEnabled = Compat.SafeRead(cd.isEnabled, true),
		modRate = Compat.SafeRead(cd.modRate, 1),
	}
end

-- Items

function Compat.GetItemCount(itemID, includeBank)
	if type(itemID) ~= "number" or itemID <= 0 then
		return 0
	end
	if _G.C_Item and _G.C_Item.GetItemCount then
		local ok, count = pcall(_G.C_Item.GetItemCount, itemID, includeBank)
		if ok and not Compat.IsSecret(count) and type(count) == "number" then
			return count
		end
	end
	return 0
end

-- Auras (Modern C_UnitAuras + Midnight Secret-Value safety)

function Compat.GetAuraDataByIndex(unit, index, filter)
	if type(unit) ~= "string" or type(index) ~= "number" then
		return nil, false
	end
	if not (_G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex) then
		return nil, false
	end
	local ok, raw = pcall(_G.C_UnitAuras.GetAuraDataByIndex, unit, index, filter or "HELPFUL")
	if not ok then
		return nil, true
	end
	if Compat.IsSecret(raw) then
		return nil, true
	end
	if raw == nil then
		return nil, false
	end
	if type(raw) ~= "table" then
		return nil, true
	end

	local hasSecret = false
	local function readField(fieldName, default)
		local okField, val = pcall(function()
			return raw[fieldName]
		end)
		if not okField or Compat.IsSecret(val) then
			hasSecret = true
			return default
		end
		if val == nil then
			return default
		end
		return val
	end

	local name = readField("name", nil)
	local spellId = readField("spellId", nil)
	local duration = readField("duration", nil)
	local expirationTime = readField("expirationTime", nil)
	local applications = readField("applications", 0)
	local icon = readField("icon", nil)
	local sourceUnit = readField("sourceUnit", nil)
	local dispelName = readField("dispelName", nil)
	local auraInstanceID = readField("auraInstanceID", nil)

	return {
		name = name,
		spellId = spellId,
		duration = duration,
		expirationTime = expirationTime,
		applications = applications,
		icon = icon,
		sourceUnit = sourceUnit,
		dispelName = dispelName,
		auraInstanceID = auraInstanceID,
		hasSecretFields = hasSecret,
		isCompletelyHidden = (name == nil and spellId == nil and hasSecret),
	}, false
end

-- Minimap Tracking (Modern C_Minimap)

function Compat.GetNumTrackingTypes()
	if _G.C_Minimap and _G.C_Minimap.GetNumTrackingTypes then
		local ok, n = pcall(_G.C_Minimap.GetNumTrackingTypes)
		if ok and type(n) == "number" and not Compat.IsSecret(n) then
			return n
		end
	end
	return 0
end

function Compat.GetTrackingInfo(index)
	if type(index) ~= "number" or index < 1 then
		return nil
	end
	if not (_G.C_Minimap and _G.C_Minimap.GetTrackingInfo) then
		return nil
	end
	local ok, a, b, c, d, e, f = pcall(_G.C_Minimap.GetTrackingInfo, index)
	if not ok or a == nil or Compat.IsSecret(a) then
		return nil
	end
	if type(a) == "table" then
		local name = Compat.SafeRead(a.name, nil)
		if not name then
			return nil
		end
		return {
			index = index,
			name = name,
			texture = Compat.SafeRead(a.texture, nil),
			active = Compat.SafeRead(a.active, false) and true or false,
			category = Compat.SafeRead(a.type or a.category, "other"),
			subType = Compat.SafeRead(a.subType, nil),
			spellID = Compat.SafeRead(a.spellID, nil),
		}
	end
	return {
		index = index,
		name = Compat.SafeRead(a, nil),
		texture = Compat.SafeRead(b, nil),
		active = Compat.SafeRead(c, false) and true or false,
		category = Compat.SafeRead(d, "other"),
		subType = Compat.SafeRead(e, nil),
		spellID = Compat.SafeRead(f, nil),
	}
end

function Compat.SetTracking(index, enabled)
	if type(index) ~= "number" or index < 1 then
		return false
	end
	if _G.C_Minimap and _G.C_Minimap.SetTracking then
		local ok = pcall(_G.C_Minimap.SetTracking, index, enabled and true or false)
		return ok and true or false
	end
	return false
end

-- Chat & Addon Comms (Modern C_ChatInfo)

function Compat.RegisterAddonMessagePrefix(prefix)
	if type(prefix) ~= "string" or prefix == "" then
		return false
	end
	if _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix then
		local ok, res = pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, prefix)
		return ok and (res ~= false) or false
	end
	return false
end

function Compat.SendAddonMessage(prefix, msg, chatType, target)
	if type(prefix) ~= "string" or type(msg) ~= "string" then
		return false
	end
	if _G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage then
		local ok, res
		if target then
			ok, res = pcall(_G.C_ChatInfo.SendAddonMessage, prefix, msg, chatType, target)
		else
			ok, res = pcall(_G.C_ChatInfo.SendAddonMessage, prefix, msg, chatType)
		end
		return ok and (res ~= false) or false
	end
	return false
end

function Compat.SendChatMessage(msg, chatType, language, target)
	if type(msg) ~= "string" or msg == "" then
		return false
	end
	if _G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage then
		local ok = pcall(_G.C_ChatInfo.SendChatMessage, msg, chatType, language, target)
		return ok and true or false
	elseif _G.SendChatMessage then
		local ok = pcall(_G.SendChatMessage, msg, chatType, language, target)
		return ok and true or false
	end
	return false
end

-- AddOn queries (Modern C_AddOns)

function Compat.IsAddOnLoaded(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	if _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded then
		local ok, loaded = pcall(_G.C_AddOns.IsAddOnLoaded, name)
		return ok and loaded and true or false
	end
	return false
end

function Compat.GetAddOnMetadata(name, field)
	if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
		local ok, val = pcall(_G.C_AddOns.GetAddOnMetadata, name, field)
		if ok then
			return val
		end
	end
	return nil
end

-- Unit helpers (Forever surname + Midnight secret safe)

function Compat.UnitExists(unit)
	return Compat.SafeCall(_G.UnitExists, false, unit) and true or false
end

function Compat.UnitIsDeadOrGhost(unit)
	return Compat.SafeCall(_G.UnitIsDeadOrGhost, false, unit) and true or false
end

function Compat.UnitIsConnected(unit)
	return Compat.SafeCall(_G.UnitIsConnected, true, unit) and true or false
end

function Compat.UnitIsVisible(unit)
	return Compat.SafeCall(_G.UnitIsVisible, true, unit) and true or false
end

function Compat.UnitAffectingCombat(unit)
	return Compat.SafeCall(_G.UnitAffectingCombat, false, unit) and true or false
end

function Compat.UnitGUID(unit)
	return Compat.SafeCall(_G.UnitGUID, nil, unit)
end

function Compat.UnitClass(unit)
	if not _G.UnitClass then
		return nil, nil
	end
	local ok, localized, token = pcall(_G.UnitClass, unit)
	if not ok or Compat.IsSecret(token) then
		return nil, nil
	end
	return Compat.SafeRead(localized, token), token
end

function Compat.UnitGroupRolesAssigned(unit)
	return Compat.SafeCall(_G.UnitGroupRolesAssigned, "NONE", unit)
end

function Compat.GetRealmName()
	local realm = Compat.SafeCall(_G.GetNormalizedRealmName, nil)
	if not realm or realm == "" then
		realm = Compat.SafeCall(_G.GetRealmName, "")
		if realm then
			realm = realm:gsub("%s+", "")
		end
	end
	return realm or ""
end

function Compat.NormalizeName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local realm = Compat.GetRealmName()
	if realm ~= "" then
		local suffix = "-" .. realm
		if name:sub(-#suffix) == suffix then
			return name:sub(1, #name - #suffix)
		end
	end
	return name
end

function Compat.GetFullUnitName(unit)
	unit = unit or "player"
	local name
	if _G.GetUnitName then
		name = Compat.SafeCall(_G.GetUnitName, nil, unit, true)
	end
	if not name and _G.UnitName then
		local ok, n, r = pcall(_G.UnitName, unit)
		if ok and not Compat.IsSecret(n) and n then
			if r and not Compat.IsSecret(r) and r ~= "" then
				name = n .. "-" .. r
			else
				name = n
			end
		end
	end
	return Compat.NormalizeName(name)
end

function Compat.GetWeaponEnchantInfo()
	if not _G.GetWeaponEnchantInfo then
		return false, 0, 0, nil, false, 0, 0, nil
	end
	local ok, hasMain, mainExp, mainCharges, mainID, hasOff, offExp, offCharges, offID = pcall(_G.GetWeaponEnchantInfo)
	if not ok then
		return false, 0, 0, nil, false, 0, 0, nil
	end
	return Compat.SafeRead(hasMain, false),
		Compat.SafeRead(mainExp, 0),
		Compat.SafeRead(mainCharges, 0),
		Compat.SafeRead(mainID, nil),
		Compat.SafeRead(hasOff, false),
		Compat.SafeRead(offExp, 0),
		Compat.SafeRead(offCharges, 0),
		Compat.SafeRead(offID, nil)
end

function Compat.GetGroupChannel()
	local inInstanceGroup = _G.IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and Compat.SafeCall(_G.IsInGroup, false, _G.LE_PARTY_CATEGORY_INSTANCE)
	if inInstanceGroup then
		return "INSTANCE_CHAT"
	end
	if _G.IsInRaid and Compat.SafeCall(_G.IsInRaid, false) then
		return "RAID"
	end
	if _G.IsInGroup and Compat.SafeCall(_G.IsInGroup, false) then
		return "PARTY"
	end
	if _G.GetNumGroupMembers and Compat.SafeCall(_G.GetNumGroupMembers, 0) > 0 then
		return "PARTY"
	end
	return nil
end

-- Combat Lockdown Queue (SecureActionButton safety)

local combatOrder = {}
local combatCallbacks = {}
local combatAttributes = {}

function Compat.ResetCombatQueue()
	table_wipe(combatOrder)
	table_wipe(combatCallbacks)
	table_wipe(combatAttributes)
end

function Compat.RunOutOfCombat(key, fn)
	if type(fn) ~= "function" then
		return false
	end
	if not Compat.InCombat() then
		fn()
		return true
	end
	local k = tostring(key or fn)
	if not combatCallbacks[k] then
		table_insert(combatOrder, { kind = "fn", key = k })
	end
	combatCallbacks[k] = fn
	return false
end

function Compat.SetSecureAttribute(frame, attr, value)
	if not frame or type(frame.SetAttribute) ~= "function" or type(attr) ~= "string" then
		return false
	end
	if not Compat.InCombat() then
		frame:SetAttribute(attr, value)
		return true
	end
	local k = tostring(frame) .. "::" .. attr
	if not combatAttributes[k] then
		table_insert(combatOrder, { kind = "attr", key = k })
	end
	combatAttributes[k] = {
		frame = frame,
		attr = attr,
		value = value,
	}
	return false
end

function Compat.GetPendingCombatQueueCount()
	return #combatOrder
end

function Compat.FlushCombatQueue()
	if Compat.InCombat() then
		return 0
	end
	if #combatOrder == 0 then
		return 0
	end
	local items = {}
	for i = 1, #combatOrder do
		items[i] = combatOrder[i]
	end
	local cbs = {}
	for k, v in pairs(combatCallbacks) do
		cbs[k] = v
	end
	local attrs = {}
	for k, v in pairs(combatAttributes) do
		attrs[k] = v
	end
	Compat.ResetCombatQueue()

	local executed = 0
	for i = 1, #items do
		local entry = items[i]
		if entry.kind == "attr" then
			local item = attrs[entry.key]
			if item and item.frame and item.frame.SetAttribute then
				item.frame:SetAttribute(item.attr, item.value)
				executed = executed + 1
			end
		elseif entry.kind == "fn" then
			local fn = cbs[entry.key]
			if fn then
				fn()
				executed = executed + 1
			end
		end
	end
	return executed
end

-- Top-level convenience aliases
LBB.IsSecret = Compat.IsSecret
LBB.SafeRead = Compat.SafeRead
LBB.SafeCall = Compat.SafeCall
LBB.InCombat = Compat.InCombat
LBB.RunOutOfCombat = Compat.RunOutOfCombat
LBB.SetSecureAttribute = Compat.SetSecureAttribute
