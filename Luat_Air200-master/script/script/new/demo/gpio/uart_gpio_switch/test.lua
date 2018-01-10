module(...,package.seeall)


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--uartuse: Whether the pin is currently used as uart function, true said yes, the rest of the said is not
local uartid,uartuse = 1,true

--Function name: uartopn
--Function: Open uart
--Parameters: None
--Return Value: None

local function uartopn()
	uart.setup(uartid,115200,8,uart.PAR_NONE,uart.STOP_1)	
end


--Function name: uartclose
--Function: Close uart
--Parameters: None
--Return Value: None

local function uartclose()
	uart.close(uartid)
end


--Function name: switchtouart
--Function: switch to uart function
--Parameters: None
--Return Value: None

local function switchtouart()
	print("switchtouart",uartuse)
	if not uartuse then
		-- Turn off the gpio function
		pio.pin.close(pio.P0_6)
		pio.pin.close(pio.P0_14)
		
		-- Open uart function
		uartopn()
		uartuse = true
	end
end


--Function name: switchtogpio
--Function: switch to gpio function to use
--Parameters: None
--Return Value: None

local function switchtogpio()
	print("switchtogpio",uartuse)
	if uartuse then
		
		-- Turn off uart function
		uartclose()
		
		-- Configure gpio direction
		pio.pin.setdir(pio.OUTPUT,pio.P0_6)
		pio.pin.setdir(pio.OUTPUT,pio.P0_14)
		-- Output gpio level
		pio.pin.setval(1,pio.P0_6)
		pio.pin.setval(0,pio.P0_14)
		uartuse = false
	end	
end


--Function name: switch
--Function: Switch uart and gpio functions
--Parameters: None
--Return Value: None

local function switch()
	if uartuse then
		switchtogpio()
	else
		switchtouart()
	end
end

uartopn()

-- Cycle timer, 5 seconds to switch functions
sys.timer_loop_start(switch,5000)
