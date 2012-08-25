--[[--------------------------------------------------------------------
LibResInfo-1.0
Library to provide information about resurrections in your group.
Copyright (c) 2012 A. Kinley <addons@phanx.net>. All rights reserved.
See the accompanying README and LICENSE files for more information.

Things to do:
	* Refactor messy and redundant sections
	* Detect resurrections being cast on group members by players who join the group while casting.
	* Detect resurrections being cast by group members on players who join the group while being resurrected.

Things that can't be done:
	* Detect when a pending res is declined manually.
	* Detect pending resurrections when either the caster or target was not in the group when the cast completed,
	  but joined the group before the res expired.
----------------------------------------------------------------------]]

local DEBUG_LEVEL = 1
local DEBUG_FRAME = ChatFrame1

------------------------------------------------------------------------

local MAJOR, MINOR = "LibResInfo-1.0", 1
assert(LibStub, MAJOR.." requires LibStub")
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

------------------------------------------------------------------------

lib.callbacks = lib.callbacks or LibStub:GetLibrary("CallbackHandler-1.0"):New(lib)

lib.eventFrame = lib.eventFrame or CreateFrame("Frame")

lib.guidFromUnit = lib.guidFromUnit or {}
lib.nameFromGUID = lib.nameFromGUID or {}
lib.unitFromGUID = lib.unitFromGUID or {}

lib.castTarget = lib.castTarget or {}
lib.castStart = lib.castStart or {}
lib.castEnd = lib.castEnd or {}

lib.resCasting = lib.resCasting or {}
lib.resPending = lib.resPending or {}

lib.total = lib.total or {}

------------------------------------------------------------------------

local callbacks = lib.callbacks
local f = lib.eventFrame

local guidFromUnit = lib.guidFromUnit -- unit = guid
local nameFromGUID = lib.nameFromGUID -- guid = name
local unitFromGUID = lib.unitFromGUID -- guid = unit

local castTarget = lib.castTarget -- caster guid = target guid
local castStart = lib.castStart   -- caster guid = cast start time
local castEnd = lib.castEnd       -- caster guid = cast end time

local resCasting = lib.resCasting -- dead guid = # res spells being cast on them
local resPending  = lib.resPending  -- dead guid = expiration time

local total = lib.total
total.casting = total.casting or 0 -- # res spells being cast
total.pending = total.pending or 0 -- # resses available to take

if DEBUG_LEVEL > 0 then
	LRI = {
		unitFromGUID = unitFromGUID,

		castTarget = castTarget,
		castStart = castStart,
		castEnd = castEnd,

		resCasting = resCasting,
		resPending = resPending,

		total = total,
	}
end

------------------------------------------------------------------------

local resSpells = {
	[2008]   = GetSpellInfo(2008),   -- Ancestral Spirit (shaman)
	[8342]   = GetSpellInfo(8342),   -- Defibrillate (item: Goblin Jumper Cables)
	[22999]  = GetSpellInfo(22999),  -- Defibrillate (item: Goblin Jumper Cables XL)
	[54732]  = GetSpellInfo(54732),  -- Defibrillate (item: Gnomish Army Knife)
	[61999]  = GetSpellInfo(61999),  -- Raise Ally (death knight)
	[20484]  = GetSpellInfo(20484),  -- Rebirth (druid)
	[7238]   = GetSpellInfo(7238),   -- Redemption (paladin)
	[2006]   = GetSpellInfo(2006),   -- Resurrection (priest)
	[115178] = GetSpellInfo(115178), -- Resuscitate (monk)
	[50769]  = GetSpellInfo(50769),  -- Revive (druid)
	[982]    = GetSpellInfo(982),    -- Revive Pet (hunter)
	[20707]  = GetSpellInfo(20707),  -- Soulstone (warlock)
}

------------------------------------------------------------------------

f.callbacks = LibStub("CallbackHandler-1.0"):New(f)

f:SetScript("OnEvent", function(self, event, ...)
	return self[event] and self[event](self, event, ...)
end)

