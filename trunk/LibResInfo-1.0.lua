--[[--------------------------------------------------------------------
LibResInfo-1.0
Library to provide information about resurrections in your group.
Copyright (c) 2012 A. Kinley <addons@phanx.net>. All rights reserved.
See the accompanying README and LICENSE files for more information.

Things to do:
	* Add callbacks (basically done)
	* Add API functions
	* Refactor messy and redundant sections

Things that can't be done:
	* Know when a pending res is declined manually
----------------------------------------------------------------------]]

local DEBUG_LEVEL = 1

------------------------------------------------------------------------

local MAJOR, MINOR = "LibResInfo-1.0", 1
assert(LibStub, MAJOR.." requires LibStub")
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

------------------------------------------------------------------------

lib.callbacks = lib.callbacks or LibStub:GetLibrary("CallbackHandler-1.0"):New(lib)
lib.eventFrame = lib.eventFrame or CreateFrame("Frame")

lib.unitFromGUID = lib.unitFromGUID or {}

lib.castTarget = lib.castTarget or {}
lib.castStart = lib.castStart or {}
lib.castEnd = lib.castEnd or {}

lib.resIncoming = lib.resIncoming or {}
lib.resPending = lib.resPending or {}

lib.total = lib.total or {}

------------------------------------------------------------------------

local callbacks = lib.callbacks
local f = lib.eventFrame

local unitFromGUID = lib.unitFromGUID -- guid = unit

local castTarget = lib.castTarget -- caster guid = target guid
local castStart = lib.castStart   -- caster guid = cast start time
local castEnd = lib.castEnd       -- caster guid = cast end time

local resIncoming = lib.resIncoming -- dead guid = # res spells being cast on them
local resPending  = lib.resPending  -- dead guid = expiration time

local total = lib.total
total.casting = total.casting or 0 -- # res spells being cast
total.pending = total.pending or 0 -- # resses available to take

------------------------------------------------------------------------

