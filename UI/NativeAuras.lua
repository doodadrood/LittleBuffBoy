local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

-- Display-only Blizzard CustomAuraContainerTemplate adapter for WoW: Forever (16001 / Midnight).
-- Renders live combat countdowns for short-duration personal buffs (Paladin Seals & Righteous Fury)
-- without addon Lua ever reading or comparing Midnight secret aura values.
-- Gracefully falls back (returns false) when Blizzard_AuraContainer is unavailable.

local NativeAuras = {}
LBB.NativeAuras = NativeAuras

local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local math_max = math.max
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat

NativeAuras.ready = false
NativeAuras.loadFailed = false
NativeAuras.bindingTemplate = nil
NativeAuras.hosts = {}
NativeAuras.displays = {}
NativeAuras.failed = {}

function NativeAuras:Reset()
	self.ready = false
	self.loadFailed = false
	self.bindingTemplate = nil
	self.hosts = {}
	self.displays = {}
	self.failed = {}
end

function NativeAuras:IsAvailable()
	return _G.C_AddOns and _G.C_AddOns.LoadAddOn
		and _G.C_XMLUtil and _G.C_XMLUtil.GetTemplateInfo
		and _G.C_DurationUtil and _G.C_DurationUtil.CreateDurationTextBinding
		and _G.C_StringUtil and _G.C_StringUtil.CreateNumericRuleFormatter
		and _G.C_CurveUtil and _G.C_CurveUtil.CreateColorCurve
		and _G.Enum and _G.Enum.DurationTextBindingProperty
		and _G.Enum.NumericRuleFormatRounding
		and _G.AuraContainerSortMethod
		and _G.CreateColor
		and true or false
end

function NativeAuras:GetBindingTemplate()
	if self.bindingTemplate then
		return self.bindingTemplate
	end
	local formatter = _G.C_StringUtil.CreateNumericRuleFormatter()
	formatter:AddBreakpoint({
		threshold = 0,
		format = "%d:%02d",
		components = {
			{ div = 60, step = 1, rounding = _G.Enum.NumericRuleFormatRounding.Down },
			{ mod = 60, step = 1, rounding = _G.Enum.NumericRuleFormatRounding.Down },
		},
	})
	local curve = _G.C_CurveUtil.CreateColorCurve()
	if _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Linear then
		curve:SetType(_G.Enum.LuaCurveType.Linear)
	end
	curve:AddPoint(0.0, _G.CreateColor(0.94, 0.28, 0.30, 1))
	curve:AddPoint(0.3, _G.CreateColor(0.98, 0.72, 0.18, 1))
	curve:AddPoint(1.0, _G.CreateColor(0.20, 0.82, 0.45, 1))

	local binding = _G.C_DurationUtil.CreateDurationTextBinding()
	binding:SetFormatter(formatter)
	binding:SetTextColorCurve(curve, _G.Enum.DurationTextBindingProperty.RemainingPercent)
	binding:SetExpiredText("")
	binding:SetZeroDurationText("")
	binding:SetUpdateInterval(1)
	self.bindingTemplate = binding
	return binding
end

