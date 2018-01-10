
--Module Name: Hibernation Management (Not Flight Mode)
--Module features: lua script application sleep control
--Usage please refer to: script / demo / pm
--Last modified: 2017.02.13

--Description of this part of hibernation:
--There are two ways to deal with the current dormancy,
--One is the underlying core, automatic processing, such as tcp send or receive data, it will automatically wake up, send and receive ends, it will automatically sleep; This part of the control without lua script
--Another is the lua script using pm.sleep and pm.wake self-control, for example, uart connect peripherals, uart before receiving data, take the initiative to pm.wake, so as to ensure that the data received in front of no mistakes, when no communication is required When calling pm.sleep; if lcd project, the same token
--Power consumption of at least 30mA when not sleeping
--If you do not want to control the dormancy, be sure to pm.wake ("A"), there is a place to call pm.sleep ("A")

-- Define module, import dependent libraries
local base = _G
local pmd = require"pmd"
local pairs = base.pairs
local assert = base.assert
module("pm")

-- wake up tag table

local tags = {}
-- Lua application is dormant, true sleep, the rest did not sleep

local flag = true

--Function name: isleep
--Function: read lua application hibernation
--Parameters: None
--Return value: true sleep, the rest did not sleep

function isleep()
	return flag
end

--Function name: wake
--Function: lua application wake up system
--Parameters:
--tag: wake up tag, user-defined
--Return Value: None

function wake(tag)
	assert(tag and tag~=nil,"pm.wake tag invalid")
	-- This wake-up tag is set in the wake-up list

	tags[tag] = 1
	-- If lua application is in hibernation

	if flag == true then
		-- Set to awake state

		flag = false
		-- Call the underlying software interface, the real wake-up system

		pmd.sleep(0)
	end
end

--Function name: sleep
--Function: lua application hibernation system
--Parameters:
--tag: Hibernate tag, user defined, consistent with the tag in wake
--Return Value: None

function sleep(tag)
	assert(tag and tag~=nil,"pm.sleep tag invalid")
	-- This sleep flag is set to 0 in the wakeup list

	tags[tag] = 0

	if tags[tag] < 0 then
		base.print("pm.sleep:error",tag)
		tags[tag] = 0
	end

	-- As long as there is any one flag wakes up, it does not sleep

	for k,v in pairs(tags) do
		if v > 0 then
			return
		end
	end

	flag = true
	---- Call the underlying software interface, the real sleep system

	pmd.sleep(1)
end
