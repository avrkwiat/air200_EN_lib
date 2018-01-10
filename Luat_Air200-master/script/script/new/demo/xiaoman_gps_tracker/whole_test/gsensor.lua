
--Module Name: gsensor Function
--Module function: Currently only used to detect the occurrence of vibration
--Last modified: 2017.02.16

module(...,package.seeall)

--i2c id
--gsensor Lock shock interrupt register address
local i2cid,intregaddr = 1,0x1A

--Function name: print
--Function: Print Interface, all prints in this file will be prefixed with gsensor
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("gsensor",...)
end

--Function name: clrint
--Function: Clear gsensor chip lock vibration interrupt flag, so gsensor can begin to detect the next vibration
--Parameters: None
--Return Value: None

local function clrint() 
	if pins.get(pincfg.GSENSOR) then
		i2c.read(i2cid,intregaddr,1)
	end
end

--Function name: init2
--Function: gsensor The second step initialization
--Parameters: None
--Return Value: None

local function init2()
	local cmd,i = {0x1B,0x00,0x6A,0x01,0x1E,0x20,0x21,0x04,0x1B,0x00,0x1B,0xDA,0x1B,0xDA}
	for i=1,#cmd,2 do
		i2c.write(i2cid,cmd[i],cmd[i+1])
		print("init2",string.format("%02X",cmd[i]),string.format("%02X",string.byte(i2c.read(i2cid,cmd[i],1))))
	end
	clrint()
end

--Function name: checkready
--Function: Check "gsensor first step initialization" is successful
--Parameters: None
--Return Value: None

local function checkready()
	local s = i2c.read(i2cid,0x1D,1)
	print("checkready",s,(s and s~="") and string.byte(s) or "nil")
	if s and s~="" then
		if bit.band(string.byte(s),0x80)==0 then
			init2()
			return
		end
	end
	sys.timer_start(checkready,1000)
end

--Function name: init
--Function: gsensor first step initialization
--Parameters: None
--Return Value: None

local function init()
	--gsensor i2c address
	local i2cslaveaddr = 0x0E
	-- Turn on the i2c function
	if i2c.setup(i2cid,i2c.SLOW,i2cslaveaddr) ~= i2c.SLOW then
		print("init fail")
		return
	end
	i2c.write(i2cid,0x1D,0x80)
	sys.timer_start(checkready,1000)
end

--Function name: qryshk
--Function: Check gsensor vibration occurs
--Parameters: None
--Return Value: None

local function qryshk()
	-- There was a vibration
	if pins.get(pincfg.GSENSOR) then
		-- Clear the lock vibration flag to be able to detect the next vibration
		clrint()
		print("GSENSOR_SHK_IND")
		-- Generates an internal message GSENSOR_SHK_IND, indicating that the device has vibrated
		sys.dispatch("GSENSOR_SHK_IND")
	end
end

-- Start a 10 second cycle timer to poll for vibration
-- The reason why the interrupt is not taken is because the interrupt is too power-hungry due to frequent vibrations
sys.timer_loop_start(qryshk,10000)
init()

-- Sometimes an exception occurs, there is no vibration check out, but gsensor internal registers have been set lock vibration flag
-- 30 seconds Clear a lock vibration flag, used to avoid this anomaly
sys.timer_loop_start(clrint,30000)
