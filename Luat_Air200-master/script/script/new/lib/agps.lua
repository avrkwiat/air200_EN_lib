
--Module Name: AGPS, Assisted Global Positioning System, GPS Assisted Positioning Management (GPS module for u-blox only)
--Module function: connect AGPS background, download GPS ephemeris data, write GPS module, accelerate GPS positioning
--Module last modified: 2017.02.20


--After connecting to the background, the application layer protocol:
--1, send AGPS to the background
--2, Backstage AGPSUPDATE, total, last, sum1, sum2, sum3, ......, sumn
--??? total: the total number of packages
--??? last: the number of bytes in the last packet
--??? sum1: checksum of the first packet data
--??? sum2: checksum of the second packet data
--??? sum3: the third packet data checksum
--??? ...
--??? sumn: checksum of the nth packet data
--3, send Getidx
--??? idx is the index of the package, the range is 1 --- total
--??? For example: Assuming the upgrade file is 4000 bytes,
--??? Get1
--??? Get2
--??? Get3
--??? Get4
--4, backstage the contents of each package
--??? The first byte and the second byte, for the package index, big end
--??? The rest of the data is ephemeris data


-- Define module, import dependent libraries
local base = _G
local table = require"table"
local rtos = require"rtos"
local sys = require"sys"
local string = require"string"
local link = require"link"
local gps = require"gps"
module(...)

-- Load common global functions to local
local print = base.print
local tonumber = base.tonumber
local sfind = string.find
local slen = string.len
local ssub = string.sub
local sbyte = string.byte
local sformat = string.format
local send = link.send
local dispatch = sys.dispatch

--lid£ºsocket id
--isfix: GPS positioning is successful
local lid,isfix
--ispt: Whether to enable the AGPS function
--itv: connect AGPS background interval, in seconds, the default 2 hours, is 2 hours to connect an AGPS background, update the ephemeris data
--PROT, SVR, PORT: AGPS background transport layer protocol, address, port
--WRITE_INTERVAL: Interval for writing GPS module to each ephemeris data packet, in milliseconds
local ispt,itv,PROT,SVR,PORT,WRITE_INTERVAL = true,(2*3600),"UDP","zx1.clouddatasrv.com",8072,50
--mode: AGPS function mode, the following two (default is 0)
--0: Automatically connect background, download ephemeris data, write GPS module
--1: need to connect the background, the internal message AGPS_EVT, the user program to process the message to determine whether you need to connect; Download ephemeris data, write GPS module, after the end of the internal message AGPS_EVT to inform the user to download the results and write results
local mode = 0
--gpssupport: Is there a GPS module?
--eph: Ephemeris data downloaded from AGPS background
local gpssupport,eph = true,""
-- GET_TIMEOUT: GET command waiting time in milliseconds
--ERROR_PACK_TIMEOUT: Error packets (packet ID or length mismatch) are retrieved after a period of time
--GET_RETRY_TIMES: GET command timeout or error packet, the current packet allows the maximum number of retries
--PACKET_LEN: The maximum data length per packet, in bytes
--RETRY_TIMES: connect background, download the data process will be disconnected; if the download process fails, it will re-connect the background, start again from scratch. This variable refers to the maximum number of times background download is allowed to be reconnected
local GET_TIMEOUT,ERROR_PACK_TIMEOUT,GET_RETRY_TIMES,PACKET_LEN,RETRY_TIMES = 10000,5000,3,1024,3
--state: state machine state
--IDLE: Idle state
--CHECK: "Query server ephemeris data" status
--UPDATE: "download ephemeris data" status
--total = (int) ((10221 + 1021) / 1022) = 11; upgrade file is 10220 bytes, then total = (int) is the total number of packets, for example, ephemeris data is 10221 bytes, ((10220 + 1021) / 1022) = 10
-- last: the number of bytes in the last packet, for example, the upgrade file is 10225 bytes, last = 10225% 1022 = 5; the upgrade file is 10220 bytes, last = 1022
--checksum: Checksum store table for each ephemeris data
--packid: the current package index
--getretries: Get the number of times each package has been retry
-- Retries: re-connect background download, has retry the number of times
--reconnect: need to reconnect background
local state,total,last,checksum,packid,getretries,retries,reconnect = "IDLE",0,0,{},0,0,1,false

--Function name: startupdatetimer
--Function: Open the "connect background, update ephemeris data" timer
--Parameters: None
--Return Value: None

local function startupdatetimer()
	-- GPS support and AGPS support
	if gpssupport and ispt then
		sys.timer_start(connect,itv*1000)
	end
end

--Function name: gpsstateind
--Function: Handles the internal messages of the GPS module
--Parameters:
--id: gps.GPS_STATE_IND, do not have to deal with
--data: the type of the message parameter
--Return value: true

