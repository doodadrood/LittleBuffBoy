-- Full WoW: Forever (16001 / Midnight API) Mock Environment for Busted / Lua 5.1 Unit Tests
-- Intentionally omits removed legacy globals (GetSpellInfo, UnitBuff, UnitDebuff) to prove strict modern API usage.

local Mock = {}

local pairs = pairs
local ipairs = ipairs
local type = type
local setmetatable = setmetatable
local table_insert = table.insert

local SECRET_SENTINEL = {}

-- Create a Midnight "secret value" proxy that throws if addon code compares, indexes, or does arithmetic on it
function Mock.MakeSecret(label)
	local obj = { _lbb_secret_label = label or "secret" }
	SECRET_SENTINEL[obj] = true
	return setmetatable(obj, {
		__index = function()
			error("ADDON_ACTION_FORBIDDEN: attempted to index a Midnight secret value (" .. tostring(label) .. ")")
		end,
		__add = function()
			error("ADDON_ACTION_FORBIDDEN: arithmetic on a Midnight secret value (" .. tostring(label) .. ")")
		end,
		__sub = function()
			error("ADDON_ACTION_FORBIDDEN: arithmetic on a Midnight secret value (" .. tostring(label) .. ")")
		end,
		__lt = function()
			error("ADDON_ACTION_FORBIDDEN: comparison on a Midnight secret value (" .. tostring(label) .. ")")
		end,
		__le = function()
			error("ADDON_ACTION_FORBIDDEN: comparison on a Midnight secret value (" .. tostring(label) .. ")")
		end,
		__tostring = function()
			return "<secret:" .. tostring(label) .. ">"
		end,
	})
end

function Mock.IsSecret(val)
	return SECRET_SENTINEL[val] == true
end

