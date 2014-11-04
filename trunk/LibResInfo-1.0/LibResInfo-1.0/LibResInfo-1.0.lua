--[[--------------------------------------------------------------------
LibResInfo-1.0
Library to provide information about resurrections in your group.
Copyright (c) 2012-2014 Phanx. All rights reserved.
See the accompanying README and LICENSE files for more information.
http://www.wowinterface.com/downloads/info21467-LibResInfo-1.0.html
http://wow.curseforge.com/addons/libresinfo/
------------------------------------------------------------------------
TODO:
* Handle Reincarnation with some guesswork?
* Clear data when releasing spirit
----------------------------------------------------------------------]]

local DEBUG_LEVEL = GetAddOnMetadata("LibResInfo-1.0", "Version") and 1 or 0
local DEBUG_FRAME = ChatFrame3

------------------------------------------------------------------------

local MAJOR, MINOR = "LibResInfo-1.0", 21
assert(LibStub, MAJOR.." requires LibStub")
assert(LibStub("CallbackHandler-1.0"), MAJOR.." requires CallbackHandler-1.0")
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

------------------------------------------------------------------------

local callbacks     = lib.callbacks     or LibStub("CallbackHandler-1.0"):New(lib)
local eventFrame    = lib.eventFrame    or CreateFrame("Frame")

local guidFromUnit  = lib.guidFromUnit  or {} -- t[unit] = guid -- table lookup is faster than calling UnitGUID
local nameFromGUID  = lib.nameFromGUID  or {} -- t[guid] = name
local unitFromGUID  = lib.unitFromGUID  or {} -- t[guid] = unit

local castingSingle = lib.castingSingle or {} -- t[casterGUID] = { startTime = <number>, endTime = <number>, target = <guid> }
local castingMass   = lib.castingMass   or {} -- t[casterGUID] = endTime
local hasPending    = lib.hasPending    or {} -- t[targetGUID] = endTime

local hasSoulstone  = lib.hasSoulstone  or {} -- t[targetGUID] = <boolean>
local isDead        = lib.isDead        or {} -- t[targetGUID] = <boolean>
local isGhost       = lib.isGhost       or {} -- t[targetGUID] = <boolean>

------------------------------------------------------------------------

lib.callbacks       = callbacks
lib.eventFrame      = eventFrame

lib.guidFromUnit    = guidFromUnit
lib.nameFromGUID    = nameFromGUID
lib.unitFromGUID    = unitFromGUID

lib.castingSingle   = castingSingle
lib.castingMass     = castingMass
lib.hasPending      = hasPending

lib.hasSoulstone    = hasSoulstone
lib.isDead          = isDead
lib.isGhost         = isGhost

------------------------------------------------------------------------

local RESURRECT_PENDING_TIME = 60
local RELEASE_PENDING_TIME = 360
local RECENTLY_MASS_RESURRECTED = GetSpellInfo(95223)
local SOULSTONE = GetSpellInfo(20707)

local resSpells = {
	[2008]   = GetSpellInfo(2008),   -- Ancestral Spirit (shaman)
	[8342]   = GetSpellInfo(8342),   -- Defibrillate (item: Goblin Jumper Cables)
	[22999]  = GetSpellInfo(22999),  -- Defibrillate (item: Goblin Jumper Cables XL)
	[54732]  = GetSpellInfo(54732),  -- Defibrillate (item: Gnomish Army Knife)
	[126393] = GetSpellInfo(126393), -- Eternal Guardian (hunter pet: quilien)
	[61999]  = GetSpellInfo(61999),  -- Raise Ally (death knight)
	[20484]  = GetSpellInfo(20484),  -- Rebirth (druid)
	[7328]   = GetSpellInfo(7328),   -- Redemption (paladin)
	[2006]   = GetSpellInfo(2006),   -- Resurrection (priest)
	[115178] = GetSpellInfo(115178), -- Resuscitate (monk)
	[50769]  = GetSpellInfo(50769),  -- Revive (druid)
	[982]    = GetSpellInfo(982),    -- Revive Pet (hunter)
	[20707]  = GetSpellInfo(20707),  -- Soulstone (warlock)
	[83968]  = GetSpellInfo(83968),  -- Mass Resurrection
}

------------------------------------------------------------------------

