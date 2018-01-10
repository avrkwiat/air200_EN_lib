
--Module Name: Remote Upgrade
--Module function: Connect to upgrade server only at every boot or reboot, if there is a new version of the server, lib and application scripts are upgraded remotely
--Last modified: 2017.02.09


-- Define module, import dependent libraries
local base = _G
local string = require"string"
local io = require"io"
local os = require"os"
local rtos = require"rtos"
local sys  = require"sys"
local link = require"link"
local misc = require"misc"
local common = require"common"
module(...)

-- Load common global functions to local

local print = base.print
local send = link.send
local dispatch = sys.dispatch

-- Remote upgrade mode, in the main.lua, UPDMODE variable configuration, the default configuration is 0
--0: Automatic upgrade mode, the script is updated, restart automatically to complete the upgrade
-- 1: user-defined mode, if the background has a new version, will produce a message, the user application script to decide whether to upgrade
local updmode = base.UPDMODE or 0

--PROTOCOL: transport layer protocol, only supports TCP and UDP
--SERVER, PORT for the server address and port
local PROTOCOL,SERVER,PORT = "UDP","firmware.openluat.com",12410
-- Whether to use a user-defined upgrade server

local usersvr
-- Upgrade package save path

local UPDATEPACK = "/luazip/update.bin"

-- GET command waiting time

local CMD_GET_TIMEOUT = 10000
-- Error packets (packet ID or length mismatch) are retrieved after a period of time

local ERROR_PACK_TIMEOUT = 10000
-- The number of GET command retries per GET

local CMD_GET_RETRY_TIMES = 5
--socket id
local lid,updsuc
-- Set the time period of regular upgrade in seconds, 0 means to turn off the regular upgrade

local period = 0
-- state machine state
--IDLE: Idle state
--CHECK: "Check if there is a new version of the server" status
--UPDATE: status during upgrade
local state = "IDLE"
--projectid is the ID of the project ID, the server itself to maintain
--total is the number of packages, for example, the upgrade file is 10235 bytes, then total = (int) ((10235 + 1022) / 1023) = 11; the upgrade file is 10230 bytes, then total = (int) 10230 + 1022) / 1023) = 10
--last is the number of bytes in the last packet, for example, the upgrade file is 10235 bytes, last = 10235% 1023 = 5; the upgrade file is 10230 bytes, last = 1023
local projectid,total,last
--packid: the current package index
--getretries: Get the number of times each package has been retry
local packid,getretries = 1,0

-- Time zone, the module supports setting the system time function, but the server needs to return the current time

timezone = nil
BEIJING_TIME = 8
GREENWICH_TIME = 0

--Function name: print
--Function: Print interface, all print in this file will be added with the update prefix
--Parameters: None
--Return Value: None

local function print(...)
	base.print("update",...)
end

--Function name: save
--Function: Save the package to the upgrade file
--Parameters:
--data: data packet
--Return Value: None

local function save(data)
	-- If it is the first package, then overwrite; otherwise, save it

	local mode = packid == 1 and "wb" or "a+"
	--open a file

	local f = io.open(UPDATEPACK,mode)

	if f == nil then
		print("save:file nil")
		return
	end
	-- write the file

	f:write(data)
	f:close()
end

--Function name: retry
--Function: Retry action during upgrade
--Parameters:
--param: If STOP, stop retry; otherwise, retry
--Return Value: None

local function retry(param)
	-- The upgrade status has ended and will exit directly

	if state~="CONNECT" and state~="UPDATE" and state~="CHECK" then
		return
	end
	-- stop retrying

	if param == "STOP" then
		getretries = 0
		sys.timer_stop(retry)
		return
	end
	-- The contents of the package are incorrect. ERROR_PACK_TIMEOUT Retry the current package in milliseconds

	if param == "ERROR_PACK" then
		sys.timer_start(retry,ERROR_PACK_TIMEOUT)
		return
	end
	-- Retry times plus 1

	getretries = getretries + 1
	if getretries < CMD_GET_RETRY_TIMES then
		-- The number of retries has not been reached, and continue to try to get the upgrade package

		if state == "CONNECT" then
			link.close(lid)
			lid = nil
			connect()
		elseif state == "UPDATE" then
			reqget(packid)
		else
			reqcheck()
		end
	else
		-- Retries exceeded, upgrade failed

		upend(false)
	end
end

--Function name: reqget
--Function: send "Get the first index of the request packet data" to the server
--Parameters:
--index: The index of the package, starting from 1
--Return Value: None