f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("INCOMING_RESURRECT_CHANGED")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("UNIT_SPELLCAST_STOP")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

------------------------------------------------------------------------

local function debug(level, text, ...)
	if level <= DEBUG_LEVEL then
		if (...) then
			if type(text) == "string" and strfind(text, "%%[dfqsx%d%.]") then
				text = format(text, ...)
			else
				text = strjoin(" ", tostringall(text, ...))
			end
		end
		DEBUG_FRAME:AddMessage("|cff00ddba[LRI]|r " .. text)
	end
end

------------------------------------------------------------------------

function lib:UnitHasIncomingRes(unit)
	debug(2, "UnitHasIncomingRes", unit)
	local guid
	if strmatch(unit, "^0x") then
		guid = unit
		unit = unitFromGUID[unit]
	else
		guid = UnitGUID(unit)
		unit = unitFromGUID[guid]
	end
	if guid and unit then
		debug(3, unit, guid, nameFromGUID[guid])
		if resPending[guid] then
			debug(3, true, nil, nil, resPending[guid])
			return true, nil, nil, resPending[guid]
		else
			local single, firstCaster, firstEnd = resCasting[guid] == 1
			for casterGUID, targetGUID in pairs(castTarget) do
				if targetGUID == guid then
					local endTime = castEnd[casterGUID]
					if single then
						debug(3, true, unitFromGUID[casterGUID], casterGUID, endTime)
						return true, unitFromGUID[casterGUID], casterGUID, endTime
					elseif not firstEnd or endTime < firstEnd then
						firstCaster, firstEnd = casterGUID, endTime
					end
				end
			end
			if firstCaster then
				debug(3, true, unitFromGUID[firstCaster], firstCaster, firstEnd)
				return true, unitFromGUID[firstCaster], firstCaster, firstEnd
			end
		end
	end
	debug(3, "nil")
end

function lib:UnitIsCastingRes(unit)
	debug(2, "UnitIsCastingRes", unit)
	local guid
	if strmatch(unit, "^0x") then
		guid = unit
		unit = unitFromGUID[unit]
	else
		guid = UnitGUID(unit)
		unit = unitFromGUID[guid]
	end
	if guid and unit then
		debug(3, unit, guid, nameFromGUID[guid])
		local isFirst, targetGUID, endTime = true, castTarget[guid], castEnd[guid]
		if targetGUID then
			if resPending[targetGUID] then
				isFirst = nil
			else
				for k, v in pairs(castTarget) do
					if k ~= guid and v == targetGUID and castEnd[k] < endTime then
						isFirst = nil
						break
					end
				end
			end
			debug(3, unitFromGUID[targetGUID], targetGUID, endTime, isFirst)
			return unitFromGUID[targetGUID], targetGUID, endTime, isFirst
		end
	end
	debug(3, "nil")
end

------------------------------------------------------------------------

local unitFromGUID_old, guidFromUnit_old = {}, {}