local next, pairs, GetNumGroupMembers, GetTime, IsInGroup, IsInRaid, UnitAura, UnitCastingInfo, UnitGUID, UnitHasIncomingResurrection, UnitHealth, UnitIsConnected, UnitIsDead, UnitIsDeadOrGhost, UnitIsGhost, UnitName
    = next, pairs, GetNumGroupMembers, GetTime, IsInGroup, IsInRaid, UnitAura, UnitCastingInfo, UnitGUID, UnitHasIncomingResurrection, UnitHealth, UnitIsConnected, UnitIsDead, UnitIsDeadOrGhost, UnitIsGhost, UnitName

------------------------------------------------------------------------

local function debug(level, text, ...)
	if level <= DEBUG_LEVEL then
		if ... then
			if type(text) == "string" and strfind(text, "%%[dfqsx%d%.]") then
				text = format(text, ...)
			else
				text = strjoin(" ", tostringall(text, ...))
			end
		else
			text = tostring(text)
		end
		DEBUG_FRAME:AddMessage("|cff00ddba[LRI]|r " .. text)
	end
end

local newTable, remTable
do
	local pool = {}
	function newTable()
		local t = next(pool)
		if t then
			pool[t] = nil
			return t
		end
		return {}
	end
	function remTable(t)
		pool[wipe(t)] = true
		return nil
	end
end

------------------------------------------------------------------------

lib.callbacksInUse = lib.callbacksInUse or {}

eventFrame:SetScript("OnEvent", function(self, event, ...)
	return self[event] and self[event](self, event, ...)
end)

function callbacks:OnUsed(lib, callback)
	if not next(lib.callbacksInUse) then
		debug(1, "Callbacks in use! Starting up...")
		eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
		eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
		eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
		eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
		eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		eventFrame:RegisterEvent("UNIT_AURA")
		eventFrame:RegisterEvent("UNIT_CONNECTION")
		eventFrame:RegisterEvent("UNIT_HEALTH")
		eventFrame:GROUP_ROSTER_UPDATE("OnUsed")
	end
	lib.callbacksInUse[callback] = true
end

function callbacks:OnUnused(lib, callback)
	lib.callbacksInUse[callback] = nil
	if not next(lib.callbacksInUse) then
		debug(1, "No callbacks in use. Shutting down...")
		eventFrame:UnregisterAllEvents()
		eventFrame:Hide()
		wipe(guidFromUnit)
		wipe(nameFromGUID)
		wipe(unitFromGUID)
		for caster, data in pairs(castingSingle) do
			castingSingle[caster] = remTable(data)
		end
		wipe(castingMass)
		wipe(hasPending)
		wipe(hasSoulstone)
		wipe(isDead)
		wipe(isGhost)
	end
end

------------------------------------------------------------------------

function lib.RegisterAllCallbacks(handler, method, includeMassRes)
	lib.RegisterCallback(handler, "LibResInfo_ResCastStarted", method)
	lib.RegisterCallback(handler, "LibResInfo_ResCastCancelled", method)
	lib.RegisterCallback(handler, "LibResInfo_ResCastFinished", method)

	if includeMassRes then
		lib.RegisterCallback(handler, "LibResInfo_MassResStarted", method)
		lib.RegisterCallback(handler, "LibResInfo_MassResCancelled", method)
		lib.RegisterCallback(handler, "LibResInfo_MassResFinished", method)
		lib.RegisterCallback(handler, "LibResInfo_UnitUpdate", method)
	end

	lib.RegisterCallback(handler, "LibResInfo_ResPending", method)
	lib.RegisterCallback(handler, "LibResInfo_ResUsed", method)
	lib.RegisterCallback(handler, "LibResInfo_ResExpired", method)
end

------------------------------------------------------------------------
--	Returns information about the res being cast on the specified unit.
--	Arguments: unit (unitID or GUID)
--	Returns: resType (string), endTime (number), caster (unitID), casterGUID
--	* All returns are nil if no res is being cast on the unit.
--	* resType is one of:
--   - SELFRES if the unit has a Soulstone or other self-res ability available,
--   - PENDING if the unit already has a res available to accept, or
--	  - CASTING if a res is being cast on the unit.
--	* caster and casterGUID are nil if the unit is being Mass Ressed.
------------------------------------------------------------------------

