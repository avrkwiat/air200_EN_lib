module(...,package.seeall)


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--i2cuse: Whether the pin is currently used as an i2c function, true means yes, the rest is not
local i2cid,i2cuse = 1,true

--Function name: i2copn
--Function: Open i2c
--Parameters: None
--Return Value: None

local function i2copn()
	
	-- The third address parameter, 0x15, is just an example, which is determined by peripherals when actually used
	if i2c.setup(i2cid,i2c.SLOW,0x15) ~= i2c.SLOW then
		print("i2copn fail")
	end
end


--Function name: i2close
--Function: Close i2c
--Parameters: None
--Return Value: None

local function i2close()
	i2c.close(i2cid)
end


--Function name: switchtoi2c
--Function: Switch to i2c function
--Parameters: None
--Return Value: None

local function switchtoi2c()
	print("switchtoi2c",i2cuse)
	if not i2cuse then
		
		-- Turn off the gpio function
		pio.pin.close(pio.P0_24)
		pio.pin.close(pio.P0_25)
		
		-- Turn on the i2c function
		i2copn()
		i2cuse = true
	end
end


--Function name: switchtogpio
--Function: switch to gpio function to use
--Parameters: None
--Return Value: None

local function switchtogpio()
	print("switchtogpio",i2cuse)
	if i2cuse then
		
		-- Turn off the i2c function
		i2close()
		-- Configure gpio direction
		pio.pin.setdir(pio.OUTPUT,pio.P0_24)
		pio.pin.setdir(pio.OUTPUT,pio.P0_25)
		-- Output gpio level
		pio.pin.setval(1,pio.P0_24)
		pio.pin.setval(0,pio.P0_25)
		i2cuse = false
	end	
end


--Function name: switch
--Function: Switch i2c and gpio functions
--Parameters: None
--Return Value: None

local function switch()
	if i2cuse then
		switchtogpio()
	else
		switchtoi2c()
	end
end

i2copn()

-- Cycle timer, 5 seconds to switch functions
sys.timer_loop_start(switch,5000)