function f:GROUP_ROSTER_UPDATE()
	debug(2, "GROUP_ROSTER_UPDATE")

	wipe(guidFromUnit_old)
	wipe(unitFromGUID_old)
	for k,v in pairs(unitFromGUID) do
		unitFromGUID_old[k] = v
		unitFromGUID[k] = nil
	end
	for k,v in pairs(guidFromUnit) do
		guidFromUnit_old[k] = v
		guidFromUnit[k] = nil
	end

	if IsInRaid() then
		debug(3, "raid")
		local unit, guid
		for i = 1, GetNumGroupMembers() do
			unit = "raid"..i
			guid = UnitGUID(unit)
			if guid then
				guidFromUnit[unit] = guid
				nameFromGUID[guid] = UnitName(unit)
				unitFromGUID[guid] = unit
			end
			unit = "raidpet"..i
			guid = UnitGUID(unit)
			if guid then
				guidFromUnit[unit] = guid
				nameFromGUID[guid] = UnitName(unit)
				unitFromGUID[guid] = unit
			end
		end
	else
		local unit, guid = "player", UnitGUID("player")
		guidFromUnit[unit] = guid
		nameFromGUID[guid] = UnitName(unit)
		unitFromGUID[guid] = unit

		unit, guid = "pet", UnitGUID("pet")
		if guid then
			guidFromUnit[unit] = guid
			nameFromGUID[guid] = UnitName(unit)
			unitFromGUID[guid] = unit
		end

		if IsInGroup() then
			debug(3, "party")
			for i = 1, GetNumGroupMembers() - 1 do
				unit = "party"..i
				guid = UnitGUID(unit)
				if guid then
					guidFromUnit[unit] = guid
					nameFromGUID[guid] = UnitName(unit)
					unitFromGUID[guid] = unit
				end
				unit = "partypet"..i
				guid = UnitGUID(unit)
				if guid then
					guidFromUnit[unit] = guid
					nameFromGUID[guid] = UnitName(unit)
					unitFromGUID[guid] = unit
				end
			end
		else
			debug(3, "solo")
		end
	end

	-- Someone left the group while casting a res.
	-- Find who they were casting on and cancel it.
	for caster in pairs(castEnd) do
		if not unitFromGUID[caster] then
			debug(3, nameFromGUID[caster], "left while casting.")
			local target = castTarget[caster]
			if target then
				debug(1, ">> ResCastCancelled", "=>", nameFromGUID[caster], "=>", nameFromGUID[target])
				callbacks:Fire("LibResInfo_ResCastCancelled", unitFromGUID_old[caster], caster, unitFromGUID[target], target)
				if resCasting[target] > 1 then
					resCasting[target] = resCasting[target] - 1
				else
					resCasting[target] = nil
				end
				castTarget[caster] = nil
			end
			castStart[caster], castEnd[caster] = nil, nil
		end
	end

	-- Someone left the group while a res was being cast on them.
	-- Find the cast and cancel it.
	for target, n in pairs(resCasting) do
		if not unitFromGUID[target] then
			debug(3, nameFromGUID[target], "left while incoming.")
			for caster, castertarget in pairs(castTarget) do
				if target == castertarget then
					debug(1, ">> ResCastCancelled", "=>", nameFromGUID[caster], "=>", nameFromGUID[target])
					callbacks:Fire("LibResInfo_ResCastCancelled", unitFromGUID[caster], caster, unitFromGUID_old[target], target)
					castTarget[caster], castStart[caster], castEnd[caster] = nil, nil, nil
					resCasting[target] = nil
				end
			end
		end
	end

	-- Someone left the group when they had a res available.
	-- Find the res and cancel it.
	for target in pairs(resPending) do
		if not unitFromGUID[target] then
			debug(2, nameFromGUID[target], "left while pending.")
			debug(1, ">> ResExpired", "=>", nameFromGUID[target])
			callbacks:Fire("LibResInfo_ResExpired", unitFromGUID_old[target], target)
			resPending[target] = nil
			total.pending = total.pending - 1
		end
	end

	-- Check events
	debug(2, "# pending:", total.pending)
	if total.pending == 0 then
		self:UnregisterEvent("UNIT_HEALTH")
		self:Hide()
	end

	local most = 0
	for _, n in pairs(resCasting) do
		most = max(n, most)
	end
	debug(2, "highest # casting:", most)
	if most < 2 then
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end

	for guid, name in pairs(nameFromGUID) do
		if not unitFromGUID[guid] then
			nameFromGUID[guid] = nil
		end
	end
end

------------------------------------------------------------------------