function lib:UnitHasIncomingRes(unit)
	if type(unit) ~= "string" then return end
	local guid
	if strmatch(unit, "^Player%-") then
		guid = unit
		unit = unitFromGUID[guid]
	else
		guid = UnitGUID(unit)
		unit = unitFromGUID[guid]
	end
	if not guid or not unit or not UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
		return
	end
	if hasPending[guid] then
		local state = hasSoulstone[guid] and "SELFRES" or "PENDING"
		debug(2, "UnitHasIncomingRes", nameFromGUID[guid], state)
		return state, hasPending[guid]
	end

	local state, firstCaster, firstEnd
	for caster, data in pairs(castingSingle) do
		if data.target == guid then
			if not firstEnd or data.endTime < firstEnd then
				state, firstCaster, firstEnd = "CASTING", caster, data.endTime
			end
		end
	end
	if not UnitDebuff(unit, RECENTLY_MASS_RESURRECTED) then
		for caster, endTime in pairs(castingMass) do
			if not firstEnd or endTime < firstEnd then
				state, firstCaster, firstEnd = "MASSRES", caster, endTime
			end
		end
	end
	if state and firstCaster and firstEnd then
		debug(2, "UnitHasIncomingRes", nameFromGUID[guid], state, nameFromGUID[firstCaster])
		return state, firstEnd, unitFromGUID[firstCaster], firstCaster
	end
	--debug(3, "UnitHasIncomingRes", nameFromGUID[guid], "nil")
end

------------------------------------------------------------------------
--	Return information about the res being cast by the specified unit.
--	Arguments: unit (unitID or GUID)
--	Returns: endTime (number), target (unitID), targetGUID (guid), isFirst (boolean)
--	* all returns are nil if the unit is not casting a res
--	* target and targetGUID are nil if the unit is casting Mass Res
------------------------------------------------------------------------

function lib:UnitIsCastingRes(unit)
	if type(unit) ~= "string" then return end
	local guid
	if strmatch(unit, "^Player%-") then
		guid = unit
		unit = unitFromGUID[guid]
	else
		guid = UnitGUID(unit)
		unit = unitFromGUID[guid]
	end
	if not guid or not unit then
		return
	end

	local casting = castingSingle[guid]
	if casting then
		local endTime, target, isFirst = casting.endTime, casting.target, true
		-- TODO: Handle edge case where this function is called in between the cast start and the target identification?
		for caster, data in pairs(castingSingle) do
			if data.target == target and data.endTime < endTime then
				isFirst = false
				break
			end
		end
		debug(2, "UnitIsCastingRes", nameFromGUID[guid], "casting on", nameFromGUID[casting.target], isFirst and "(first)" or "(duplicate)")
		return endTime, unitFromGUID[casting.target], casting.target, isFirst
	end

	casting = castingMass[guid]
	if casting then
		local endTime, isFirst = casting, true
		for caster, endTime2 in pairs(castingMass) do
			if endTime2 < endTime then
				isFirst = false
				break
			end
		end
		debug(2, "UnitIsCastingRes", nameFromGUID[guid], "casting Mass Res", isFirst and "(first)" or "(duplicate)")
		return endTime, nil, nil, isFirst
	end

	--debug(3, "UnitIsCastingRes", nameFromGUID[guid], "nil")
end

------------------------------------------------------------------------
--	Handle group changes:

local function AddUnit(unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	guidFromUnit[unit] = guid
	nameFromGUID[guid] = UnitName(unit)
	unitFromGUID[guid] = unit
	-- Check for soulstones:
	eventFrame:UNIT_AURA("AddUnit", unit)
end

function eventFrame:GROUP_ROSTER_UPDATE(event)
	debug(3, event)

	-- Update guid <==> unit mappings:
	wipe(guidFromUnit)
	wipe(unitFromGUID)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			AddUnit("raid"..i)
			AddUnit("raidpet"..i)
		end
	else
		AddUnit("player")
		AddUnit("pet")
		if IsInGroup() then
			for i = 1, GetNumGroupMembers() - 1 do
				AddUnit("party"..i)
				AddUnit("partypet"..i)
			end
		end
	end

	-- Remove data for single casters no longer in the group:
	for caster, data in pairs(castingSingle) do
		if not unitFromGUID[caster] then
			local target = data.target
			castingSingle[caster] = remTable(data)
			debug(1, ">> ResCastCancelled on", nameFromGUID[target], "by", nameFromGUID[caster], "(caster left group)")
			callbacks:Fire("LibResInfo_ResCastCancelled", unitFromGUID[target], target, nil, caster)
		end
	end

	-- Remove data for mass casters no longer in the group:
	for caster in pairs(castingMass) do
		if not unitFromGUID[caster] then
			castingMass[caster] = nil
			debug(1, ">> MassResCancelled by", nameFromGUID[caster], "(left group)")
			callbacks:Fire("LibResInfo_MassResCancelled", nil, caster)
		end
	end

	-- Remove data for targets no longer in the group:
	for caster, data in pairs(castingSingle) do
		local target = data.target
		if not unitFromGUID[target] then
			castingSingle[caster] = remTable(data)
			-- TODO: Is this callback needed, or will the cast cancel on its own?
			debug(1, ">> ResCastCancelled on", nameFromGUID[target], "by", nameFromGUID[caster], "(target left group)")
			callbacks:Fire("LibResInfo_ResCastCancelled", nil, target, unitFromGUID[caster], caster)
		end
	end

	-- Remove data for waiters no longer in the group:
	for target in pairs(hasPending) do
		if not unitFromGUID[target] then
			hasPending[target] = nil
			debug(1, ">> ResExpired on", nameFromGUID[target], "(left group)")
			callbacks:Fire("LibResInfo_ResExpired", nil, target)
		end
	end

	-- Unregister unit events and stop the timer if there are no waiters:
	if not next(hasPending) then
		debug(3, "Nobody pending, stop timer")
		self:Hide()
	end

	-- Unregister CLEU if there are no casts:
	if not next(castingSingle) and not next(castingMass) then
		debug(3, "Nobody casting, unregistering CLEU")
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end

	-- Remove names no longer in the group:
	for guid, name in pairs(nameFromGUID) do
		if not unitFromGUID[guid] then
			debug(4, name, "is no longer in the group")
			nameFromGUID[guid] = nil
		end
	end
end

eventFrame.PLAYER_ENTERING_WORLD = eventFrame.GROUP_ROSTER_UPDATE

------------------------------------------------------------------------

function eventFrame:INCOMING_RESURRECT_CHANGED(event, unit)
	local guid = guidFromUnit[unit]
	if not guid then return end

	local hasRes = UnitHasIncomingResurrection(unit)
	debug(3, event, nameFromGUID[guid], hasRes)

	if hasRes then
		-- Unit has a res incoming. Match it to a spell.
		local now = GetTime()
		for caster, data in pairs(castingSingle) do
			if not data.target and data.startTime - now < 10 then
				-- Found it!
				data.target = guid
				debug(1, ">> ResCastStarted on", nameFromGUID[guid], "by", nameFromGUID[caster], "in", event)
				callbacks:Fire("LibResInfo_ResCastStarted", unit, guid, unitFromGUID[caster], caster, data.endTime)
				break
			end
		end
		-- TODO: Why was I searching for finished casts here???
	else
		-- Check if unit previously had any resses.
		for caster, data in pairs(castingSingle) do
			if data.target == guid then
				debug(4, nameFromGUID[caster], "was casting...")
				if data.startTime then
					debug(4, "...and stopped.")
					castingSingle[caster] = remTable(data)
					debug(1, ">> ResCastCancelled", "on", nameFromGUID[guid], "by", nameFromGUID[casterGUID], "in", event)
					callbacks:Fire("LibResInfo_ResCastCancelled", unit, guid, unitFromGUID[casterGUID], casterGUID)
				else
					debug(4, "...and finished.")
					castingSingle[caster] = remTable(data)
					hasPending[guid] = nil
					debug(1, ">> ResCastFinished", "on", nameFromGUID[guid], "by", nameFromGUID[casterGUID], "in", event)
					callbacks:Fire("LibResInfo_ResCastFinished", unit, guid, unitFromGUID[casterGUID], casterGUID)
					self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
				end
			end
		end
	end
end

------------------------------------------------------------------------

function eventFrame:UNIT_SPELLCAST_START(event, unit, spellName, _, _, spellID)
	if not resSpells[spellID] then return end
	local guid = guidFromUnit[unit]
	if not guid then return end
	debug(3, event, nameFromGUID[guid], "casting", spellName)

	local _, _, _, _, startTime, endTime = UnitCastingInfo(unit)

	if spellID == 83968 then -- Mass Resurrection
		castingMass[guid] = endTime / 1000
		debug(1, ">> MassResStarted", nameFromGUID[guid])
		callbacks:Fire("LibResInfo_MassResStarted", unit, guid, endTime / 1000)
		return
	end

	local data = newTable()
	data.startTime = startTime / 1000
	data.endTime = endTime / 1000
	castingSingle[guid] = data
end

function eventFrame:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, _, _, spellID)
	if not resSpells[spellID] then return end
	local guid = guidFromUnit[unit]
	if not guid then return end

	debug(3, event, nameFromGUID[guid], "finished", spellName)

	if spellID == 83968 then -- Mass Resurrection
		castingMass[guid] = nil
		debug(1, ">> MassResFinished", nameFromGUID[guid])
		callbacks:Fire("LibResInfo_MassResFinished", unit, guid)
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		return
	end

	local data = castingSingle[guid]
	if data then -- No START event for instant cast spells.
		local target = data.target
		if not target then
			-- Probably Soulstone precast on a live target.
			return
		end
		data.finished = true -- Flag so STOP can ignore this.
		debug(1, ">> ResCastFinished", "on", nameFromGUID[target], "by", nameFromGUID[guid], "in", event)
		callbacks:Fire("LibResInfo_ResCastFinished", unitFromGUID[target], target, unit, guid)
	end

	debug(3, "Registering CLEU")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function eventFrame:UNIT_SPELLCAST_STOP(event, unit, spellName, _, _, spellID)
	if not resSpells[spellID] then return end
	local guid = guidFromUnit[unit]
	if not guid then return end

	debug(3, event, nameFromGUID[guid], "stopped", spellName)

	if spellID == 83968 then -- Mass Resurrection
		if not castingMass[guid] then return end -- already SUCCEEDED
		castingMass[guid] = nil
		debug(1, ">> MassResCancelled", nameFromGUID[guid])
		callbacks:Fire("LibResInfo_MassResCancelled", unit, guid)
	else
		local data = castingSingle[guid]
		if data then
			local target = data.target
			local finished = data.finished
			castingSingle[guid] = remTable(data)
			if finished or not target then
				-- no target = Probably Soulstone precast on a live target.
				-- finished = Cast finished. Don't fire a callback or unregister CLEU.
				return
			end
			debug(1, ">> ResCastCancelled", "on", nameFromGUID[target], "by", nameFromGUID[guid])
			callbacks:Fire("LibResInfo_ResCastCancelled", unitFromGUID[target], target, unit, guid)
		end
	end

	-- Unregister CLEU if there are no casts:
	if not next(castingSingle) and not next(castingMass) then
		debug(3, "Nobody casting, unregistering CLEU")
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