function Mock.New()
	local state = {
		time = 1000,
		inCombat = false,
		realm = "ForeverRealm",
		inRaid = false,
		inGroup = false,
		inInstanceGroup = false,
		knownSpells = {},
		spellBookExtras = {}, -- optional list of { spellID, name, iconID } exposed via C_SpellBook skill lines
		spellInfo = {},
		nativeAuraEnabled = false,
		nativeAuraSlots = {},
		requestedSpellLoads = {},
		spellInRange = {}, -- [unit] = { [spell] = true/false/nil }
		itemCounts = {},
		loadedAddons = {},
		registeredPrefixes = {},
		sentAddonMessages = {},
		sentChatMessages = {},
		tracking = {}, -- list of { name, texture, active, type, spellID }
		trackingTableMode = true,
		units = {},    -- [unitToken] = { name, class, subgroup, role, guid, online, dead, visible, inCombat, isLeader, isAssist, auras = {}, auraBlocked = false }
		raidOrder = {},
		talents = {},  -- [talentName] = rank (exposed via C_ClassTalents + C_Traits!)
		weaponEnchants = { false, 0, 0, nil, false, 0, 0, nil },
		frames = {},
		hooks = {},
	}

	local env = { state = state }

	-- Helper setters on env
	function env:SetTime(t)
		state.time = t
	end

	function env:AdvanceTime(dt)
		state.time = state.time + dt
	end

	function env:SetCombat(inCombat)
		state.inCombat = inCombat and true or false
	end

	function env:SetAddonLoaded(name, loaded)
		state.loadedAddons[name] = loaded and true or false
	end

	function env:SetKnownSpell(spellID, name, iconID)
		state.knownSpells[spellID] = true
		if name ~= false then
			state.spellInfo[spellID] = {
				name = name or ("Spell_" .. tostring(spellID)),
				iconID = iconID or 134400,
				originalIconID = iconID or 134400,
				castTime = 0,
				minRange = 0,
				maxRange = 30,
				spellID = spellID,
			}
		end
	end

	function env:SetSpellInfo(spellID, name, iconID)
		state.spellInfo[spellID] = {
			name = name,
			iconID = iconID or 134400,
			originalIconID = iconID or 134400,
			castTime = 0,
			minRange = 0,
			maxRange = 30,
			spellID = spellID,
		}
	end

	function env:SetSpellBookExtra(spellID, name, iconID)
		table_insert(state.spellBookExtras, { spellID = spellID, name = name, iconID = iconID })
		env:SetKnownSpell(spellID, name, iconID)
	end

	function env:EnableNativeAuraMock(enabled)
		state.nativeAuraEnabled = enabled and true or false
	end

	function env:SetTalent(name, rank)
		state.talents[name] = rank
	end

	function env:SetItemCount(itemID, count)
		state.itemCounts[itemID] = count
	end

	function env:SetSpellInRange(unit, spell, inRange)
		state.spellInRange[unit] = state.spellInRange[unit] or {}
		state.spellInRange[unit][spell] = inRange
	end

	function env:SetTrackingList(list, tableMode)
		state.tracking = list or {}
		if tableMode ~= nil then
			state.trackingTableMode = tableMode
		end
	end

	function env:SetUnit(unit, info)
		state.units[unit] = {
			name = info.name,
			class = info.class or "PRIEST",
			subgroup = info.subgroup or 1,
			role = info.role or "NONE",
			guid = info.guid or ("GUID-" .. (info.name or unit)),
			online = (info.online ~= false),
			dead = info.dead and true or false,
			visible = (info.visible ~= false),
			inPhase = (info.inPhase ~= false),
			charmed = info.charmed and true or false,
			hostile = info.hostile and true or false,
			unitInRange = info.unitInRange,
			inCombat = info.inCombat and true or false,
			isLeader = info.isLeader and true or false,
			isAssist = info.isAssist and true or false,
			auras = info.auras or {},
			auraBlocked = info.auraBlocked and true or false,
		}
	end

	function env:SetGroup(mode, unitList)
		state.inRaid = (mode == "RAID")
		state.inGroup = (mode == "RAID" or mode == "PARTY" or mode == "INSTANCE")
		state.inInstanceGroup = (mode == "INSTANCE")
		state.raidOrder = unitList or {}
	end

	function env:SetWeaponEnchant(hasMain, mainMs, hasOff, offMs)
		state.weaponEnchants = { hasMain and true or false, mainMs or 0, 0, nil, hasOff and true or false, offMs or 0, 0, nil }
	end

	function env:CreateMockFrame(frameType, name, parent, template)
		local isSecure = type(template) == "string" and template:find("SecureActionButtonTemplate", 1, true) ~= nil
		local frame = {
			_type = frameType,
			_name = name,
			_parent = parent,
			_template = template,
			_isSecure = isSecure,
			_attrs = {},
			_events = {},
			_scripts = {},
			_shown = true,
			_points = {},
			_children = {},
			_alpha = 1,
			_width = 32,
			_height = 32,
			SetAttribute = function(self, k, v)
				if self._isSecure and state.inCombat and not state.inRestrictedSnippet then
					error("ADDON_ACTION_BLOCKED: SecureActionButtonTemplate:SetAttribute(" .. tostring(k) .. ") called during InCombatLockdown()")
				end
				self._attrs[k] = v
			end,
			GetAttribute = function(self, k)
				return self._attrs[k]
			end,
			Click = function(self, button, down)
				button = button or "LeftButton"
				if self._preClickSnippet then
					state.inRestrictedSnippet = true
					local ok, err = pcall(self._preClickSnippet, self, button, down)
					state.inRestrictedSnippet = false
					if not ok then
						error(err)
					end
				end
				if self._scripts["OnClick"] then
					self._scripts["OnClick"](self, button, down)
				end
				if self._scripts["PostClick"] then
					self._scripts["PostClick"](self, button, down)
				end
			end,
			RegisterEvent = function(self, ev)
				if ev == "COMBAT_LOG_EVENT_UNFILTERED" then
					error("ADDON_ACTION_FORBIDDEN: COMBAT_LOG_EVENT_UNFILTERED is forbidden on WoW: Forever")
				end
				self._events[ev] = true
			end,
			UnregisterEvent = function(self, ev)
				self._events[ev] = nil
			end,
			SetScript = function(self, s, fn)
				self._scripts[s] = fn
			end,
			GetScript = function(self, s)
				return self._scripts[s]
			end,
			HookScript = function(self, s, fn)
				local prev = self._scripts[s]
				self._scripts[s] = function(...)
					if prev then prev(...) end
					fn(...)
				end
			end,
			Show = function(self) self._shown = true end,
			Hide = function(self) self._shown = false end,
			SetShown = function(self, v) self._shown = v and true or false end,
			IsShown = function(self) return self._shown end,
			IsVisible = function(self) return self._shown end,
			SetSize = function(self, w, h) self._width, self._height = w, h end,
			SetWidth = function(self, w) self._width = w end,
			SetHeight = function(self, h) self._height = h end,
			GetWidth = function(self) return self._width end,
			GetHeight = function(self) return self._height end,
			SetPoint = function(self, ...) table_insert(self._points, { ... }) end,
			ClearAllPoints = function(self) self._points = {} end,
			SetAllPoints = function(self, target) self._points = { { "ALL", target } } end,
			GetPoint = function(self) return "CENTER", _G.UIParent, "CENTER", 0, 0 end,
			SetFrameStrata = function() end,
			SetFrameLevel = function() end,
			GetFrameLevel = function() return 1 end,
			SetScale = function(self, s) self._scale = s end,
			SetAlpha = function(self, a) self._alpha = a end,
			EnableMouse = function() end,
			EnableMouseWheel = function() end,
			SetMovable = function() end,
			SetClampedToScreen = function() end,
			RegisterForDrag = function() end,
			RegisterForClicks = function() end,
			StartMoving = function() end,
			StopMovingOrSizing = function() end,
			SetText = function(self, t) self._text = t end,
			GetText = function(self) return self._text end,
			SetTexture = function(self, t) self._texture = t end,
			SetTexCoord = function() end,
			SetColorTexture = function(self, r, g, b, a) self._color = { r, g, b, a } end,
			SetVertexColor = function(self, r, g, b, a) self._vcolor = { r, g, b, a } end,
			SetDesaturated = function(self, d) self._desaturated = d end,
			SetTextColor = function(self, r, g, b, a) self._tcolor = { r, g, b, a } end,
			SetFont = function() end,
			SetJustifyH = function() end,
			SetJustifyV = function() end,
			SetWordWrap = function() end,
			SetNormalFontObject = function() end,
			SetHighlightTexture = function() end,
			SetPushedTexture = function() end,
			GetName = function(self) return self._name end,
			GetParent = function(self) return self._parent end,
			SetParent = function(self, p) self._parent = p end,
			GetCenter = function() return 100, 100 end,
			GetEffectiveScale = function() return 1 end,
			SetMask = function(self, m) self._mask = m end,
			IsForbidden = function() return false end,
			CreateTexture = function(self)
				return env:CreateMockFrame("Texture", nil, self)
			end,
			CreateFontString = function(self)
				return env:CreateMockFrame("FontString", nil, self)
			end,
		}
		if name then
			_G[name] = frame
		end
		table_insert(state.frames, frame)
		return frame
	end

	-- Install all WoW: Forever 16001 / Midnight globals
	function env:Install()
		-- Ensure removed Classic globals are absent!
		_G.GetSpellInfo = nil
		_G.UnitBuff = nil
		_G.UnitDebuff = nil
		_G.GetNumTalentTabs = nil
		_G.GetNumTalents = nil
		_G.GetTalentInfo = nil
		_G.LittleBuffBoy = nil
		if not state.preserveSavedVars then
			_G.LittleBuffBoyDB = nil
			_G.LittleBuffBoyCharDB = nil
		end
		_G.LibStub = nil

		_G.issecretvalue = Mock.IsSecret
		_G.GetTime = function() return state.time end
		_G.InCombatLockdown = function() return state.inCombat end
		_G.PlayerInCombat = function() return state.inCombat end
		_G.newtable = function() return {} end
		_G.SecureCmdOptionParse = function(condStr)
			if type(condStr) ~= "string" then
				return nil
			end
			for clauses, result in condStr:gmatch("%[([^%]]+)%]%s*([^;]+)") do
				result = result:match("^%s*(.-)%s*$")
				local unit = clauses:match("@([%w_]+)") or "target"
				local u = state.units[unit]
				local ok = (u ~= nil and u.online ~= false)
				if ok and clauses:find("help", 1, true) then
					ok = (not u.charmed and not u.hostile)
				end
				if ok and clauses:find("nodead", 1, true) then
					ok = (not u.dead)
				end
				if ok then
					return result
				end
			end
			return nil
		end
		_G.SecureHandlerWrapScript = function(frame, script, _, preBody)
			if frame and script == "OnClick" and type(preBody) == "string" then
				-- Mirror Blizzard's RestrictedExecution.lua static checks!
				if preBody:find("{", 1, true) or preBody:find("}", 1, true) then
					error("RestrictedExecution.lua: Direct table creation is not permitted")
				end
				if preBody:find("%f[%a]function%f[%A]") then
					error("RestrictedExecution.lua: Function definitions are not permitted")
				end
				local chunk, err = loadstring("local self, button, down = ...; " .. preBody)
				if not chunk then
					error("Invalid SecureHandler snippet: " .. tostring(err))
				end
				local restrictedEnv = {
					PlayerInCombat = _G.PlayerInCombat,
					SecureCmdOptionParse = _G.SecureCmdOptionParse,
					strlen = string.len,
					strfind = string.find,
					strsub = string.sub,
					strmatch = string.match,
					gmatch = string.gmatch,
					gsub = string.gsub,
					tonumber = tonumber,
					tostring = tostring,
					type = type,
					select = select,
					newtable = _G.newtable,
				}
				setfenv(chunk, restrictedEnv)
				frame._preClickSnippet = chunk
			end
		end
		_G.GetNormalizedRealmName = function() return state.realm end
		_G.GetRealmName = function() return state.realm end
		_G.LE_PARTY_CATEGORY_INSTANCE = 2
		_G.Enum = {
			SpellBookSpellBank = { Player = 0, Pet = 1 },
		}

		_G.C_Spell = {
			GetSpellInfo = function(spell)
				if type(spell) == "number" then
					return state.spellInfo[spell]
				elseif type(spell) == "string" then
					for _, info in pairs(state.spellInfo) do
						if info.name == spell then
							return info
						end
					end
				end
				return nil
			end,
			RequestLoadSpellData = function(spellID)
				state.requestedSpellLoads[spellID] = true
			end,
			IsSpellInRange = function(spell, unit)
				local uMap = state.spellInRange[unit]
				if uMap and uMap[spell] ~= nil then
					if uMap[spell] == "NIL" then
						return nil
					end
					return uMap[spell]
				end
				return true
			end,
			GetSpellCooldown = function()
				return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
			end,
		}

		_G.C_SpellBook = {
			IsSpellKnown = function(spellID)
				return state.knownSpells[spellID] == true
			end,
			GetNumSpellBookSkillLines = function()
				return #state.spellBookExtras > 0 and 1 or 0
			end,
			GetSpellBookSkillLineInfo = function(idx)
				if idx == 1 then
					return { itemIndexOffset = 0, numSpellBookItems = #state.spellBookExtras }
				end
				return nil
			end,
			GetSpellBookItemInfo = function(slot)
				local item = state.spellBookExtras[slot]
				return item and { spellID = item.spellID } or nil
			end,
		}

		_G.C_UnitAuras = {
			GetAuraDataByIndex = function(unit, index, filter)
				local u = state.units[unit]
				if not u then
					return nil
				end
				if u.auraBlocked then
					return Mock.MakeSecret("blocked_aura_" .. unit)
				end
				return u.auras[index]
			end,
		}

		_G.C_Minimap = {
			GetNumTrackingTypes = function()
				return #state.tracking
			end,
			GetTrackingInfo = function(index)
				local t = state.tracking[index]
				if not t then
					return nil
				end
				if state.trackingTableMode then
					return {
						name = t.name,
						texture = t.texture,
						active = t.active,
						type = t.type or "spell",
						subType = t.subType,
						spellID = t.spellID,
					}
				end
				return t.name, t.texture, t.active, t.type or "spell", t.subType, t.spellID
			end,
			SetTracking = function(index, enabled)
				local target = state.tracking[index]
				if not target then
					return
				end
				if enabled then
					for i, item in ipairs(state.tracking) do
						item.active = (i == index)
					end
				else
					target.active = false
				end
			end,
		}

		_G.C_ChatInfo = {
			RegisterAddonMessagePrefix = function(prefix)
				state.registeredPrefixes[prefix] = true
				return true
			end,
			SendAddonMessage = function(prefix, msg, chatType, target)
				if #msg > 255 then
					error("SendAddonMessage exceeded 255 bytes (" .. tostring(#msg) .. ")")
				end
				table_insert(state.sentAddonMessages, {
					prefix = prefix,
					msg = msg,
					chatType = chatType,
					target = target,
					time = state.time,
				})
				return true
			end,
			SendChatMessage = function(msg, chatType, lang, target)
				table_insert(state.sentChatMessages, {
					msg = msg,
					chatType = chatType,
					lang = lang,
					target = target,
				})
			end,
		}

		_G.C_Item = {
			GetItemCount = function(itemID)
				return state.itemCounts[itemID] or 0
			end,
		}

		_G.C_AddOns = {
			IsAddOnLoaded = function(name)
				return state.loadedAddons[name] == true
			end,
			LoadAddOn = function(name)
				if name == "Blizzard_AuraContainer" and state.nativeAuraEnabled then
					return true
				end
				return false, "DISABLED"
			end,
			GetAddOnMetadata = function(name, field)
				if field == "Version" then
					return "0.1.0"
				end
				return nil
			end,
		}

		-- Optional Blizzard_AuraContainer / C_DurationUtil mock (activated when env:EnableNativeAuraMock(true))
		_G.C_XMLUtil = {
			GetTemplateInfo = function(name)
				if name == "CustomAuraContainerTemplate" and state.nativeAuraEnabled then
					return { name = name }
				end
				return nil
			end,
		}
		_G.C_StringUtil = {
			CreateNumericRuleFormatter = function()
				return { AddBreakpoint = function() end }
			end,
		}
		_G.C_CurveUtil = {
			CreateColorCurve = function()
				return { SetType = function() end, AddPoint = function() end }
			end,
		}
		_G.C_DurationUtil = {
			CreateDurationTextBinding = function()
				return {
					SetFormatter = function() end,
					SetTextColorCurve = function() end,
					SetExpiredText = function() end,
					SetZeroDurationText = function() end,
					SetUpdateInterval = function() end,
				}
			end,
		}
		_G.Enum.DurationTextBindingProperty = { RemainingPercent = 1 }
		_G.Enum.NumericRuleFormatRounding = { Down = 1 }
		_G.Enum.LuaCurveType = { Linear = 1 }
		_G.AuraContainerSortMethod = { ExpirationOnly = 1 }
		_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

		-- Modern C_ClassTalents + C_Traits mock
		_G.C_ClassTalents = {
			GetActiveConfigID = function()
				return 1
			end,
		}
		_G.C_Traits = {
			GetConfigInfo = function()
				return { treeIDs = { 100 } }
			end,
			GetTreeNodes = function()
				local nodes = {}
				local idx = 1
				for tName in pairs(state.talents) do
					nodes[idx] = tName
					idx = idx + 1
				end
				return nodes
			end,
			GetNodeInfo = function(_, nodeID)
				local rank = state.talents[nodeID] or 0
				return {
					ranksPurchased = rank,
					activeRank = rank,
					activeEntry = { entryID = nodeID },
				}
			end,
			GetEntryInfo = function(_, entryID)
				return { definitionID = entryID }
			end,
			GetDefinitionInfo = function(defID)
				return { overrideName = defID }
			end,
		}

		_G.UnitExists = function(u) return state.units[u] ~= nil end
		_G.GetUnitName = function(u) return state.units[u] and state.units[u].name or nil end
		_G.UnitName = function(u) return state.units[u] and state.units[u].name or nil end
		_G.UnitClass = function(u)
			local info = state.units[u]
			if not info then return nil, nil end
			return info.class, info.class
		end
		_G.UnitGUID = function(u) return state.units[u] and state.units[u].guid or nil end
		_G.UnitIsDeadOrGhost = function(u) return state.units[u] and state.units[u].dead or false end
		_G.UnitIsConnected = function(u) return state.units[u] and state.units[u].online or false end
		_G.UnitIsVisible = function(u) return state.units[u] and state.units[u].visible or false end
		_G.UnitInPhase = function(u) return state.units[u] == nil or state.units[u].inPhase ~= false end
		_G.UnitIsCharmed = function(u) return state.units[u] and state.units[u].charmed or false end
		_G.UnitCanAttack = function(_, u) return state.units[u] and state.units[u].hostile or false end
		_G.UnitIsFriend = function(_, u) return state.units[u] == nil or (not state.units[u].hostile) end
		_G.UnitInRange = function(u)
			local info = state.units[u]
			if info and info.unitInRange ~= nil then
				return info.unitInRange, true
			end
			return true, true
		end
		_G.UnitAffectingCombat = function(u) return state.units[u] and state.units[u].inCombat or false end
		_G.UnitGroupRolesAssigned = function(u) return state.units[u] and state.units[u].role or "NONE" end
		_G.UnitIsGroupLeader = function(u) return state.units[u] and state.units[u].isLeader or false end
		_G.UnitIsGroupAssistant = function(u) return state.units[u] and state.units[u].isAssist or false end
		_G.GetWeaponEnchantInfo = function()
			return unpack(state.weaponEnchants)
		end

		_G.IsInRaid = function() return state.inRaid end
		_G.IsInGroup = function(cat)
			if cat == _G.LE_PARTY_CATEGORY_INSTANCE then
				return state.inInstanceGroup
			end
			return state.inGroup
		end
		_G.GetNumGroupMembers = function()
			return #state.raidOrder
		end
		_G.GetRaidRosterInfo = function(i)
			local unit = state.raidOrder[i]
			local u = unit and state.units[unit]
			if not u then
				return nil
			end
			local rank = u.isLeader and 2 or (u.isAssist and 1 or 0)
			return u.name, rank, u.subgroup or 1, 60, u.class, u.class, "Zone", u.online, u.dead
		end

		_G.UIParent = env:CreateMockFrame("Frame", "UIParent", nil)
		_G.Minimap = env:CreateMockFrame("Frame", "Minimap", _G.UIParent)
		_G.Minimap:SetSize(140, 140)
		_G.GameTooltip = {
			SetOwner = function() end,
			ClearLines = function() end,
			AddLine = function() end,
			AddDoubleLine = function() end,
			Show = function() end,
			Hide = function() end,
		}
		_G.CreateFrame = function(frameType, name, parent, template)
			local f = env:CreateMockFrame(frameType, name, parent, template)
			if frameType == "AuraContainer" then
				f._slots = {}
				f._unit = nil
				f._enabled = false
				f.SetUnit = function(self, u) self._unit = u end
				f.SetEnabled = function(self, v) self._enabled = v and true or false end
				f.AddAuraSlot = function(self, key, filter, cfg)
					local slotFrame = env:CreateMockFrame("Frame", nil, self)
					slotFrame.SetDurationText = function(sf, text, opts)
						sf._durationText = text
						sf._durationOpts = opts
					end
					if cfg and cfg.initializeFrame then
						cfg.initializeFrame(slotFrame)
					end
					self._slots[key] = { filter = filter, cfg = cfg, frame = slotFrame, enabled = true }
					state.nativeAuraSlots[key] = self._slots[key]
				end
				f.SetAuraSlotEnabled = function(self, key, v)
					if self._slots[key] then self._slots[key].enabled = v and true or false end
				end
				f.SetAuraSlotCandidateFilters = function(self, key, filter)
					if self._slots[key] then self._slots[key].candidateFilters = filter end
				end
			end
			return f
		end
		_G.hooksecurefunc = function(fnName, hookFn)
			state.hooks[fnName] = hookFn
		end
		_G.CompactUnitFrame_UpdateAuras = function() end
		_G.UISpecialFrames = {}
		_G.SlashCmdList = {}
		_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
	end

	-- Load all Core/ modules in exact TOC order into a fresh LBB namespace
	function env:LoadCore()
		local LBB = {}
		_G.LittleBuffBoy = LBB
		local coreFiles = {
			"Core/Compat.lua",
			"Core/Catalog.lua",
			"Core/Capabilities.lua",
			"Core/Assignments.lua",
			"Core/Negotiator.lua",
			"Core/Comms.lua",
			"Core/Scanner.lua",
			"Core/Tracking.lua",
		}
		for _, path in ipairs(coreFiles) do
			local chunk, err = loadfile(path)
			if not chunk then
				error("Failed to load " .. path .. ": " .. tostring(err))
			end
			chunk("LittleBuffBoy", LBB)
		end
		return LBB
	end

	-- Load the entire addon (Core + UI + Init) in exact LittleBuffBoy.toc order
	function env:LoadFullAddon()
		local LBB = env:LoadCore()
		local uiFiles = {
			"UI/Theme.lua",
			"UI/NativeAuras.lua",
			"UI/BuffStrip.lua",
			"UI/MatrixFrame.lua",
			"UI/RaidIndicators.lua",
			"UI/ReminderPill.lua",
			"UI/MinimapButton.lua",
			"UI/Options.lua",
			"Init.lua",
		}
		for _, path in ipairs(uiFiles) do
			local chunk, err = loadfile(path)
			if not chunk then
				error("Failed to load " .. path .. ": " .. tostring(err))
			end
			chunk("LittleBuffBoy", LBB)
		end
		return LBB
	end

	return env
end

return Mock