local function gpsstateind(id,data)
	-- GPS positioning successful
	if data == gps.GPS_LOCATION_SUC_EVT or data == gps.GPS_LOCATION_UNFILTER_SUC_EVT then
		sys.dispatch("AGPS_UPDATE_SUC")
		startupdatetimer()
		isfix = true
	-- GPS positioning failed or GPS off
	elseif data == gps.GPS_LOCATION_FAIL_EVT or data == gps.GPS_CLOSE_EVT then
		isfix = false
	-- No GPS chip
	elseif data == gps.GPS_NO_CHIP_EVT then
		gpssupport = false
	end
	return true
end

--Function name: writecmd
--Function: Write each ephemeris data to the GPS module
--Parameters:
--id: gps.GPS_STATE_IND, do not have to deal with
--data: the type of the message parameter
--Return value: true

local function writecmd()
	if eph and slen(eph) > 0 and not isfix then
		local h1,h2 = sfind(eph,"\181\98")
		if h1 and h2 then
			local id = ssub(eph,h2+1,h2+2)
			if id and slen(id) == 2 then
				local llow,lhigh = sbyte(eph,h2+3),sbyte(eph,h2+4)
				if lhigh and llow then
					local length = lhigh*256 + llow
					print("length",h2+6+length,slen(eph))
					if h2+6+length <= slen(eph) then
						gps.writegpscmd(false,ssub(eph,h1,h2+6+length),false)
						eph = ssub(eph,h2+7+length,-1)
						sys.timer_start(writecmd,WRITE_INTERVAL)
						return
					end
				end
			end
		end
	end
	gps.closegps("AGPS")
	eph = ""
	sys.dispatch("AGPS_UPDATE_SUC")
end

--Function name: startwrite
--Function: Start writing ephemeris data to GPS module
--Parameters: None
--Return Value: None

local function startwrite()
	if isfix or not gpssupport then
		eph = ""
		return
	end
	if eph and slen(eph) > 0 then
		gps.opengps("AGPS")
		sys.timer_start(writecmd,WRITE_INTERVAL)
	end
end


--Function name: calsum
--Function: Calculate checksum
--Parameters:
--str: The data to be calculated for the checksum
--Return Value: Checksum

local function calsum(str)
	local sum,i = 0
	for i=1,slen(str) do
		sum = sum + sbyte(str,i)
	end
	return sum
end

--Function name: errpack
--Function: Error packet handling
--Parameters:
--str: The data to be calculated for the checksum
--Return Value: Checksum

local function errpack()
	print("errpack")
	upend(false)
end

--Function name: retry
--Function: Retry action
--Parameters:
--para: If STOP, stop retry; otherwise, retry
--Return Value: None

function retry(para)
	if state ~= "UPDATE" and state ~= "CHECK" then
		return
	end

	if para == "STOP" then
		getretries = 0
		sys.timer_stop(errpack)
		sys.timer_stop(retry)
		return
	end

	if para == "ERROR_PACK" then
		sys.timer_start(errpack,ERROR_PACK_TIMEOUT)
		return
	end

	getretries = getretries + 1
	if getretries < GET_RETRY_TIMES then
		if state == "UPDATE" then
			-- The number of retries has not been reached, and continue to try to get the upgrade package
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

function reqget(idx)
	send(lid,sformat("Get%d",idx))
	sys.timer_start(retry,GET_TIMEOUT)
end

--Function name: getpack
--Function: Resolve a packet of data received from the server
--Parameters:
--data: package content
--Return Value: None

local function getpack(data)
	-- Determine whether the packet length is correct
	local len = slen(data)
	if (packid < total and len ~= PACKET_LEN) or (packid >= total and len ~= (last+2)) then
		print("getpack:len not match",packid,len,last)
		retry("ERROR_PACK")
		return
	end

	-- Determine packet number is correct
	local id = sbyte(data,1)*256 + sbyte(data,2)%256
	if id ~= packid then
		print("getpack:packid not match",id,packid)
		retry("ERROR_PACK")
		return
	end

	-- Check the checksum is correct
	local sum = calsum(ssub(data,3,-1))
	if checksum[id] ~= sum then
		print("getpack:checksum not match",checksum[id],sum)
		retry("ERROR_PACK")
		return
	end

	-- stop retrying
	retry("STOP")

	-- Save the ephemeris package
	eph = eph .. ssub(data,3,-1)

	-- Get the next package data
	if packid == total then
		sum = calsum(eph)
		if checksum[total+1] ~= sum then
			print("getpack:total checksum not match",checksum[total+1],sum)
			upend(false)
		else
			upend(true)
		end
	else
		packid = packid + 1
		reqget(packid)
	end
end

--Function name: upbegin
--Function: Analyze the ephemeris package information issued by the server
--Parameters:
--data: Ephemeris package information
--Return Value: None

