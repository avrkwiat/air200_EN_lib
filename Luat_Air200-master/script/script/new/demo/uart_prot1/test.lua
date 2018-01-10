module(...,package.seeall)

local schar,slen,sfind,sbyte,ssub = string.char,string.len,string.find,string.byte,string.sub

--Functional Requirements:
--Uart receives the input of parsing peripherals according to the frame structure

--Frame structure is as follows:
--Start flag: 1 byte, fixed to 0x01
--Number of data: 1 byte, the number of data bytes between the check code and the number of data
--Instruction: 1 byte
--Data 1: 1 byte
--Data 2: 1 byte
--Data 3: 1 byte
--Data 4: 1 byte
--Check code: the number of data to the data 4 exclusive OR operation
--End flag: 1 byte, fixed to 0xFE



-- Serial ID, 1 corresponds to uart1
-- If you want to change uart2, set UART_ID to 2
local UART_ID = 1
-- start and end signs
local FRM_HEAD,FRM_TAIL = 0x01,0xFE
--instruction
local CMD_01 = 0x01
-- Serial read data buffer
local rdbuf = ""

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

-- Command 1 data analysis
local function cmd01(s)
	print("cmd01",common.binstohexs(s),slen(s))
	if slen(s)~=4 then return end
	local i,j,databyte
	for i=1,4 do
		databyte = sbyte(s,i)
		for j=0,7 do
			print("cmd01 data"..i.."_bit"..j..": "..(bit.isset(databyte,j) and 1 or 0))
		end
	end
end

-- Calculate the checksum of the string s
local function checksum(s)
	local ret,i = 0
	for i=1,slen(s) do
		ret = bit.bxor(ret,sbyte(s,i))
	end
	return ret
end

--Function name: parse
--Function: According to the frame structure analysis of a complete frame of data
--Parameters:
--data: all unprocessed data
--Return Value: The first return value is the result of a complete frame message processing, the second return value is unprocessed data

local function parse(data)
	if not data then return end
	
	-- start sign
	local headidx = string.find(data,schar(FRM_HEAD))
	if not headidx then print("parse no head error") return true,"" end
	
	-- the number of data
	if slen(data)<=headidx then print("parse wait cnt byte") return false,data end
	local cnt = sbyte(data,headidx+1)
	
	if slen(data)<headidx+cnt+3 then print("parse wait complete") return false,data end
	
	--instruction
	local cmd = sbyte(data,headidx+2)	
	local procer =
	{
		[CMD_01] = cmd01,
	}
	if not procer[cmd] then print("parse cmd error",cmd) return false,ssub(data,headidx+cnt+4,-1) end
	
	-- end sign
	if sbyte(data,headidx+cnt+3)~=FRM_TAIL then print("parse tail error",sbyte(data,headidx+cnt+3)) return false,ssub(data,headidx+cnt+4,-1) end
	
	-- check code
	local sum1,sum2 = checksum(ssub(data,headidx+1,headidx+1+cnt)),sbyte(data,headidx+cnt+2)
	if sum1~=sum2 then print("parse checksum error",sum1,sum2) return false,ssub(data,headidx+cnt+4,-1) end
	
	procer[cmd](ssub(data,headidx+3,headidx+1+cnt))
	
	return true,ssub(data,headidx+cnt+4,-1)	
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
	-- So Lua script interrupt received serial port data, read the data in the receive buffer all the time, so as to ensure that the underlying data in the core interrupt up, while the read statement in the while function Guaranteed this
	while true do		
		data = uart.read(UART_ID,"*l",0)
		if not data or string.len(data) == 0 then break end
		-- Opening the print below will take time
		print("read",common.binstohexs(data))
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
	uart.write(UART_ID,s)
end

-- Keep the system awake, here for testing purposes only, so this module has no place to call pm.sleep ("test") Hibernate and will not go into low-power hibernation
-- When developing a project that requires low power consumption, make sure to call pm.sleep ("test") when pm.wake ("test")
pm.wake("test")
-- Register serial data receiving function, the serial port receives the data, it will interrupt the way, call read interface read data
sys.reguart(UART_ID,read)
-- Configure and open the serial port
uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1)