function reqget(index)
	send(lid,string.format("%sGet%d,%d",
							usersvr and "" or string.format("0,%s,%s,%s,%s,%s,",base.PRODUCT_KEY,misc.getimei(),misc.isnvalid() and misc.getsn() or "",base.PROJECT.."_"..sys.getcorever(),base.VERSION),
							index,
							projectid))
	-- Start the "CMD_GET_TIMEOUT Milliseconds Retry" timer

	sys.timer_start(retry,CMD_GET_TIMEOUT)
end

--Function name: getpack
--Function: Resolve a packet of data received from the server
--Parameters:
--data: package content
--Return Value: None

local function getpack(data)
	-- Determine whether the packet length is correct

	local len = string.len(data)
	if (packid < total and len ~= 1024) or (packid >= total and (len - 2) ~= last) then
		print("getpack:len not match",packid,len,last)
		retry("ERROR_PACK")
		return
	end

	-- Determine packet number is correct

	local id = string.byte(data,1)*256+string.byte(data,2)
	if id ~= packid then
		print("getpack:packid not match",id,packid)
		retry("ERROR_PACK")
		return
	end

	-- stop retrying

	retry("STOP")

	-- Save the upgrade package

	save(string.sub(data,3,-1))
	-- If user-defined mode, an internal message UP_PROGRESS_IND, said the progress of the upgrade

	if updmode == 1 then
		dispatch("UP_EVT","UP_PROGRESS_IND",packid*100/total)
	end

	-- Get the next package data

	if packid == total then
		upend(true)
	else
		packid = packid + 1
		reqget(packid)
	end
end

--Function name: upbegin
--Function: Analyze the new version information issued by the server
--Parameters:
--data: new version information
--Return Value: None

function upbegin(data)
	local p1,p2,p3 = string.match(data,"LUAUPDATE,(%d+),(%d+),(%d+)")
	-- background maintenance project id, the number of packets, the last packet in bytes

	p1,p2,p3 = base.tonumber(p1),base.tonumber(p2),base.tonumber(p3)
	-- the format is correct

	if p1 and p2 and p3 then
		projectid,total,last = p1,p2,p3
		-- Retry count is cleared

		getretries = 0
		-- Set to in progress state

		state = "UPDATE"
		-- Start with the first upgrade package

		packid = 1
		-- Send the request to get the first upgrade package

		reqget(packid)
	-- Incorrect format, upgrade ended

	else
		upend(false)
	end
end

--Function name: upend
--Function: Upgrade finished
--Parameters:
--succ: As a result, true is successful and the rest is failed
--Return Value: None

function upend(succ)
	print("upend",succ)
	updsuc = succ
	local tmpsta = state
	state = "IDLE"
	-- stop retry timer

	sys.timer_stop(retry)
	-- Disconnect

	link.close(lid)
	lid = nil
	getretries = 0
	sys.setrestart(true,1)
	sys.timer_stop(sys.setrestart,true,1)
	-- The upgrade is successful and the automatic upgrade mode restarts

	if succ == true and updmode == 0 then
		sys.restart("update.upend")
	end
	-- If custom upgrade mode, generate an internal message UP_END_IND, said the end of the upgrade and upgrade results

	if updmode == 1 and tmpsta ~= "IDLE" then
		dispatch("UP_EVT","UP_END_IND",succ)
	end
	-- Generate an internal message UPDATE_END_IND, currently used in conjunction with flight mode

	dispatch("UPDATE_END_IND")
	if period~=0 then sys.timer_start(connect,period*1000,"period") end
end

--Function name: reqcheck
--Function: Send "check if there is a new version of the server" request data to the server
--Parameters: None
--Return Value: None

function reqcheck()
	print("reqcheck",usersvr)
	state = "CHECK"
	if usersvr then
		send(lid,string.format("%s,%s,%s",misc.getimei(),base.PROJECT.."_"..sys.getcorever(),base.VERSION))
	else
		send(lid,string.format("0,%s,%s,%s,%s,%s",base.PRODUCT_KEY,misc.getimei(),misc.isnvalid() and misc.getsn() or "",base.PROJECT.."_"..sys.getcorever(),base.VERSION))
	end
	sys.timer_start(retry,CMD_GET_TIMEOUT)
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
		state = "CONNECT"
		-- Generate an internal message UPDATE_BEGIN_IND, currently used in conjunction with flight mode

		dispatch("UPDATE_BEGIN_IND")
		--connection succeeded

		if val == "CONNECT OK" then
			reqcheck()
		--Connection failed

		else
			sys.timer_start(retry,CMD_GET_TIMEOUT)
		end
	-- The connection is disconnected passively

	elseif evt == "STATE" and val == "CLOSED" then		 
		upend(false)
	end
