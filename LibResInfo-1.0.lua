--[[--------------------------------------------------------------------
LibResInfo-0.1.3
Replacement for LibResComm that doesn't require addon communication.
by Phanx <addons@phanx.net>

Development Status:
	* So new it's not even actually a library yet!
	* Needs to get run in actual group play to test the logic.
	* Set DEBUG below to true to get more detailed spam, er, debug messages.
	* Please post bug reports, suggestions, questions, or other comments here:
	  http://www.wowinterface.com/forums/showthread.php?t=43933

Callbacks:
	* ResCastStarted
		* Arguments: casterGUID, targetGUID, startTime, endTime
		* Fires when a group member starts casting a res spell on another group member.
	* ResCastFinished
		* Arguments: casterGUID, targetGUID
		* Fires when a group member successfully finishes casting a res spell on another group member.
	* ResCastCancelled
		* Arguments: casterGUID, targetGUID
		* Fires when a group member stops casting a res spell on another group member.
	* ResPending
		* Arguments: targetGUID
		* Fires when a group member receives a resurrection.
	* ResUsed
		* Arguments: targetGUID
		* Fires when a group member accepts a resurrection.
	* ResExpired
		* Arguments: targetGUID
		* Fires when a group member's resurrection expires, or the group member releases their spirit or disconnects.

Objectives:
	* Know who is casting a res on who
	* Know when each casting res will end
	* Knwo when a casting res ends
	* Know who has a pending res
	* Know when each pending res will expire
	* Know when a pending res expires
	* Know when a pending res is accepted
	* Know when a pending res is declined automatically by releasing spirit or disconnecting

Impossible:
	* Know when a pending res is declined manually
----------------------------------------------------------------------]]

local DEBUG = true

local unitFromGUID = {} -- guid = unit

local isDead = {}       -- dead guid = true

local castTarget = {}   -- caster guid = target guid
local castStart = {}    -- caster guid = cast start time
local castEnd = {}      -- caster guid = cast end time

local resCasting = {}   -- dead guid = # res spells being cast on them
local resPending  = {}  -- dead guid = expiration time

local numCasting = 0    -- # res spells being cast
local numPending = 0    -- # resses available to take

local TIMER_INTERVAL = 0.5

LRI = {
	targets = castTarget,
	starts = castStart,
	ends = castEnd,
	casting = resCasting,
	pending = resPending,
	getCasting = function() return numCasting end,
	getPending = function() return numPending end,
}

------------------------------------------------------------------------

local resSpells = {
	2008,   -- Ancestral Spirit (shaman)
	61999,  -- Raise Ally (death knight)
	20484,  -- Rebirth (druid)
	7238,   -- Redemption (paladin)
	2006,   -- Resurrection (priest)
	115178, -- Resuscitate (monk)
	50769,  -- Revive (druid)
	982,    -- Revive Pet (hunter)
	20707,  -- Soulstone (warlock)
}
for i = #resSpells, 1, -1 do
	local id = resSpells[i]
	local name, _, icon = GetSpellInfo(id)
	if name then
		resSpells[id] = name
		resSpells[name] = id
	end
	resSpells[i] = nil
end

------------------------------------------------------------------------

local validUnits = {
	player = true,
	pet = true,
}
for i = 1, MAX_PARTY_MEMBERS do
	validUnits["party"..i] = true
	validUnits["partypet"..i] = true
end
for i = 1, MAX_RAID_MEMBERS do
	validUnits["raid"..i] = true
	validUnits["raidpet"..i] = true
end

------------------------------------------------------------------------

local f = CreateFrame("Frame")

--f.callbacks = LibStub("CallbackHandler-1.0"):New(f)

f:SetScript("OnEvent", function(self, event, ...)
	return self[event] and self[event](self, ...)
end)

f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("INCOMING_RESURRECT_CHANGED")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("UNIT_SPELLCAST_STOP")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

------------------------------------------------------------------------

function f:GROUP_ROSTER_UPDATE()
	if DEBUG then print("GROUP_ROSTER_UPDATE") end
	wipe(unitFromGUID)
	if IsInRaid() then
		if DEBUG then print("raid") end
		local guid
		for i = 1, GetNumGroupMembers() do
			guid = UnitGUID("raid"..i)
			if guid then
				unitFromGUID[guid] = "raid"..i
			end
			guid = UnitGUID("raidpet"..i)
			if guid then
				unitFromGUID[guid] = "raidpet"..i
			end
		end
	else
		unitFromGUID[UnitGUID("player")] = "player"
		local guid = UnitGUID("pet")
		if guid then
			unitFromGUID[guid] = "pet"
		end
		if IsInGroup() then
			if DEBUG then print("party") end
			for i = 1, GetNumGroupMembers() - 1 do
				guid = UnitGUID("party"..i)
				if guid then
					unitFromGUID[guid] = "party"..i
				end
				guid = UnitGUID("partypet"..i)
				if guid then
					unitFromGUID[guid] = "partypet"..i
				end
			end
		else
			if DEBUG then print("solo") end
		end
	end
