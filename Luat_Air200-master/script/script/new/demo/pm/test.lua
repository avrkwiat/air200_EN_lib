module(...,package.seeall)


--Description of this part of hibernation:
--There are two ways to deal with the current dormancy,
--One is the underlying core, automatic processing, such as tcp send or receive data, it will automatically wake up, send and receive ends, it will automatically sleep; This part of the control without lua script
--Another is the lua script using pm.sleep and pm.wake self-control, for example, uart connect peripherals, uart before receiving data, take the initiative to pm.wake, so as to ensure that the data received in front of no mistakes, when no communication is required When calling pm.sleep; if lcd project, the same token
--Power consumption of at least 30mA when not sleeping
--After hibernation, flight mode less than 1mA, non-flight mode power consumption has no data (follow-up)
--If you do not want to control the dormancy, be sure to pm.wake ("A"), there is a place to call pm.sleep ("A")


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

pm.wake("A") -- After executing this sentence, A wakes up the module
pm.wake("A") -- After executing this sentence, A repeated wake-up module, in fact, nothing changed
pm.sleep("A") -- After executing this sentence, A dormant module, lua part has no function wake module, the module is dormant by the core decision

pm.wake("B") -- After executing this sentence, B wakes up the module
pm.wake("C") -- After executing this sentence, C wakes up the module
pm.sleep("B") -- After executing this statement, B hibernates the module, but there is also a part in Lua that wakes up the module, and the module does not hibernate
pm.sleep("C") -- After executing this sentence, C dormant module, lua part has no function wake module, the module is dormant by the core decision


