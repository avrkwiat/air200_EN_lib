module(...,package.seeall)

require"pm"

-- Serial ID, 1 corresponds to uart1
local UART_ID = 1

--SND_UNIT_MAX: each send the maximum number of bytes, as long as the cumulative received data is greater than or equal to the maximum number of bytes, and is not sending data to the background, then immediately send the first SND_UNIT_MAX byte data to the background
--SND_DELAY: every time the serial port receives the data, re-delay SND_DELAY milliseconds, did not receive new data, and is not sending data to the background, immediately send up to the first SND_UNIT_MAX bytes of data to the background
-- These two variables are used in conjunction, as long as any one of the conditions are met, will trigger the sending action
-- For example: SND_UNIT_MAX, SND_DELAY = 1024,1000, the following situations
-- Serial port received 500 bytes of data, the next 1000 ms did not receive the data, and is not sending data to the background, then immediately send this 500 bytes of data to the background
-- Serial received 500 bytes of data, 800 milliseconds, they have received 524 bytes of data, this time is not sending data to the background, then immediately send this 1024 bytes of data to the background
local SND_UNIT_MAX,SND_DELAY = 1024,1000

--sndingtosvr: Whether to send data to the background
local sndingtosvr

--unsndbuf: Data not yet sent
--sndingbuf: the data being sent
local readbuf--[[,sndingbuf]] = ""--[[,""]]

--Function name: print
--Function: Print interface, all print in this file will be added mcuart prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("mcuart",...)
end

--Function name: sndtosvr
--Function: Notify the data sending function module, the serial port data is ready, you can send
--Parameters: None
--Return Value: None

local function sndtosvr()
	--print("sndtosvr",sndingtosvr)
	if not sndingtosvr then
		sys.dispatch("SND_TO_SVR_REQ")
	end
end

--Function name: getsndingbuf
--Function: Get the data to be sent
--Parameters: None
--Return value: string type, the data to be sent

local function getsndingbuf()
	print("getsndingbuf",string.len(readbuf),sndingtosvr,sys.timer_is_active(sndtosvr))
	if string.len(readbuf)>0 and not sndingtosvr and (not sys.timer_is_active(sndtosvr) or string.len(readbuf)>=SND_UNIT_MAX) then
		local endidx = string.len(readbuf)>=SND_UNIT_MAX and SND_UNIT_MAX or string.len(readbuf)
		local retstr = string.sub(readbuf,1,endidx)
		readbuf = string.sub(readbuf,endidx+1,-1)
		sndingtosvr = true
		return retstr
	else
		sndingtosvr = false
		return ""
	end	
end

--Function name: resumesndtosvr
--Function: Reset the sending flag to get the data to be sent
--Parameters: None
--Return value: string type, the data to be sent

function resumesndtosvr()
	sndingtosvr = false
	return getsndingbuf()
end


--Function name: sndcnf
--Function: Send result processing function
--Parameters:
--result: send the result, true success, the rest of the value failed
--Return Value: None

--[[local function sndcnf(result)
	print("sndcnf",result)
	--sndingbuf = ""
	sndingtosvr = false
end]]


--Function name: proc
--Function: handle the data received by the serial port
--Parameters:
--data: The serial port data currently read
--Return Value: None

local function proc(data)
	if not data or string.len(data) == 0 then return end
	-- Append to the end of the unsent data buffer
	readbuf = readbuf..data
	if string.len(readbuf)>=SND_UNIT_MAX then sndtosvr() end
	sys.timer_start(sndtosvr,SND_DELAY)
end



--Function name: snd
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
		--print("read",string.len(data)--[[data,common.binstohexs(data)]])
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

-- a list of message processing functions
local procer =
{
	SVR_TRANSPARENT_TO_MCU = write,
	--SND_TO_SVR_CNF = sndcnf,
}

-- Register a list of message handlers
sys.regapp(procer)
-- Keep the system awake without hibernation
pm.wake("mcuart")
-- Register serial data receiving function, the serial port receives the data, it will interrupt the way, call read interface read data
sys.reguart(UART_ID,read)
-- Configure and open the serial port
uart.setup(UART_ID,9600,8,uart.PAR_NONE,uart.STOP_1)