local resSpells = {
	2008,   -- Ancestral Spirit (shaman)
	8342,   -- Defibrillate (item: Goblin Jumper Cables)
	22999,  -- Defibrillate (item: Goblin Jumper Cables XL)
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
	resSpells[id] = GetSpellInfo(id)
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

--f.callbacks = LibStub("CallbackHandler-1.0"):New(f)

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
			if strfind(text, "%%[dfqsx%d%.]") then
				print("|cff00ddba[LRI]|r", format(text, ...))
			else
				print("|cff00ddba[LRI]|r", text, ...)
			end
		else
			print("|cff00ddba[LRI]|r", text)
		end
	end
end

------------------------------------------------------------------------

function f:GROUP_ROSTER_UPDATE()
	debug(1, "GROUP_ROSTER_UPDATE")
	wipe(unitFromGUID)
	if IsInRaid() then
		debug(2, "raid")
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
			debug(2, "party")
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
			debug(2, "solo")
		end
	end
--[[
	-- Someone left the group while casting a res.
	-- Find who they were casting on and cancel it.
	for caster in pairs(castStart) do
		if unitFromGUID[caster] then
			debug(1, (UnitName(unitFromGUID[caster])), "left while casting")
			local target = castTarget[caster]
			if target then
				print(">> ResCastCancelled", (UnitName(unitFromGUID[caster])), (UnitName(unitFromGUID[target])))
				if resIncoming[target] > 1 then
					resIncoming[target] = resIncoming[target] - 1
				else
					resIncoming[target] = nil
				end
				castTarget[caster] = nil
			end
			castStart[caster], castEnd[caster] = nil, nil
		end
	end

	-- Someone left the group while a res was being cast on them.
	-- Find the cast and cancel it.
	for target, n in pairs(resIncoming) do
		if not unitFromGUID[target] then
			debug(1, (UnitName(unitFromGUID[target])), "left while incoming")
			for caster, castertarget in pairs(castTarget) do
				if target == castertarget then
					print(">> ResCastCancelled", (UnitName(unitFromGUID[caster])), (UnitName(unitFromGUID[target])))
					castTarget[caster], castStart[caster], castEnd[caster] = nil, nil, nil
					resIncoming[target] = nil
				end
			end
		end
	end

	-- Someone left the group when they had a res available.
	-- Find the res and cancel it.
	for target in pairs(resPending) do
		if not unitFromGUID[target] then
			debug(1, (UnitName(unitFromGUID[target])), "left while pending")
			print(">> ResExpired", (UnitName(unitFromGUID[target])))
			resPending[target] = nil
			total.pending = total.pending - 1
		end
	end

	-- Check events
	debug(1, "# pending:", total.pending)
	if total.pending == 0 then
		self:UnregisterEvent("UNIT_HEALTH")
	end

	local most = 0
	for _, n in pairs(resIncoming) do
		most = max(n, most)
	end
	debug(1, "highest # casting:", most)
	if most < 2 then
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
]]
end

------------------------------------------------------------------------

function f:INCOMING_RESURRECT_CHANGED(event, unit)
	if validUnits[unit] then
		local guid = UnitGUID(unit)
		local name = UnitName(unit)
		local hasRes = UnitHasIncomingResurrection(unit)
		debug(1, "INCOMING_RESURRECT_CHANGED", "=>", name, "=>", hasRes)

		if hasRes then
			local now, found = GetTime() * 1000
			for casterGUID, startTime in pairs(castStart) do
				if startTime - now < 10 and not castTarget[casterGUID] then -- time in ms between cast start and res gain
					castTarget[casterGUID] = guid
					if resIncoming[guid] then
						resIncoming[guid] = resIncoming[guid] + 1
					else
						resIncoming[guid] = 1
					end
					local casterUnit = unitFromGUID[casterGUID]
					print(">> ResCastStarted", (UnitName(casterUnit)), "=>", name, "ETA", now - startTime, "#", resIncoming[guid])
					-- callbacks:Fire("LibResInfo_ResCastStarted", casterUnit, casterGUID, unit, guid, now - startTime)
					found = true
				end
			end
			if not found then
				debug(2, "No new cast found.")
			end
			for casterGUID, targetGUID in pairs(castTarget) do
				if targetGUID == guid and not castStart[casterGUID] then
					-- finished casting
					local casterUnit = unitFromGUID[casterGUID]
					print(">> ResCastFinished", (UnitName(casterUnit)), "=>", name, "#", resIncoming[guid])
					-- callbacks:Fire("LibResInfo_ResCastFinished", casterUnit, casterGUID, unit, guid)
					castTarget[casterGUID], castEnd[casterGUID] = nil, nil
					local n = total.casting
					n = n + 1
					if n > 0 then
						debug(2, n, "casting, waiting for CLEU")
						self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
					end
					total.casting = n
				end
			end

		elseif resIncoming[guid] then
			-- had a res, doesn't anymore
			local finished, stopped
			for casterGUID, targetGUID in pairs(castTarget) do
				if targetGUID == guid then
					debug(2, (UnitName(unitFromGUID[casterGUID])), "was casting...")
					if castStart[casterGUID] then
						debug(2, "...and stopped.")
						stopped = casterGUID
					else
						debug(2, "...and finished.")
						finished = casterGUID
					end
					castStart[casterGUID], castEnd[casterGUID], castTarget[casterGUID] = nil, nil, nil
					break
				end
			end
			if stopped then
				local casterUnit = unitFromGUID[stopped]
				print(">> ResCastCancelled", (UnitName(casterUnit)), "=>", name, "#", resIncoming[guid])
				-- callbacks:Fire("LibResInfo_ResCastCancelled", casterUnit, stopped, unit, guid)
				resIncoming[guid] = nil
			elseif finished then
				print(">> ResCastFinished", (UnitName(casterUnit)), "=>", name, "#", resIncoming[guid])
				-- callbacks:Fire("LibResInfo_ResCastFinished", casterUnit, casterGUID, unit, guid)
				local n = total.casting
				n = n + 1
				if n > 0 then
					debug(1, n, "casting, waiting for CLEU")
					self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
				end
				total.casting = n
			end
		end
	end
end

------------------------------------------------------------------------

function f:UNIT_SPELLCAST_START(event, unit, spellName, _, _, spellID)
	if validUnits[unit] and resSpells[spellID] then
		debug(1, event, "=>", (UnitName(unit)), "=>", spellName)

		local name, _, _, _, startTime, endTime = UnitCastingInfo(unit)
		debug(2, "UnitCastingInfo =>", name, startTime, endTime)

		local guid = UnitGUID(unit)
		castStart[guid] = startTime
		castEnd[guid] = endTime
	end
end

function f:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, _, _, spellID)
	if validUnits[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			debug(1, event, "=>", (UnitName(unit)), "=>", spellName)
			castStart[guid] = nil
		end
	end
end

function f:UNIT_SPELLCAST_STOPevent, (unit, spellName, _, _, spellID)
	if validUnits[unit] and resSpells[spellID] then
		local guid = UnitGUID(unit)
		if castStart[guid] then
			debug(1, event, "=>", (UnitName(unit)), "=>", spellName)
			local targetGUID = castTarget[guid]
			if targetGUID then
				local n = resIncoming[targetGUID]
				if n and n > 1 then
					-- someone else is still casting, send cancellation here
					local targetUnit = unitFromGUID[targetGUID]
					print(">> ResCastCancelled", (UnitName(unit)), "=>", (UnitName(targetUnit)))
					-- callbacks:Fire("LibResInfo_ResCastCancelled", unit, guid, targetUnit, targetGUID)
					castStart[guid], castEnd[guid], castTarget[guid] = nil, nil
					resIncoming[targetGUID] = n - 1
				else
					debug(2, "Waiting for INCOMING_RESURRECT_CHANGED.")
				end
			end
		end
	end
end

f.UNIT_SPELLCAST_INTERRUPTED = f.UNIT_SPELLCAST_STOP

------------------------------------------------------------------------

function f:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, combatEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool)
	if combatEvent == "SPELL_RESURRECT" then
		timestamp = GetTime() * 1000
		debug(1, combatEvent, "=>", sourceName, "=>", spellName, "=>", destName)
		if resIncoming[destGUID] then
			print(">> ResPending", sourceName, "=>" destName)
			-- callbacks:Fire("LibResInfo_ResPending", unitFromGUID[destGUID], destGUID, timestamp + 120)
			if resIncoming[destGUID] > 1 then
				resIncoming[destGUID] = resIncoming[destGUID] - 1
			else
				resIncoming[destGUID] = nil
			end
			resPending[destGUID] = timestamp + 120

			total.casting = total.casting - 1
			if total.casting == 0 then
				debug(2, "0 casting, unregister CLEU")
				self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			end

			total.pending = total.pending + 1
			if total.pending > 0 then
				debug(2, total.pending, "pending, register UNIT_HEALTH, start timer")
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
			debug(1, "UNIT_HEALTH", (UnitName(unit)), "/ Dead?", UnitIsDead(unit) and "Y" or "N", "/ Ghost?", UnitIsGhost(unit) and "Y" or "N", "/ Offline?", UnitIsConnected(unit) and "N" or "Y")
			local lost
			if UnitIsGhost(unit) or not UnitIsConnected(unit) then
				print(">> ResExpired", (UnitName(unit)))
				-- callbacks:Fire("LibResInfo_ResExpired", unit, guid)
				lost = true
			elseif not UnitIsDead(unit) then
				print(">> ResUsed", (UnitName(unit)))
				-- callbacks:Fire("LibResInfo_ResUsed", unit, guid)
				lost = true
			end
			if lost then
				resPending[guid] = nil
				total.pending = total.pending - 1
				if total.pending == 0 then
					debug(2, "0 pending, unregister UNIT_HEALTH")
					self:UnregisterEvent("UNIT_HEALTH")
				end
			end
		end
	end
end

------------------------------------------------------------------------

f:Hide()

local timer = 0
local INTERVAL = 0.5
f:SetScript("OnUpdate", function(self, elapsed)
	timer = timer + elapsed
	if timer > INTERVAL then
		local now = GetTime()
		for guid, expiry in pairs(resPending) do
			if expiry - now < INTERVAL then -- will expire before next update
				local unit = unitFromGUID[guid]
				print(">> ResExpired", (UnitName(unit))
				-- callbacks:Fire("LibResInfo_ResExpired", unit, guid)
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