--[[
	-- Someone left the group while casting a res.
	-- Find who they were casting on and cancel it.
	for caster in pairs(castStart) do
		if unitFromGUID[caster] then
			if DEBUG then print((UnitName(unitFromGUID[caster])), "left while casting") end
			local target = castTarget[caster]
			if target then
				print(">> ResCastCancelled", (UnitName(unitFromGUID[caster])), (UnitName(unitFromGUID[target])))
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
			if DEBUG then print((UnitName(unitFromGUID[target])), "left while incoming") end
			for caster, castertarget in pairs(castTarget) do
				if target == castertarget then
					print(">> ResCastCancelled", (UnitName(unitFromGUID[caster])), (UnitName(unitFromGUID[target])))
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
			if DEBUG then print((UnitName(unitFromGUID[target])), "left while pending") end
			print(">> ResExpired", (UnitName(unitFromGUID[target])))
			resPending[target] = nil
			numPending = numPending - 1
		end
	end

	-- Check events
	if DEBUG then print("# pending:", numPending) end
	if numPending == 0 then
		self:UnregisterEvent("UNIT_HEALTH")
	end

	local most = 0
	for _, n in pairs(resCasting) do
		most = max(n, most)
	end
	if DEBUG then print("highest # casting:", most) end
	if most < 2 then
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
]]
end

------------------------------------------------------------------------

function f:INCOMING_RESURRECT_CHANGED(unit)
	if validUnits[unit] then
		local guid = UnitGUID(unit)
		local hasRes = UnitHasIncomingResurrection(unit)
		if DEBUG then print("INCOMING_RESURRECT_CHANGED", "=>", (UnitName(unit)), "=>", hasRes) end

		if hasRes then
			local now, found = GetTime() * 1000
			for caster, startTime in pairs(castStart) do
				if startTime - now < 10 and not castTarget[caster] then -- time in ms between cast start and res gain
					castTarget[caster] = guid
					if resCasting[guid] then
						resCasting[guid] = resCasting[guid] + 1
					else
						resCasting[guid] = 1
					end
					print(">> ResCastStarted", (UnitName(unitFromGUID[caster])), (UnitName(unit)), resCasting[guid], now - startTime)
					found = true
				end
			end
			if not found then
				if DEBUG then print("No new caster found.") end
			end
			for caster, target in pairs(castTarget) do
				if target == guid and not castStart[caster] then
					-- finished casting
					print(">> ResCastFinished", (UnitName(unitFromGUID[caster])), (UnitName(unit)))
					castTarget[caster], castEnd[caster] = nil, nil
					numCasting = numCasting + 1
					if numCasting > 0 then
						if DEBUG then print(numCasting, "casting, waiting for CLEU") end
						self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
					end
				end
			end

		elseif resCasting[guid] then
			-- had a res, doesn't anymore
			local finished, stopped
			for caster, target in pairs(castTarget) do
				if target == guid then
					if DEBUG then print((UnitName(unitFromGUID[caster])), "was casting...") end
					if castStart[caster] then
						if DEBUG then print("...and stopped.") end
						stopped = caster
					else
						if DEBUG then print("...and finished.") end
						finished = caster
					end
					castStart[caster], castEnd[caster], castTarget[caster] = nil, nil, nil
					break
				end
			end
			if stopped then
				print(">> ResCastCancelled", (UnitName(unitFromGUID[stopped])), (UnitName(unit)))
				resCasting[guid] = nil
			elseif finished then
				print(">> ResCastFinished", (UnitName(unitFromGUID[finished])), (UnitName(unit)))
				numCasting = numCasting + 1
				if numCasting > 0 then
					if DEBUG then print(numCasting, "casting, waiting for CLEU") end
					self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
				end
			end
		end
	end
end

------------------------------------------------------------------------

