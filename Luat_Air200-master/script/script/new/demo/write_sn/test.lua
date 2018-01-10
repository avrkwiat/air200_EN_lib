module(...,package.seeall)

require"misc"

-- The new SN number to be written to the device
local newsn = "1234567890123456"

-- Begin writing SN after 5 seconds
sys.timer_start(misc.setsn,5000,newsn)
