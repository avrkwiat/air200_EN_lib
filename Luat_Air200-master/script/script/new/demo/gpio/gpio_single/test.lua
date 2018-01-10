require"pincfg"
module(...,package.seeall)


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

-------------------------PIN22 test begins-------------------------
local pin22flg = true

--Function name: pin22set
--Function: Set the output level of PIN22 pin to invert once in 1 second
--Parameters: None
--Return Value: None

local function pin22set()
	pins.set(pin22flg,pincfg.PIN22)
	pin22flg = not pin22flg
end
-- Start the 1-second cycle timer to set the output level of the PIN22 pin

sys.timer_loop_start(pin22set,1000)
-------------------------PIN22 test is over-------------------------


-------------------------PIN23 test begins-------------------------
local pin23flg = true

--Function name: pin23set
--Function: Set the PIN23 pin output level, 1 second reverse
--Parameters: None
--Return Value: None

local function pin23set()
	pins.set(pin23flg,pincfg.PIN23)
	pin23flg = not pin23flg
end
-- Start the one-second cycle timer to set the output level of the PIN23 pin
sys.timer_loop_start(pin23set,1000)
-------------------------PIN23 test is over-------------------------


-------------------------PIN20 test begins-------------------------


--Function name: pin20get
--Function: Read the input level of PIN20 pin
--Parameters: None
--Return Value: None

local function pin20get()
	local v = pins.get(pincfg.PIN20)
	print("pin20get",v and "low" or "high")
end

--Start the 1 second cycle timer and read the input level of the PIN20 pin
sys.timer_loop_start(pin20get,1000)
-------------------------PIN20 test is over-------------------------
