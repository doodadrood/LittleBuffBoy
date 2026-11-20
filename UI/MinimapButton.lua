local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local MinimapButton = {}
LBB.MinimapButton = MinimapButton

local math_cos = math.cos
local math_sin = math.sin
local math_rad = math.rad
local math_deg = math.deg
local math_atan2 = math.atan2

MinimapButton.ICON_PATH = "Interface\\AddOns\\LittleBuffBoy\\Media\\MinimapIcon"
MinimapButton.button = nil
MinimapButton.ldbObject = nil
MinimapButton.usingLibDBIcon = false

local function getMinimapDB()
	if not LBB.DB then
		LBB.DB = {}
	end
	if type(LBB.DB.minimap) ~= "table" then
		LBB.DB.minimap = { hide = false, minimapPos = 220 }
	end
	if LBB.DB.minimap.minimapPos == nil then
		LBB.DB.minimap.minimapPos = 220
	end
	return LBB.DB.minimap
end

local function handleButtonClick(mouseButton)
	if mouseButton == "RightButton" then
		if LBB.Options then
			LBB.Options:Toggle()
		end
	elseif mouseButton == "MiddleButton" then
		if LBB.RunNegotiator then
			LBB:RunNegotiator(true, { forceFresh = true })
			LBB:Print("Auto-negotiated buff assignments.")
		end
	else
		if LBB.MatrixFrame then
			LBB.MatrixFrame:Toggle()
		end
	end
end