end

-- New version of server information, used in custom mode

local chkrspdat
--Function name: upselcb
--Function: Custom mode, the user choose whether to upgrade the callback processing
--Parameters:
--???????? sel: whether to allow upgrade, true is allowed, the rest is not allowed
--Return Value: None

local upselcb = function(sel)
	-- Allow upgrade

	if sel then
		upbegin(chkrspdat)
	-- Not allowed to upgrade

	else
		link.close(lid)
		lid = nil
		dispatch("UPDATE_END_IND")
	end
end

--Function name: recv
--Function: socket to receive data processing functions
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? data: received data
--Return Value: None

local function recv(id,data)
	--stop retry timer

	sys.timer_stop(retry)
	-- "Check if there is a new version of the server" status

	if state == "CHECK" then
		-- There is a new version on the server

		if string.find(data,"LUAUPDATE") == 1 then
			-- Automatic upgrade mode

			if updmode == 0 then
				upbegin(data)
			-- Custom upgrade mode

			elseif updmode == 1 then
				chkrspdat = data
				dispatch("UP_EVT","NEW_VER_IND",upselcb)
			else
				upend(false)
			end
		-- There is no new version

		else
			upend(false)
		end
		-- If settimezone interface is invoked in user application script

		if timezone then
			local clk,a,b = {}
			a,b,clk.year,clk.month,clk.day,clk.hour,clk.min,clk.sec = string.find(data,"(%d+)%-(%d+)%-(%d+) *(%d%d):(%d%d):(%d%d)")
			-- if the server returned the correct time format

			if a and b then
				-- Set the system time

				clk = common.transftimezone(clk.year,clk.month,clk.day,clk.hour,clk.min,clk.sec,BEIJING_TIME,timezone)
				misc.setclock(clk)
			end
		end
	-- "in progress" status

	elseif state == "UPDATE" then
		if data == "ERR" then
			upend(false)
		else
			getpack(data)
		end
	else
		upend(false)
	end	
end

--Function name: settimezone
--Function: Set the system time of the time zone
--Parameters:
--??????? zone: The time zone, currently only supports Greenwich Mean Time and Beijing Time, BEIJING_TIME and GREENWICH_TIME
--Return Value: None

function settimezone(zone)
	timezone = zone
end

function connect()
	print("connect",lid,updsuc)
	if not lid and not updsuc then
		lid = link.open(nofity,recv,"update")
		link.connect(lid,PROTOCOL,SERVER,PORT)
	end
end

local function defaultbgn()
	print("defaultbgn",usersvr)
	if not usersvr then
		base.assert(base.PRODUCT_KEY and base.PROJECT and base.VERSION,"undefine PRODUCT_KEY or PROJECT or VERSION in main.lua")
		base.assert(not string.match(base.PROJECT,","),"PROJECT in main.lua format error")
		base.assert(string.match(base.VERSION,"%d%.%d%.%d") and string.len(base.VERSION)==5,"VERSION in main.lua format error")
		connect()
	end
end

--Function name: setup
--Function: Configure the server's transport protocol, address and port
--Parameters:
--???????? prot: transport layer protocol, only supports TCP and UDP
--server: server address
--port: server port
--Return Value: None

function setup(prot,server,port)
	if prot and server and port then
		PROTOCOL,SERVER,PORT = prot,server,port
		usersvr = true
		base.assert(base.PROJECT and base.VERSION,"undefine PROJECT or VERSION in main.lua")		
		connect()
	end
end

--Function name: setperiod
--Function: Configure the periodic upgrade
--Parameters:
--???????? prd: number type, the period of regular upgrade in seconds; 0 means to turn off the regular upgrade function, and the remaining value should be greater than or equal to 60 seconds
--Return Value: None

function setperiod(prd)
	base.assert(prd==0 or prd>=60,"setperiod prd error")
	print("setperiod",prd)
	period = prd
	if prd==0 then
		sys.timer_stop(connect,"period")
	else
		sys.timer_start(connect,prd*1000,"period")
	end
end

--Function name: request
--Function: start real-time upgrade
--Parameters: None
--Return Value: None

function request()
	print("request")
	connect()
end

sys.timer_start(defaultbgn,10000)
sys.setrestart(false,1)
sys.timer_start(sys.setrestart,300000,true,1)