eventFrame.UNIT_SPELLCAST_INTERRUPTED = eventFrame.UNIT_SPELLCAST_STOP

------------------------------------------------------------------------

function eventFrame:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool)
	if combatEvent ~= "SPELL_RESURRECT" then return end

	local destUnit = unitFromGUID[destGUID]
	if not destUnit then return end
	debug(3, combatEvent, "on", destName, "by", sourceName)

	local now = GetTime()
	local endTime = now + RESURRECT_PENDING_TIME

	hasPending[destGUID] = endTime

	self:Show()

	debug(1, ">> ResPending", "on", strmatch(destName, "[^%-]+"), "by", strmatch(sourceName, "[^%-]+"))
	callbacks:Fire("LibResInfo_ResPending", destUnit, destGUID, endTime)

	-- Unregister CLEU if there are no casts:
	if not next(castingSingle) and not next(castingMass) then
		-- TODO: Keep track of number of instant casts?
		-- Seems unlikely that multiple casts would end so close together that this would be an issue.
		debug(3, "Nobody casting, unregistering CLEU")
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

------------------------------------------------------------------------

function eventFrame:UNIT_AURA(event, unit)
	local guid = guidFromUnit[unit]
	if not guid then return end
	debug(5, event, unit)

	if not isDead[guid] then
		local stoned = UnitAura(unit, SOULSTONE)
		if stoned ~= hasSoulstone[guid] then
			if not stoned and UnitHealth(unit) <= 1 then
				return
			end
			hasSoulstone[guid] = stoned
			debug(2, nameFromGUID[guid], stoned and "gained" or "lost", SOULSTONE)
		end
		return
	end

	if UnitIsGhost(unit) and not isGhost[guid] then
		isGhost[guid] = true
		if hasPending[guid] then
			hasPending[guid] = nil
			debug(1, ">> ResExpired", nameFromGUID[guid], "(released)")
			callbacks:Fire("LibResInfo_ResExpired", unit, guid)
		end
		-- No need to check next(castingMass) and fire a UnitUpdate here
		-- since Mass Resurrection will still hit units who released.
	end