function f:INCOMING_RESURRECT_CHANGED(event, unit)
	if guidFromUnit[unit] then
		local guid = UnitGUID(unit)
		local hasRes = UnitHasIncomingResurrection(unit)
		debug(2, "INCOMING_RESURRECT_CHANGED", "=>", name, "=>", hasRes)

		if hasRes then
			local now, found = GetTime()
			for casterGUID, startTime in pairs(castStart) do
				if startTime - now < 10 and not castTarget[casterGUID] then -- time in ms between cast start and res gain
					castTarget[casterGUID] = guid
					if resCasting[guid] then
						resCasting[guid] = resCasting[guid] + 1
					else
						resCasting[guid] = 1
					end
					local casterUnit = unitFromGUID[casterGUID]
					debug(1, ">> ResCastStarted", nameFromGUID[casterGUID], "=>", nameFromGUID[guid], "DIFF", now - startTime, "#", resCasting[guid])
					callbacks:Fire("LibResInfo_ResCastStarted", casterUnit, casterGUID, unit, guid, now - startTime)
					found = true
				end
			end
			if not found then
				debug(3, "No new cast found.")
			end
			for casterGUID, targetGUID in pairs(castTarget) do
				if targetGUID == guid and not castStart[casterGUID] then
					-- finished casting
					local casterUnit = unitFromGUID[casterGUID]
					debug(1, ">> ResCastFinished", nameFromGUID[casterGUID], "=>", nameFromGUID[guid], "#", resCasting[guid])
					callbacks:Fire("LibResInfo_ResCastFinished", casterUnit, casterGUID, unit, guid)
					castTarget[casterGUID], castEnd[casterGUID] = nil, nil
					local n = total.casting
					n = n + 1
					if n > 0 then
						debug(3, n, "casting, waiting for CLEU")
						self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
					end
					total.casting = n
				end
			end

		elseif resCasting[guid] then
			-- had a res, doesn't anymore
			local finished, stopped
			for casterGUID, targetGUID in pairs(castTarget) do
				if targetGUID == guid then
					debug(3, nameFromGUID[casterGUID], "was casting...")
					if castStart[casterGUID] then
						debug(3, "...and stopped.")
						stopped = casterGUID
					else
						debug(3, "...and finished.")
						finished = casterGUID
					end
					castStart[casterGUID], castEnd[casterGUID], castTarget[casterGUID] = nil, nil, nil
					break
				end
			end
			if stopped then
				local casterUnit = unitFromGUID[stopped]
				debug(1, ">> ResCastCancelled", nameFromGUID[casterGUID], "=>", nameFromGUID[guid], "#", resCasting[guid] - 1)
				callbacks:Fire("LibResInfo_ResCastCancelled", casterUnit, stopped, unit, guid)
				resCasting[guid] = nil
			elseif finished then
				debug(1, ">> ResCastFinished", nameFromGUID[casterGUID], "=>", nameFromGUID[guid], "#", resCasting[guid] - 1)
				callbacks:Fire("LibResInfo_ResCastFinished", casterUnit, casterGUID, unit, guid)
				local n = total.casting
				n = n + 1
				if n > 0 then
					debug(2, n, "casting, waiting for CLEU")
					self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
				end
				total.casting = n
			end
		end
	end
end

------------------------------------------------------------------------

