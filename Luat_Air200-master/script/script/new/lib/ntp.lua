--Module Name: Network Time Update
--Module function: Only connect with NTP server every time when power on or reboot, update system time
--Please study the NTP protocol on your own
--Then read this module
--Last modified: 2017.03.22

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local os = require"os"
local sys  = require"sys"
local link = require"link"
local misc = require"misc"
local common = require"common"
local pack = require"pack"
module(...)

-- Load common global functions to local

local print = base.print
local send = link.send
local dispatch = sys.dispatch
local sbyte,ssub = string.byte,string.sub


-- Available NTP server domain name collection, in accordance with the order to connect to the server synchronization time, the synchronization is successful, exit, no longer continue traversal

local tserver =
{	
	"ntp1.aliyun.com",
	"ntp2.aliyun.com",
	"ntp3.aliyun.com",
	"ntp4.aliyun.com",
	"ntp5.aliyun.com",
	"ntp7.aliyun.com",
	"ntp6.aliyun.com",	
	"s2c.time.edu.cn",
	"194.109.22.18",
	"210.72.145.44",
	--"ntp.sjtu.edu.cn",
	--"s1a.time.edu.cn",
	--"s1b.time.edu.cn",
	--"s1c.time.edu.cn",
	--"s1d.time.edu.cn",
	--"s2a.time.edu.cn",	
	--"s2d.time.edu.cn",
	--"s2e.time.edu.cn",
	--"s2g.time.edu.cn",
	--"s2h.time.edu.cn",
	--"s2m.time.edu.cn",
}
-- The index of the currently connected server in tserver

local tserveridx = 1

--REQUEST command waiting time

local REQUEST_TIMEOUT = 8000
-- The number of retries per REQUEST command

local REQUEST_RETRY_TIMES = 3
--socket id
local lid
-- The number of times the time synchronization with the current NTP server has been retried

local retries = 0


--Function name: retry
--Function: Retry action in time synchronization
--Parameters: None
--Return Value: None

local function retry()
	sys.timer_stop(retry)
	-- Retry times plus 1

	retries = retries + 1
	-- Number of retries has been reached, continue sending synchronization request

	if retries < REQUEST_RETRY_TIMES then
		request()
	else
		-- Retry count exceeded, synchronization with current server failed

		upend(false)
	end
end


--Function name: upend
--Function: Time synchronization result processing with current NTP server
--Parameters:
--suc: time synchronization result, true is successful, the rest is failed
--Return Value: None

function upend(suc)
	print("ntp.upend",suc)
	-- stop retry timer

	sys.timer_stop(retry)
	retries = 0
	-- Disconnect

	link.close(lid)
	-- The synchronization time is successful or the NTP server has completely traversed

	if suc or tserveridx>=#tserver then
		-- Generate an internal message UPDATE_END_IND, currently used in conjunction with flight mode

		dispatch("NTP_END_IND",suc)
	else
		tserveridx = tserveridx+1
		connect()
	end	
end

--Function name: request
--Function: Send "sync time" request data to the server
--Parameters: None
--Return Value: None

function request()
	send(lid,common.hexstobins("E30006EC0000000000000000314E31340000000000000000000000000000000000000000000000000000000000000000"))
	sys.timer_start(retry,REQUEST_TIMEOUT)
end

--Function name: nofity
--Function: Socket state processing function
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? evt: message event type
--val: message event parameter
--Return Value: None

local function nofity(id,evt,val)
	-- connection result

	if evt == "CONNECT" then
		-- Generate an internal message NTP_BEGIN_IND, currently used in conjunction with flight mode

		dispatch("NTP_BEGIN_IND")
		--connection succeeded

		if val == "CONNECT OK" then
			request()
		--Connection failed

		else
			upend(false)
		end
	-- The connection is disconnected passively

	elseif evt == "STATE" and val == "CLOSED" then		 
		upend(false)
	end
end

--Function name: setclkcb
--Function: Call the misc.setclock interface to set the time after the callback function
--Parameters:
--???????? cmd: program can be ignored not dealt with
--???????? suc: set success or failure, true success, the other failed
--Return Value: None

local function setclkcb(cmd,suc)
	upend(suc)
end

--Function name: recv
--Function: socket to receive data processing functions
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? data: received data
--Return Value: None

local function recv(id,data)
	-- stop retry timer

	sys.timer_stop(retry)
	-- Data format error

	if string.len(data)~=48 then
		upend(false)
		return
	end
	print("ntp recv:",common.binstohexs(ssub(data,41,44)))
	misc.setclock(os.date("*t",(sbyte(ssub(data,41,41))-0x83)*2^24+(sbyte(ssub(data,42,42))-0xAA)*2^16+(sbyte(ssub(data,43,43))-0x7E)*2^8+(sbyte(ssub(data,44,44))-0x80)+1),setclkcb)
end

--Function name: connect
--Function: Create socket, and connect tserveridx NTP server
--Parameters: None
--Return Value: None

function connect()
	lid = link.open(nofity,recv,"ntp")
	link.connect(lid,"UDP",tserver[tserveridx],123)
end

connect()