function NativeAuras:Prepare()
	if self.ready then
		return true
	end
	if self.loadFailed or LBB.Compat.InCombat() then
		return false
	end
	if not self:IsAvailable() then
		self.loadFailed = true
		return false
	end
	local ok, loaded = pcall(_G.C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	if not ok or not loaded or not _G.C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") then
		self.loadFailed = true
		return false
	end
	self.ready = true
	return true
end

local function buildSignature(spellIDSet)
	local ids = {}
	for sid, enabled in pairs(spellIDSet or {}) do
		if enabled and type(sid) == "number" and sid > 0 then
			table_insert(ids, sid)
		end
	end
	table_sort(ids)
	return table_concat(ids, ",")
end

local function setDisplayEnabled(display, enabled)
	enabled = enabled and true or false
	if display.enabled ~= enabled then
		pcall(function()
			display.host.container:SetAuraSlotEnabled(display.key, enabled)
		end)
		display.host.active = math_max(0, display.host.active + (enabled and 1 or -1))
		display.enabled = enabled
	end
	local active = display.host.active > 0
	if display.host.enabled ~= active then
		pcall(function()
			display.host.container:SetEnabled(active)
		end)
		display.host.enabled = active
	end
end

local function ensureHost(parentTile, unit)
	local host = NativeAuras.hosts[parentTile]
	if not host then
		if LBB.Compat.InCombat() then
			return nil
		end
		-- Sibling frame to UIParent (never a protected child of the SecureActionButton!)
		local ok, container = pcall(_G.CreateFrame, "AuraContainer", nil, _G.UIParent, "CustomAuraContainerTemplate")
		if not ok or not container then
			return nil
		end
		container:EnableMouse(false)
		container:EnableMouseWheel(false)
		container:SetSize(1, 1)
		container:SetPoint("TOPLEFT", parentTile, "TOPLEFT")
		container:SetEnabled(false)
		host = {
			container = container,
			parent = parentTile,
			unit = nil,
			active = 0,
			enabled = false,
			displays = {},
		}
		NativeAuras.hosts[parentTile] = host

		if parentTile.HookScript then
			parentTile:HookScript("OnHide", function()
				for _, d in pairs(host.displays) do
					setDisplayEnabled(d, false)
				end
				container:Hide()
			end)
			parentTile:HookScript("OnShow", function()
				container:Show()
				for _, d in pairs(host.displays) do
					if d.requested then
						setDisplayEnabled(d, true)
					end
				end
			end)
		end
	end

	if not LBB.Compat.InCombat() then
		if parentTile.GetEffectiveScale and _G.UIParent.GetEffectiveScale then
			local scale = parentTile:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
			if host.scale ~= scale and host.container.SetScale then
				host.container:SetScale(scale)
				host.scale = scale
			end
		end
		if parentTile.GetFrameStrata and host.container.SetFrameStrata then
			host.container:SetFrameStrata(parentTile:GetFrameStrata())
		end
		if parentTile.GetFrameLevel and host.container.SetFrameLevel then
			host.container:SetFrameLevel(parentTile:GetFrameLevel() + 2)
		end
		if host.unit ~= unit then
			pcall(function()
				host.container:SetUnit(unit)
			end)
			host.unit = unit
		end
	end

	return host
end

local function copyFontStyle(dst, src)
	if src.GetFont then
		local font, size, flags = src:GetFont()
		if font then
			dst:SetFont(font, size or 10, flags or "OUTLINE")
		end
	end
	if src.GetJustifyH and dst.SetJustifyH then dst:SetJustifyH(src:GetJustifyH()) end
	if src.GetJustifyV and dst.SetJustifyV then dst:SetJustifyV(src:GetJustifyV()) end
	dst:SetAllPoints(src)
end

-- Bind a native Blizzard AuraContainer timer overlay onto `sourceFontString` (owned by `parentTile`)
function NativeAuras:BindTimer(parentTile, sourceFontString, unit, spellIDSet)
	if not parentTile or not sourceFontString or self.failed[sourceFontString] then
		return false
	end
	if not self:Prepare() then
		return false
	end
	local signature = buildSignature(spellIDSet)
	if signature == "" then
		self:UnbindTimer(sourceFontString)
		return false
	end

	local display = self.displays[sourceFontString]
	local host = ensureHost(parentTile, unit or "player")
	if not host then
		return false
	end

	if not display then
		if LBB.Compat.InCombat() then
			return false
		end
		local slotKey = tostring(parentTile:GetName() or parentTile) .. "_native"
		display = {
			host = host,
			key = slotKey,
			enabled = true,
			requested = false,
			signature = "",
		}
		local ok = pcall(function()
			host.container:AddAuraSlot(slotKey, "HELPFUL", {
				candidateFilters = { includeSpellIDs = spellIDSet },
				sortMethod = _G.AuraContainerSortMethod.ExpirationOnly,
				initializeFrame = function(frame)
					frame:EnableMouse(false)
					frame:EnableMouseWheel(false)
					frame:SetAllPoints(parentTile)
					if parentTile.GetFrameLevel then
						frame:SetFrameLevel(parentTile:GetFrameLevel() + 3)
					end
					-- Green active indicator bar rendered natively by Blizzard while the aura is active
					local activeBar = frame:CreateTexture(nil, "ARTWORK")
					activeBar:SetHeight(3)
					activeBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
					activeBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
					activeBar:SetColorTexture(0.20, 0.82, 0.45, 1)

					local text = frame:CreateFontString(nil, "OVERLAY")
					copyFontStyle(text, sourceFontString)
					frame:SetDurationText(text, { binding = self:GetBindingTemplate() })
					display.frame = frame
					display.text = text
					display.activeBar = activeBar
				end,
			})
		end)
		if not ok or not display.frame then
			self.failed[sourceFontString] = true
			pcall(function()
				host.container:SetAuraSlotEnabled(slotKey, false)
			end)
			return false
		end
		host.active = host.active + 1
		display.signature = signature
		self.displays[sourceFontString] = display
		host.displays[sourceFontString] = display
	else
		if display.signature ~= signature then
			pcall(function()
				display.host.container:SetAuraSlotCandidateFilters(display.key, { includeSpellIDs = spellIDSet })
			end)
			display.signature = signature
		end
	end

	display.requested = true
	local visible = (not parentTile.IsVisible) or parentTile:IsVisible()
	setDisplayEnabled(display, visible)
	if visible and host.container.Show then
		host.container:Show()
	end
	-- Hide the fallback Lua text while Blizzard owns the live countdown
	if sourceFontString.SetAlpha then
		sourceFontString:SetAlpha(0)
	end
	return true
end

function NativeAuras:UnbindTimer(sourceFontString)
	local display = sourceFontString and self.displays[sourceFontString]
	if not display then
		return
	end
	display.requested = false
	setDisplayEnabled(display, false)
	if sourceFontString.SetAlpha then
		sourceFontString:SetAlpha(1)
	end
end

function NativeAuras:IsBound(sourceFontString)
	local display = sourceFontString and self.displays[sourceFontString]
	return display ~= nil and display.requested == true and display.enabled == true
end