function f:UNIT_SPELLCAST_START(event, unit, spellName, _, _, spellID)
	if guidFromUnit[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		debug(2, event, "=>", nameFromGUID[guid], "=>", spellName)

		local _, _, _, _, startTime, endTime = UnitCastingInfo(unit)
		debug(3, "UnitCastingInfo =>", spellName, startTime / 1000, endTime / 1000)

		castStart[guid] = startTime / 1000
		castEnd[guid] = endTime / 1000
	end
end

function f:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, _, _, spellID)
	if guidFromUnit[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			debug(2, event, "=>", nameFromGUID[guid], "=>", spellName)
			castStart[guid] = nil
		end
	end
end

function f:UNIT_SPELLCAST_STOP(event, unit, spellName, _, _, spellID)
	if guidFromUnit[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			debug(2, event, "=>", nameFromGUID[guid], "=>", spellName)
			local targetGUID = castTarget[guid]
			if targetGUID then
				local n = resCasting[targetGUID]
				if n and n > 1 then
					-- someone else is still casting, send cancellation here
					local targetUnit = unitFromGUID[targetGUID]
					debug(1, ">> ResCastCancelled", nameFromGUID[guid], "=>", nameFromGUID[targetGUID])
					callbacks:Fire("LibResInfo_ResCastCancelled", unit, guid, targetUnit, targetGUID)
					castStart[guid], castEnd[guid], castTarget[guid] = nil, nil
					resCasting[targetGUID] = n - 1
				else
					debug(3, "Waiting for INCOMING_RESURRECT_CHANGED.")
				end
			end
		end
	end
end

f.UNIT_SPELLCAST_INTERRUPTED = f.UNIT_SPELLCAST_STOP

------------------------------------------------------------------------

function f:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool)
	if combatEvent == "SPELL_RESURRECT" then
		local now = GetTime()
		debug(2, combatEvent, "=>", sourceName, "=>", spellName, "=>", destName)
		if resCasting[destGUID] then
			debug(1, ">> ResPending", sourceName, "=>", destName)
			callbacks:Fire("LibResInfo_ResPending", unitFromGUID[destGUID], destGUID, now + 60)
			if resCasting[destGUID] > 1 then
				resCasting[destGUID] = resCasting[destGUID] - 1
			else
				resCasting[destGUID] = nil
			end

			local new = not resPending[destGUID]
			resPending[destGUID] = now + 60

			total.casting = total.casting - 1
			if total.casting == 0 then
				debug(3, "0 casting, unregister CLEU")
				self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			end

			if new then
				total.pending = total.pending + 1
				debug(3, total.pending, "pending, start timer, register UNIT_HEALTH/AURA")
				self:RegisterEvent("UNIT_HEALTH")
				self:RegisterEvent("UNIT_AURA")
				self:Show()
			else
				debug(3, total.pending, "pending, timer already running")
			end
		end
	end
end

------------------------------------------------------------------------

function f:UNIT_HEALTH(event, unit)
	local guid = guidFromUnit[unit]
	if guidFromUnit[unit] then
			debug(2, event, nameFromGUID[guid], "Dead", UnitIsDead(unit), "Ghost", UnitIsGhost(unit), "Offline", not UnitIsConnected(unit))
		if resPending[guid] then
			local lost
			if UnitIsGhost(unit) or not UnitIsConnected(unit) then
				debug(1, ">> ResExpired", nameFromGUID[guid])
				callbacks:Fire("LibResInfo_ResExpired", unit, guid)
				lost = true
			elseif not UnitIsDead(unit) then
				debug(1, ">> ResUsed", nameFromGUID[guid])
				callbacks:Fire("LibResInfo_ResUsed", unit, guid)
				lost = true
			end
			if lost then
				resPending[guid] = nil
				total.pending = total.pending - 1
				if total.pending == 0 then
					debug(3, "0 pending, unregister UNIT_HEALTH/AURA")
					self:UnregisterEvent("UNIT_AURA")
					self:UnregisterEvent("UNIT_HEALTH")
				end
			end
		end
	end
end

f.UNIT_AURA = f.UNIT_HEALTH

------------------------------------------------------------------------

f:Hide()

local timer = 0
local INTERVAL = 0.5
f:SetScript("OnUpdate", function(self, elapsed)
	timer = timer + elapsed
	if timer >= INTERVAL then
		debug(5, "timer update")
		local now = GetTime()
		for guid, expiry in pairs(resPending) do
			if expiry - now < INTERVAL then -- will expire before next update
				local unit = unitFromGUID[guid]
				debug(1, ">> ResExpired", nameFromGUID[guid])
				callbacks:Fire("LibResInfo_ResExpired", unit, guid)
				resPending[guid] = nil
				total.pending = total.pending - 1
				if total.pending == 0 then
					self:UnregisterEvent("UNIT_HEALTH")
					self:Hide()
				end
			end
		end
		timer = 0
	end
end)

f:SetScript("OnShow", function()
	debug(2, "timer start")
end)

f:SetScript("OnHide", function()
	debug(2, "timer stop")
	timer = 0
end)