end

function eventFrame:UNIT_CONNECTION(event, unit)
	local guid = guidFromUnit[unit]
	if not guid then return end
	debug(4, event, unit)

	if hasPending[unit] and not UnitIsConnected(unit) then
		hasPending[guid] = nil
		debug(1, ">> ResExpired", nameFromGUID[guid], "(offline)")
		callbacks:Fire("LibResInfo_ResExpired", unit, guid)
	elseif next(castingMass) then
		for caster, data in pairs(castingSingle) do
			if data.target == guid then
				return
			end
		end
		debug(1, ">> UnitUpdate", nameFromGUID[guid], "(offline)")
		callbacks:Fire("LibResInfo_UnitUpdate", unit, guid)
	end
end

function eventFrame:UNIT_HEALTH(event, unit)
	local guid = guidFromUnit[unit]
	if not guid then return end
	debug(5, event, unit)

	local dead = UnitIsDead(unit)

	if dead and not isDead[guid] then
		debug(2, nameFromGUID[guid], "is now dead")
		isDead[guid] = true
		if hasSoulstone[guid] then
			local endTime = GetTime() + RELEASE_PENDING_TIME
			hasPending[guid] = endTime
			debug(1, ">> ResPending", nameFromGUID[guid], SOULSTONE)
			callbacks:Fire("LibResInfo_ResPending", unit, guid, endTime, true)
		elseif next(castingMass) then
			debug(1, ">> UnitUpdate", nameFromGUID[guid], "(dead)")
			callbacks:Fire("LibResInfo_UnitUpdate", unit, guid)
		end

	elseif isDead[guid] and not dead then
		debug(2, nameFromGUID[guid], "is now alive")
		isDead[guid] = nil
		if hasPending[guid] then
			isGhost[guid] = nil
			hasPending[guid] = nil
			debug(1, ">> ResUsed", nameFromGUID[guid])
			callbacks:Fire("LibResInfo_ResUsed", unit, guid)
		elseif next(castingMass) then
			for caster, data in pairs(castingSingle) do
				if data.target == guid then
					return
				end
			end
			debug(1, ">> UnitUpdate", nameFromGUID[guid], "(alive)")
			callbacks:Fire("LibResInfo_UnitUpdate", unit, guid)
		end
	end
end

------------------------------------------------------------------------

eventFrame:Hide()

local timer, INTERVAL = 0, 0.5
eventFrame:SetScript("OnUpdate", function(self, elapsed)
	timer = timer + elapsed
	if timer >= INTERVAL then
		debug(6, "Timer update")
		if not next(hasPending) then
			debug(4, "Nobody pending, stop timer")
			return self:Hide()
		end
		local now = GetTime()
		for guid, endTime in pairs(hasPending) do
			if endTime - now < INTERVAL then -- It will expire before the next update.
				local unit = unitFromGUID[guid]
				hasPending[guid] = nil
				debug(1, ">> ResExpired", nameFromGUID[guid])
				callbacks:Fire("LibResInfo_ResExpired", unit, guid, true)
			end
		end
		timer = 0
	end
end)

eventFrame:SetScript("OnShow", function()
	debug(4, "Timer start")
end)

eventFrame:SetScript("OnHide", function()
	debug(4, "Timer stop")
	timer = 0
end)

------------------------------------------------------------------------

SLASH_LIBRESINFO1 = "/lri"
SlashCmdList.LIBRESINFO = function(input)
	input = gsub(input, "[^A-Za-z0-9]", "")
	if strlen(input) < 1 then return end
	if strmatch(input, "%D") then
		local f = _G[input]
		if type(f) == "table" and type(f.AddMessage) == "function" then
			DEBUG_FRAME = f
			debug(0, "Debug frame set to", input)
		else
			debug(0, input, "is not a valid debug output frame!")
		end
	else
		local v = tonumber(input)
		if v and v >= 0 then
			DEBUG_LEVEL = v
			debug(0, "Debug level set to", input)
		else
			debug(0, input, "is not a valid debug level!")
		end
	end
end