local function populateTooltip(tooltip)
	if not tooltip then
		return
	end
	tooltip:ClearLines()
	tooltip:AddLine("|cff38bdf8LittleBuffBoy|r", 1, 1, 1)
	local vec = LBB.Capabilities and LBB.Capabilities.playerVector
	local duties = vec and LBB.Assignments and LBB.Assignments:GetPlayerDuties(vec.name) or {}
	local activePreset = LBB.CharDB and LBB.CharDB.activePresetName
	if activePreset then
		tooltip:AddDoubleLine("Preset:", activePreset, 0.7, 0.75, 0.82, 0.2, 0.9, 0.5)
	end
	tooltip:AddDoubleLine("Active Duties:", tostring(#duties), 0.7, 0.75, 0.82, 1, 1, 1)
	tooltip:AddLine(" ")
	tooltip:AddLine("Left-Click: Toggle Assignment Matrix", 0.75, 0.9, 1.0)
	tooltip:AddLine("Right-Click: Open Options", 0.75, 0.9, 1.0)
	tooltip:AddLine("Middle-Click: Auto-Assign Buffs", 0.75, 0.9, 1.0)
	tooltip:AddLine("Drag: Move around Minimap", 0.6, 0.65, 0.72)
end

-- Blizzard Addon Compartment callbacks (referenced in .toc)
_G.LittleBuffBoy_OnAddonCompartmentClick = function(_, buttonName)
	handleButtonClick(buttonName or "LeftButton")
end

_G.LittleBuffBoy_OnAddonCompartmentEnter = function(_, menuButtonFrame)
	if _G.GameTooltip and menuButtonFrame then
		_G.GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
		populateTooltip(_G.GameTooltip)
		_G.GameTooltip:Show()
	end
end

_G.LittleBuffBoy_OnAddonCompartmentLeave = function()
	if _G.GameTooltip then
		_G.GameTooltip:Hide()
	end
end

function MinimapButton:UpdatePosition()
	local btn = self.button
	if not btn or self.usingLibDBIcon then
		return
	end
	-- CRITICAL for minimap collectors (OneForAll, MBB, HidingBar, SexyMap):
	-- NEVER force-reanchor the button if a collector has reparented it into its drawer!
	if _G.Minimap and btn:GetParent() ~= _G.Minimap then
		return
	end
	local db = getMinimapDB()
	local angle = math_rad(db.minimapPos or 220)
	local radius = ((_G.Minimap and _G.Minimap.GetWidth and _G.Minimap:GetWidth() or 140) / 2) + 8
	local x = math_cos(angle) * radius
	local y = math_sin(angle) * radius
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", _G.Minimap or _G.UIParent, "CENTER", x, y)
end

function MinimapButton:CreateLDBObject()
	if self.ldbObject then
		return self.ldbObject
	end
	local obj = {
		type = "launcher",
		text = "LittleBuffBoy",
		label = "LittleBuffBoy",
		icon = self.ICON_PATH,
		OnClick = function(_, buttonName)
			handleButtonClick(buttonName)
		end,
		OnTooltipShow = function(tooltip)
			populateTooltip(tooltip)
		end,
	}
	self.ldbObject = obj
	return obj
end

function MinimapButton:Init()
	if self.button or self.usingLibDBIcon then
		return self.button
	end
	local db = getMinimapDB()

	-- Path 1: Prefer shared LibDataBroker-1.1 + LibDBIcon-1.0 when present
	-- (Ensures instant native registration in OneForAll, MBB, HidingBar, ElvUI, SexyMap, etc.)
	if _G.LibStub then
		local okLDB, LDB = pcall(_G.LibStub, "LibDataBroker-1.1", true)
		local okIcon, LDBIcon = pcall(_G.LibStub, "LibDBIcon-1.0", true)
		if okLDB and LDB and okIcon and LDBIcon then
			local dataObj = LDB:GetDataObjectByName("LittleBuffBoy")
			if not dataObj then
				dataObj = LDB:NewDataObject("LittleBuffBoy", self:CreateLDBObject())
			end
			if not LDBIcon:IsRegistered("LittleBuffBoy") then
				LDBIcon:Register("LittleBuffBoy", dataObj, db)
			end
			self.usingLibDBIcon = true
			self.ldbIconLib = LDBIcon
			self.button = LDBIcon:GetMinimapButton("LittleBuffBoy")
			if db.hide then
				LDBIcon:Hide("LittleBuffBoy")
			else
				LDBIcon:Show("LittleBuffBoy")
			end
			return self.button
		end
	end

	-- Path 2: Standalone LibDBIcon-compatible button parented directly to Minimap
	-- Named LibDBIcon10_LittleBuffBoy with standard .icon, .dataObject, .db, OnClick, OnEnter, OnLeave
	-- so OneForAll and heuristic Minimap:GetChildren() collectors pick it up cleanly.
	local parent = _G.Minimap or _G.UIParent
	local btn = _G.CreateFrame("Button", "LibDBIcon10_LittleBuffBoy", parent)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:EnableMouse(true)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(24, 24)
	bg:SetPoint("CENTER", btn, "CENTER", 0, 0)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	btn._bg = bg

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
	icon:SetTexture(self.ICON_PATH)
	if icon.SetMask then
		icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	end
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	btn.border = border

	btn.dataObject = self:CreateLDBObject()
	btn.db = db

	btn:SetScript("OnClick", function(_, mouseButton)
		handleButtonClick(mouseButton)
	end)
	btn:SetScript("OnEnter", function(selfBtn)
		if _G.GameTooltip then
			_G.GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
			populateTooltip(_G.GameTooltip)
			_G.GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function()
		if _G.GameTooltip then
			_G.GameTooltip:Hide()
		end
	end)
	btn:SetScript("OnDragStart", function(selfBtn)
		if _G.Minimap and selfBtn:GetParent() ~= _G.Minimap then
			return
		end
		selfBtn._dragging = true
		selfBtn:SetScript("OnUpdate", function()
			if not (_G.Minimap and _G.GetCursorPosition and _G.Minimap.GetCenter) then
				return
			end
			local mx, my = _G.Minimap:GetCenter()
			local cx, cy = _G.GetCursorPosition()
			local scale = _G.Minimap:GetEffectiveScale() or 1
			if mx and my and cx and cy then
				cx, cy = cx / scale, cy / scale
				local angle = math_deg(math_atan2(cy - my, cx - mx))
				if angle < 0 then
					angle = angle + 360
				end
				getMinimapDB().minimapPos = angle
				MinimapButton:UpdatePosition()
			end
		end)
	end)
	btn:SetScript("OnDragStop", function(selfBtn)
		selfBtn._dragging = false
		selfBtn:SetScript("OnUpdate", nil)
	end)

	self.button = btn
	self:UpdatePosition()
	btn:SetShown(not db.hide)
	return btn
end

function MinimapButton:SetShown(show)
	local db = getMinimapDB()
	db.hide = not (show and true or false)
	if self.usingLibDBIcon and self.ldbIconLib then
		if db.hide then
			self.ldbIconLib:Hide("LittleBuffBoy")
		else
			self.ldbIconLib:Show("LittleBuffBoy")
		end
	elseif self.button then
		self.button:SetShown(not db.hide)
	end
end

function MinimapButton:IsShown()
	local db = getMinimapDB()
	return not db.hide
end