local function upbegin(data)
	-- the number of packets, the last packet in bytes
	local d1,d2,p1,p2 = sfind(data,"AGPSUPDATE,(%d+),(%d+)")
	local i
	if d1 and d2 and p1 and p2 then
		p1,p2 = tonumber(p1),tonumber(p2)
		total,last = p1,p2
		local tmpdata = data
		-- Checksum of each ephemeris data
		for i=1,total+1 do
			if d2+2 > slen(tmpdata) then
				upend(false)
				return false
			end
			tmpdata = ssub(tmpdata,d2+2,-1)
			d1,d2,p1 = sfind(tmpdata,"(%d+)")
			if d1 == nil or d2 == nil or p1 == nil then
				upend(false)
				return false
			end
			checksum[i] = tonumber(p1)
		end

		getretries,state,packid,eph = 0,"UPDATE",1,""
		-- Request the first package
		reqget(packid)
		return true
	end

	upend(false)
	return false
end

--Function name: reqcheck
--Function: Send "request ephemeris information" data to the server
--Parameters: None
--Return Value: None

function reqcheck()
	state = "CHECK"
	send(lid,"AGPS")
	sys.timer_start(retry,GET_TIMEOUT)
end

--Function name: upend
--Function: Download finished
--Parameters:
--succ: As a result, true is successful and the rest is failed
--Return Value: None

function upend(succ)
	state = "IDLE"
	-- stop enriching the timer
	sys.timer_stop(retry)
	sys.timer_stop(errpack)
	-- Disconnect
	link.close(lid)
	getretries = 0
	if succ then
		reconnect = false
		retries = 0
		-- Write ephemeris information to GPS chip
		print("eph rcv",slen(eph))
		startwrite()
		startupdatetimer()
		if mode==1 then dispatch("AGPS_EVT","END_IND",true) end
	else
		if retries >= RETRY_TIMES then
			reconnect = false
			retries = 0
			startupdatetimer()
			if mode==1 then dispatch("AGPS_EVT","END_IND",false) end
		else
			reconnect = true
			retries = retries + 1
		end
	end
end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? data: received data
--Return Value: None

local function rcv(id,data)
	base.collectgarbage()
	-- stop retry timer
	sys.timer_stop(retry)
	-- If GPS positioning is successful or not supported
	if isfix or not gpssupport then
		upend(true)
		return
	end
	if state == "CHECK" then
		-- The total ephemeris information is returned
		if sfind(data,"AGPSUPDATE") == 1 then
			upbegin(data)
			return
		end
	elseif state == "UPDATE" then
		if data ~= "ERR" then
			getpack(data)
			return
		end
	end

	upend(false)
	return
end

--Function name: nofity
--Function: Socket state processing function
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? evt: message event type
--val: message event parameter
--Return Value: None

local function nofity(id,evt,val)
	print("agps notify",lid,id,evt,val,reconnect)
	if id ~= lid then return end
	-- If GPS positioning is successful or not supported
	if isfix or not gpssupport then
		upend(true)
		return
	end
	if evt == "CONNECT" then
		--connection succeeded
		if val == "CONNECT OK" then
			reqcheck()
		--Connection failed
		else
			upend(false)
		end
	elseif evt == "CLOSE" and reconnect then
		--Reconnection
		connect()
	elseif evt == "STATE" and val == "CLOSED" then
		upend(false)
	end
end

--Function name: connectcb
--Function: Connect to the server
--Parameters: None
--Return Value: None

local function connectcb()
	lid = link.open(nofity,rcv,"agps")
	link.connect(lid,PROT,SVR,PORT)
end

--Function name: connect
--Function: Connect to server request
--Parameters: None
--Return Value: None

function connect()
	if ispt then
		-- Automatic mode
		if mode==0 then
			connectcb()
		-- User control mode
		else
			dispatch("AGPS_EVT","BEGIN_IND",connectcb)
		end		
	end
end

--Function name: init
--Function: Set the connection server to update the ephemeris data interval and the module working mode
--Parameters:
--inv: update interval, in seconds
--md: working mode
--Return Value: None

function init(inv,md)
	itv = inv or itv
	mode = md or 0
	startupdatetimer()
end

--Function name: setspt
--Function: Set whether to enable AGPS function
--Parameters:
--spt: true is on, false or nil is off
--Return Value: None

function setspt(spt)
	if spt ~= nil and ispt ~= spt then
		ispt = spt
		if spt then
			startupdatetimer()
		end
	end
end

--Function name: load
--Function: Run this function module
--Parameters: None
--Return Value: None

local function load()
	-- (button to start or charge the boot) and allows the power to update the ephemeris data
	if (rtos.poweron_reason() == rtos.POWERON_KEY or rtos.poweron_reason() == rtos.POWERON_CHARGER) and gps.isagpspwronupd() then
		connect()
	else
		startupdatetimer()
	end
end

-- Register GPS message handler
sys.regapp(gpsstateind,gps.GPS_STATE_IND)
load()
