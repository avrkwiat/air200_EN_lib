module(...,package.seeall)


--Functional Requirements:
--Uart in accordance with the frame structure to receive input peripherals, received the correct command, reply ASCII string

--Frame structure is as follows:
--Header: 1 byte, 0x01 means scan instruction, 0x02 means control GPIO command, 0x03 means control port command
--Frame body: bytes are not fixed, with the frame header
--End of the frame: 1 byte, fixed to 0xC0

--When the received instruction frame header is 0x01, reply "CMD_SCANNER \ r \ n" to the peripheral device
--When the received instruction frame header is 0x02, reply "CMD_GPIO \ r \ n" to the peripheral device
--When the received instruction frame header is 0x03, reply "CMD_PORT \ r \ n" to the peripheral device
--When the received instruction frame header is the remaining data, reply "CMD_ERROR \ r \ n" to the peripheral device



-- Serial ID, 1 corresponds to uart1
-- If you want to change uart2, set UART_ID to 2
local UART_ID = 1
-- Header type and the end of the frame
local CMD_SCANNER,CMD_GPIO,CMD_PORT,FRM_TAIL = 1,2,3,string.char(0xC0)
-- Serial read data buffer
local rdbuf = ""


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--Function name: parse
--Function: According to the frame structure analysis of a complete frame of data
--Parameters:
--data: all unprocessed data
--Return Value: The first return value is the result of a complete frame message processing, the second return value is unprocessed data

local function parse(data)
	if not data then return end	
	
	local tail = string.find(data,string.char(0xC0))
	if not tail then return false,data end	
	local cmdtyp = string.byte(data,1)
	local body,result = string.sub(data,2,tail-1)
	
	print("parse",common.binstohexs(data),cmdtyp,common.binstohexs(body))
	
	if cmdtyp == CMD_SCANNER then
		write("CMD_SCANNER")
	elseif cmdtyp == CMD_GPIO then
		write("CMD_GPIO")
	elseif cmdtyp == CMD_PORT then
		write("CMD_PORT")
	else
		write("CMD_ERROR")
	end
	
	return true,string.sub(data,tail+1,-1)	
end


--Function name: proc
--Function: Processing data read from the serial port
--Parameters:
--data: Data read from the serial port once
--Return Value: None

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


--Function name: read
--Function: read the data received by the serial port
--Parameters: None
--Return Value: None

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


--Function name: write
--Function: send data through the serial port
--Parameters:
--s: the data to send
--Return Value: None

function write(s)
	print("write",s)
	uart.write(UART_ID,s.."\r\n")
end


-- Keep the system awake, here for testing purposes only, so this module has no place to call pm.sleep ("test") Hibernate and will not go into low-power hibernation
-- When developing a project that requires low power consumption, make sure to call pm.sleep ("test") when pm.wake ("test")
pm.wake("test")
-- Register serial data receiving function, the serial port receives the data, it will interrupt the way, call read interface read data
sys.reguart(UART_ID,read)
-- Configure and open the serial port
uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1)


--If you need to open the function of "Notify by asynchronous message after the serial port sends data," the configuration is as follows

--local function txdone()
--	print("txdone")
--end
--uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1,nil,1)
--sys.reguartx(UART_ID,txdone)


