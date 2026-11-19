local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Tracking = {}
LBB.Tracking = Tracking

local ipairs = ipairs
local pairs = pairs
local table_insert = table.insert

Tracking.dismissed = false
Tracking.listeners = {}

function Tracking:Reset()
	self.dismissed = false
	self.listeners = {}
end

function Tracking:OnStatusChanged(fn)
	if type(fn) == "function" then
		table_insert(self.listeners, fn)
	end
end

function Tracking:Notify(status)
	for _, fn in ipairs(self.listeners) do
		pcall(fn, status)
	end
end

function Tracking:GetCharDB()
	if not LBB.CharDB then
		LBB.CharDB = {}
	end
	return LBB.CharDB
end

function Tracking:GetPreferred()
	local db = self:GetCharDB()
	return db.preferredTracking
end

function Tracking:SetPreferred(entry, pinned)
	local db = self:GetCharDB()
	if not entry then
		db.preferredTracking = nil
		self.dismissed = false
		self:Notify(self:GetStatus())
		return
	end
	db.preferredTracking = {
		name = entry.name,
		spellID = entry.spellID,
		texture = entry.texture,
		category = entry.category,
		pinned = pinned and true or false,
	}
	self.dismissed = false
	self:Notify(self:GetStatus())
end

function Tracking:IsTrackableForAutoRemember(entry)
	if not entry then
		return false
	end
	return entry.category == "PROFESSION" or entry.category == "HUNTER" or entry.category == "CLASS"
end

function Tracking:FindEntryForPreferred(state, pref)
	if not state or not pref then
		return nil
	end
	if pref.spellID and state.bySpellID[pref.spellID] then
		return state.bySpellID[pref.spellID]
	end
	if pref.name and state.byName[pref.name] then
		return state.byName[pref.name]
	end
	return nil
end

-- Called on MINIMAP_UPDATE_TRACKING, PLAYER_ENTERING_WORLD, PLAYER_ALIVE, READY_CHECK
function Tracking:Refresh(opts)
	local state = LBB.Capabilities:ScanTracking()
	local db = self:GetCharDB()
	local pref = db.preferredTracking
	local autoRemember = (LBB.DB == nil or LBB.DB.autoRememberTracking ~= false)

	-- If player turned on a profession/hunter/class tracking mode and hasn't pinned a different one, remember it
	if state.active and self:IsTrackableForAutoRemember(state.active) then
		if autoRemember and (not pref or not pref.pinned) then
			if not pref or pref.name ~= state.active.name then
				db.preferredTracking = {
					name = state.active.name,
					spellID = state.active.spellID,
					texture = state.active.texture,
					category = state.active.category,
					pinned = false,
				}
				pref = db.preferredTracking
			else
				-- Keep texture/spellID refreshed
				pref.texture = state.active.texture or pref.texture
				pref.spellID = state.active.spellID or pref.spellID
			end
		end
	end

	-- On explicit wake triggers (login, revive, ready check), clear snooze so reminder shows if missing
	if opts and opts.clearDismiss then
		self.dismissed = false
	end

	local status = self:GetStatus(state)
	-- If preferred tracking is active again, clear dismissed flag automatically
	if status.isActive then
		self.dismissed = false
	end

	self:Notify(status)
	return status
end

function Tracking:GetStatus(state)
	state = state or LBB.Capabilities.trackingState
	local pref = self:GetPreferred()
	local active = state and state.active or nil

	if not pref then
		return {
			hasPreferred = false,
			preferred = nil,
			active = active,
			isActive = (active ~= nil),
			needsRestore = false,
			available = false,
			index = nil,
			dismissed = self.dismissed,
		}
	end

	local matched = self:FindEntryForPreferred(state, pref)
	local isActive = (matched ~= nil and matched.active == true)
	local available = (matched ~= nil)
	local needsRestore = available and (not isActive) and (not self.dismissed)

	return {
		hasPreferred = true,
		preferred = pref,
		active = active,
		isActive = isActive,
		needsRestore = needsRestore,
		available = available,
		index = matched and matched.index or nil,
		texture = (matched and matched.texture) or pref.texture,
		name = (matched and matched.name) or pref.name,
		dismissed = self.dismissed,
	}
end

function Tracking:RestorePreferred()
	local state = LBB.Capabilities:ScanTracking()
	local status = self:GetStatus(state)
	if not status.hasPreferred or not status.index then
		return false
	end
	local ok = LBB.Compat.SetTracking(status.index, true)
	if ok then
		self.dismissed = false
		self:Refresh()
	end
	return ok
end

function Tracking:Dismiss()
	self.dismissed = true
	self:Notify(self:GetStatus())
end

function Tracking:GetAvailableModes()
	local state = LBB.Capabilities:ScanTracking()
	local out = {}
	for _, entry in ipairs(state.list) do
		if self:IsTrackableForAutoRemember(entry) then
			table_insert(out, entry)
		end
	end
	return out
end
