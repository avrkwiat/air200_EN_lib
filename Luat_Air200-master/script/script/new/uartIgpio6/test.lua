module(...,package.seeall)




-- Serial ID, 1 corresponds to uart1
-- If you want to change uart2, set UART_ID to 2
local UART_ID = 1
-- Header type and the end of the frame
local CMD_SCANNER,CMD_GPIO,CMD_PORT,FRM_TAIL = 1,2,3,string.char(0xC0)
-- Serial read data buffer
local rdbuf = ""



local function print(...)
	_G.print("test",...)
end



local function parse(data)
	if not data then return end	
	
	local tail = string.find(data,string.char(0xC0))
	if not tail then return false,data end	
	local cmdtyp = string.byte(data,1)
	local body,result = string.sub(data,2,tail-1)
	
	print("parse",common.binstohexs(data),cmdtyp,common.binstohexs(body))
	
	if cmdtyp == CMD_SCANNER then		
		pio.pin.sethigh(pio.P0_6)
		write("set HIGH pin6")
	elseif cmdtyp == CMD_GPIO then
		pio.pin.setlow(pio.P0_6)  
		write("set LOW pin6")
	elseif cmdtyp == CMD_PORT then
		write("CMD_PORT")
	else
		write("CMD_ERROR")
	end
	
	return true,string.sub(data,tail+1,-1)	
end


--[[
Function name: proc
Function: Processing data read from the serial port
Parameters:
data: Data read from the serial port once
Return Value: None
]]
local function proc(data)
	if not data or string.len(data) == 0 then return end
	-- Append to the buffer
	rdbuf = rdbuf..data	
	
	local result,unproc
	unproc = rdbuf
	-- Parse unprocessed data cyclically according to frame structure
	while true do
		result,unproc = parse(unproc)
		if not unproc or unproc == "" or not result then
			break
		end
	end

	rdbuf = unproc or ""
end


local function read()
	local data = ""	
	-- The underlying core, the serial port receives the data:
	-- If the receive buffer is empty, an interrupt is notified that the Lua script received the new data;
	-- The Lua script is not notified if the receive buffer is not empty
	-- So Lua script interrupt received serial port data, read the data in the receive buffer every time to read, so as to ensure that the underlying data in the core interrupt up, while the read statement in the while function Guaranteed this
	while true do		
		data = uart.read(UART_ID,"*l",0)
		if not data or string.len(data) == 0 then break end		
		-- Opening the print below will take time
		--print("read",data,common.binstohexs(data))
		proc(data)
	end
end


function write(s)
	print("write",s)
	uart.write(UART_ID,s.."\r\n")
end


-- Keep the system awake, here for testing purposes only, so this module has no place to call pm.sleep ("test") Hibernate and will not go into low-power hibernation
-- When developing a project that requires low power consumption, make sure to call pm.sleep ("test") when pm.wake ("test")
pm.wake("test")
pio.pin.setdir(pio.OUTPUT, pio.P0_6)
pio.pin.setval(0, pio.P0_6)
-- Register serial data receiving function, the serial port receives the data, it will interrupt the way, call read interface read data
sys.reguart(UART_ID,read)
-- Configure and open the serial port
uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1)

--[[
If you need to open the function of "Notify by asynchronous message after the serial port sends data," the configuration is as follows

local function txdone()
	print("txdone")
end
uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1,nil,1)
sys.reguartx(UART_ID,txdone)
]]