function f:UNIT_SPELLCAST_START(unit, spellName, _, _, spellID)
	if validUnits[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if DEBUG then print("UNIT_SPELLCAST_START", "=>", (UnitName(unit)), "=>", spellName) end

		local name, _, _, _, startTime, endTime = UnitCastingInfo(unit)
		if DEBUG then print("UnitCastingInfo =>", name, startTime, endTime) end

		castStart[guid] = startTime
		castEnd[guid] = endTime
	end
end

function f:UNIT_SPELLCAST_SUCCEEDED(unit, spellName, _, _, spellID)
	if validUnits[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			if DEBUG then print("UNIT_SPELLCAST_SUCCEEDED", "=>", (UnitName(unit)), "=>", spellName) end
			castStart[guid] = nil
		end
	end
end

function f:UNIT_SPELLCAST_STOP(unit, spellName, _, _, spellID)
	if validUnits[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			if DEBUG then print("UNIT_SPELLCAST_STOP", "=>", (UnitName(unit)), "=>", spellName) end
			local target = castTarget[guid]
			if target then
				local n = resCasting[target]
				if n and n > 1 then
					-- someone else is still casting, send cancellation here
					print(">> ResCastCancelled", (UnitName(unit)), (UnitName(unitFromGUID[target])))
					castStart[guid], castEnd[guid], castTarget[guid] = nil, nil
					resCasting[target] = n - 1
				else
					if DEBUG then print("Waiting for INCOMING_RESURRECT_CHANGED.") end
				end
			end
		end
	end
end

function f:UNIT_SPELLCAST_INTERRUPTED(unit, spellName, _, lineID, spellID)
	if validUnits[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			if DEBUG then print("UNIT_SPELLCAST_INTERRUPTED", "=>", (UnitName(unit)), "=>", spellName) end
			local target = castTarget[guid]
			if target then
				local n = resCasting[target]
				if n and n > 1 then
					-- someone else is still casting, send cancellation here
					print(">> ResCastCancelled", (UnitName(unit)), (UnitName(unitFromGUID[target])))
					castStart[guid], castEnd[guid], castTarget[guid] = nil, nil
					resCasting[target] = n - 1
				else
					if DEBUG then print("Waiting for INCOMING_RESURRECT_CHANGED.") end
				end
			end
		end
	end
end

------------------------------------------------------------------------

function f:COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool)
	if event == "SPELL_RESURRECT" then
		timestamp = GetTime() * 1000
		if DEBUG then print("SPELL_RESURRECT", timestamp, "=>", sourceName, "=>", spellName, "=>", destName) end
		if resCasting[destGUID] then
			print(">> ResPending", sourceName, destName)
			if resCasting[destGUID] > 1 then
				resCasting[destGUID] = resCasting[destGUID] - 1
			else
				resCasting[destGUID] = nil
			end
			resPending[destGUID] = timestamp + 120

			numCasting = numCasting - 1
			if numCasting == 0 then
				if DEBUG then print("0 casting, unregister CLEU") end
				self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			end

			numPending = numPending + 1
			if numPending > 0 then
				if DEBUG then print(numPending, "pending, register UNIT_HEALTH, start timer") end
				self:RegisterEvent("UNIT_HEALTH")
				self:Show()
			end
		end
	end
end

------------------------------------------------------------------------

function f:UNIT_HEALTH(unit)
	if validUnits[unit] then
		local guid = UnitGUID(unit)
		if resPending[guid] then
			if DEBUG then print("UNIT_HEALTH", (UnitName(unit)), "/ Dead?", UnitIsDead(unit) and "Y" or "N", "/ Ghost?", UnitIsGhost(unit) and "Y" or "N", "/ Offline?", UnitIsConnected(unit) and "N" or "Y") end
			local lost
			if UnitIsGhost(unit) or not UnitIsConnected(unit) then
				print(">> ResExpired", (UnitName(unit)))
				lost = true
			elseif not UnitIsDead(unit) then
				print(">> ResUsed", (UnitName(unit)))
				lost = true
			end
			if lost then
				resPending[guid] = nil
				numPending = numPending - 1
				if numPending == 0 then
					self:UnregisterEvent("UNIT_HEALTH")
				end
			end
		end
	end
end

------------------------------------------------------------------------

f:Hide()

local timer = 0
f:SetScript("OnUpdate", function(self, elapsed)
	timer = timer + elapsed
	if timer > TIMER_INTERVAL then
		local now = GetTime()
		for guid, expiry in pairs(resPending) do
			if expiry - now < 0 then
				print(">> ResExpired", (UnitName(unitFromGUID[guid])))
				resPending[guid] = nil
				numPending = numPending - 1
				if numPending == 0 then
					self:UnregisterEvent("UNIT_HEALTH")
					self:Hide()
				end
			end
		end
		timer = 0
	end
end)