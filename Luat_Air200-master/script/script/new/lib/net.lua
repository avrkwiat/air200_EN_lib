
--Module Name: Network Management
--Module features: signal query, GSM network status query, network indicator control, near the district information query
--Last modified: 2017.02.17


-- Define module, import dependent libraries
local base = _G
local string = require"string"
local sys = require "sys"
local ril = require "ril"
local pio = require"pio"
local sim = require "sim"
module("net")

-- Load common global functions to local

local dispatch = sys.dispatch
local req = ril.request
local smatch,ssub = string.match,string.sub
local tonumber,tostring,print = base.tonumber,base.tostring,base.print
-- GSM network status:
--INIT: Status during power-on initialization
--REGISTERED: Register on the GSM network
--UNREGISTER: Not registered on GSM network
local state = "INIT"
-- SIM card status: true is abnormal, false or nil is normal

local simerrsta

--lac: location area ID
--ci: cell ID
-- rssi: signal strength
local lac,ci,rssi = "","",0

--csqqrypriod: signal strength timing query interval
--cengqrypriod: current and nearby cell information regularly query interval
local csqqrypriod,cengqrypriod = 60*1000

--cellinfo: current cell and neighbor cell information table
--flymode: Whether it is in flight mode
--csqswitch: timing query signal strength switch
--cengswitch: regularly check the current and nearby cell information switch
--multicellcb: Get multi-cell callback function
local cellinfo,flymode,csqswitch,cengswitch,multicellcb = {}

--ledstate: network indicator status INIT, FLYMODE, SIMERR, IDLE, CREG, CGATT, SCK
--INIT: function is off
-- FLYMODE: Flight mode
-- SIMERR: No detected SIM card or SIM card lock pin code and other abnormalities
--IDLE: Unregistered GSM network
--CREG: registered GSM network
--CGATT: GPRS data network attached
--SCK: User socket connected to the background
--ledontime: indicator light time (milliseconds)
--ledofftime: light off time (milliseconds)
--usersckconnect: user socket is connected to the background
local ledstate,ledontime,ledofftime,usersckconnect = "INIT",0,0
--ledflg: Network light switch
--ledpin: Network LED control pin
--ledvalid: The pin output level will light the indicator, 1 is high, 0 is low
--ledidleon, ledidleoff, ledcregon, ledcregoff, ledcgatton, ledcgattoff, ledsckon, ledsckoff: length of LED on and off in IDLE, CREG, CGATT,
local ledflg,ledpin,ledvalid,ledflymodeon,ledflymodeoff,ledsimerron,ledsimerroff,ledidleon,ledidleoff,ledcregon,ledcregoff,ledcgatton,ledcgattoff,ledsckon,ledsckoff = false,pio.P0_15,1,0,0xFFFF,300,5700,300,3700,300,1700,300,700,100,100

local creg3 -- flag parameter

--Function name: checkCRSM
--Function: If the registration is rejected, run this function, first determine whether to obtain imsi number, and then determine whether it is China Mobile Card
--If it is determined that China Mobile Card, the SIM card limit access
--parameter:
--return value:

local function checkCRSM()
	local imsi=sim.getimsi()
	if imsi and imsi~="" then
		if ssub(imsi,1,3)=="460" then
			local mnc=ssub(imsi,4,5)
			if (mnc=="00" or mnc=="02" or mnc=="04" or mnc=="07") and creg3 then
				req("AT+CRSM=176,28539,0,0,12")
			end
		end
	else 
		sys.timer_start(checkCRSM,5000)
	end
end

--Function name: creg
--Function: parse CREG information
--Parameters:
--data: CREG information string, for example + CREG: 2, + CREG: 1, "18be", "93e1", + CREG: 5, "18a7", "cb51"
--Return Value: None

local function creg(data)
	local p1,s
	-- Get registration status

	_,_,p1 = string.find(data,"%d,(%d)")
	if p1 == nil then
		_,_,p1 = string.find(data,"(%d)")
		if p1 == nil then
			return
		end
	end
	creg3 = false
	--registered

	if p1 == "1" or p1 == "5" then
		s = "REGISTERED"		
	--unregistered

	else
		if p1=="3" then
			creg3 = true
			checkCRSM()
		end
		s = "UNREGISTER"
	end
	-- The registration status has changed

	if s ~= state then
		--Near cell query processing

		if not cengqrypriod and s == "REGISTERED" then
			setcengqueryperiod(60000)
		else
			cengquery()
		end
		state = s
		-- Generate an internal message NET_STATE_CHANGED, indicating that the GSM network registration status changes

		dispatch("NET_STATE_CHANGED",s)
		-- Indicator control

		procled()
	end
	-- Registered and lac or ci changed

	if state == "REGISTERED" then
		p2,p3 = string.match(data,"\"(%x+)\",\"(%x+)\"")
		if lac ~= p2 or ci ~= p3 then
			lac = p2
			ci = p3
			-- Generate an internal message NET_CELL_CHANGED, that lac or ci has changed

			dispatch("NET_CELL_CHANGED")
		end
	end
end

--Function name: resetcellinfo
--Function: Reset the current cell and cell information table
--Parameters: None
--Return Value: None

local function resetcellinfo()
	local i
	cellinfo.cnt = 11 -- the maximum number

	for i=1,cellinfo.cnt do
		cellinfo[i] = {}
		cellinfo[i].mcc,cellinfo[i].mnc = nil
		cellinfo[i].lac = 0
		cellinfo[i].ci = 0
		cellinfo[i].rssi = 0
		cellinfo[i].ta = 0
	end
end

--Function name: ceng
--Function: resolve the current cell and the information of the neighboring cell
--Parameters:
--data: The current cell and neighbor cell information string, for example, each of the following lines:
--+ CENG: 1,1
--+ CENG: 0, "573,24,99,460,0,13,49234,10,0,6311,255"
--+ CENG: 1, "579,16,460,0,5,49233,6311"
--+ CENG: 2, "568,14,460,0,26,0,6311"
--+ CENG: 3, "584,13,460,0,10,0,6213"
--+ CENG: 4, "582, 13, 460, 0, 51, 50146, 6213"
--+ CENG: 5, "11,26,460,0,3,52049,6311"
--+ CENG: 6, "29,26,460,0,32,0,6311"
--Return Value: None

local function ceng(data)
	-- Only deal with valid CENG information

	if string.find(data,"%+CENG:%d+,\".+\"") then
		local id,rssi,lac,ci,ta,mcc,mnc
		id = string.match(data,"%+CENG:(%d)")
		id = tonumber(id)
		-- The first CENG information and the rest of the format

		if id == 0 then
			rssi,mcc,mnc,ci,lac,ta = string.match(data, "%+CENG:%d,\"%d+,(%d+),%d+,(%d+),(%d+),%d+,(%d+),%d+,%d+,(%d+),(%d+)\"")
		else
			rssi,mcc,mnc,ci,lac,ta = string.match(data, "%+CENG:%d,\"%d+,(%d+),(%d+),(%d+),%d+,(%d+),(%d+)\"")
		end
		-- parse correctly

		if rssi and ci and lac and mcc and mnc then
			-- If the first one, clear the information sheet

			if id == 0 then
				resetcellinfo()
			end
			-- save mcc, mnc, lac, ci, rssi, ta
			cellinfo[id+1].mcc = mcc
			cellinfo[id+1].mnc = mnc
			cellinfo[id+1].lac = tonumber(lac)
			cellinfo[id+1].ci = tonumber(ci)
			cellinfo[id+1].rssi = (tonumber(rssi) == 99) and 0 or tonumber(rssi)
			cellinfo[id+1].ta = tonumber(ta or "0")
			-- Generate an internal message CELL_INFO_IND, indicating that the new current cell and the neighboring cell information have been read

			if id == 0 then
				dispatch("CELL_INFO_IND",cellinfo)
			end
		end
	end
end

local crsmupdcnt = 0

--Function name: crsmrsp
--Function: Update FPLMN reply processing
--Parameters:
--cmd: AT command corresponding to this reply
--success: AT command execution result, true or false
--response: string of the execution result in the AT command's response
--intermediate: intermediate information in the response of the AT command
--Return Value: None

function crsmrsp(cmd,success,response,intermediate)
	print("crsmrsp",success)
	if success then
		sys.restart("crsmrsp suc")
	else
		crsmupdcnt = crsmupdcnt+1
		if crsmupdcnt>=3 then
			sys.restart("crsmrsp tmout")
		else
			req("AT+CRSM=214,28539,0,0,12,\"64f01064f03064f002fffff\"",nil,crsmrsp)
		end
	end
end

--Function name: neturc
--Function: The function of "registered core layer through the virtual serial port initiative to report the notification" of the processing
--Parameters:
--data: The complete string information for the notification
--prefix: The prefix of the notification
--Return Value: None

local function neturc(data,prefix)
	if prefix == "+CREG" then
		-- When receiving network status changes, update the signal value

		csqquery()
		-- resolve creg information

		creg(data)
	elseif prefix == "+CENG" then
		-- Parsing ceng information

		ceng(data)
	elseif prefix=="+CRSM" then
		local str = string.lower(data)
		if smatch(str,"64f000") or smatch(str,"64f020") or smatch(str,"64f040") or smatch(str,"64f070") then
			req("AT+CRSM=214,28539,0,0,12,\"64f01064f03064f002fffff\"",nil,crsmrsp)
		end
	end
end

--Function name: getstate
--Function: Get GSM network registration status
--Parameters: None
--Return Value: GSM Network Registration Status (INIT, REGISTERED, UNREGISTER)

function getstate()
	return state
end

--Function name: getmcc
--Function: Get the current cell mcc
--Parameters: None
--Return value: The current cell mcc, if not registered GSM network, then returns the sim card mcc

function getmcc()
	return cellinfo[1].mcc or sim.getmcc()
end

--Function name: getmnc
--Function: Get the current cell mnc
--Parameters: None
--Return value: The current cell mnc, if not registered GSM network, then return to sim card mnc

function getmnc()
	return cellinfo[1].mnc or sim.getmnc()
end

--Function name: getlac
--Function: Get the current location area ID
--Parameters: None
--Return Value: The current location area ID (hexadecimal string, for example, "18be"), if not already registered GSM network, return ""

function getlac()
	return lac
end

--Function name: getci
--Function: Get the current cell ID
--Parameters: None
--Return Value: The current cell ID (hexadecimal string, for example, "93e1"), if there is no GSM network, return ""

function getci()
	return ci
end

--Function name: getrssi
--Function: Get the signal strength
--Parameters: None
--Return Value: Current Signal Strength (Range 0-31)

function getrssi()
	return rssi
end

--Function name: getcell
--Function: Get the splicing string of current and nearby cells and signal strength
--Parameters: None
--Return Value: The concatenation string of current and neighboring cells and signal strength, for example: 49234.30.49233.23.49232.18.

function getcell()
	local i,ret = 1,""
	for i=1,cellinfo.cnt do
		if cellinfo[i] and cellinfo[i].lac and cellinfo[i].lac ~= 0 and cellinfo[i].ci and cellinfo[i].ci ~= 0 then
			ret = ret..cellinfo[i].ci.."."..cellinfo[i].rssi.."."
		end
	end
	return ret
end

--Function name: getcellinfo
--Function: Get the current and adjacent location area, cell and signal strength stitching string
--Parameters: None
--Return Value: The concatenation string of current and adjacent location area, cell and signal strength, for example: 6311.49234.30; 6311.49233.23; 6322.49232.18;

function getcellinfo()
	local i,ret = 1,""
	for i=1,cellinfo.cnt do
		if cellinfo[i] and cellinfo[i].lac and cellinfo[i].lac ~= 0 and cellinfo[i].ci and cellinfo[i].ci ~= 0 then
			ret = ret..cellinfo[i].lac.."."..cellinfo[i].ci.."."..cellinfo[i].rssi..";"
		end
	end
	return ret
end

--Function name: getcellinfoext
--Function: Get the current and adjacent location area, cell, mcc, mnc, and signal strength stitching string
--Parameters: None
--Return value: the current and adjacent location area, cell, mcc, mnc, and the stitching string of signal strength, for example: 460.01.6311.49234.30; 460.01.6311.49233.23; 460.02.6322.49232.18;

function getcellinfoext()
	local i,ret = 1,""
	for i=1,cellinfo.cnt do
		if cellinfo[i] and cellinfo[i].mcc and cellinfo[i].mnc and cellinfo[i].lac and cellinfo[i].lac ~= 0 and cellinfo[i].ci and cellinfo[i].ci ~= 0 then
			ret = ret..cellinfo[i].mcc.."."..cellinfo[i].mnc.."."..cellinfo[i].lac.."."..cellinfo[i].ci.."."..cellinfo[i].rssi..";"
		end
	end
	return ret
end

--[[
Function name: getta
Function: Get TA value
Parameters: None
Return value: TA value
]]
function getta()
	return cellinfo[1].ta
end

--Function name: startquerytimer
--Function: Empty function, no function, just to be compatible with the previously written application script
--Parameters: None
--Return Value: None

function startquerytimer() end

--Function name: simind
--Function: Handle function of internal message SIM_IND
--Parameters:
--para: parameter, indicating the status of the SIM card
--Return Value: None

local function simind(para)
	print("simind",simerrsta,para)
	if simerrsta ~= (para~="RDY") then
		simerrsta = (para~="RDY")
		procled()
	end
	--sim card is not working properly

	if para ~= "RDY" then
		-- Update GSM network status

		state = "UNREGISTER"
		-- Generate internal message NET_STATE_CHANGED, indicating that the network status has changed

		dispatch("NET_STATE_CHANGED",state)
	end
	return true
end

--Function name: flyind
--Function: The handler for the internal message FLYMODE_IND
--Parameters:
--para: parameter, said the state of the flight mode, true said to enter the flight mode, false means to exit the flight mode
--Return Value: None

local function flyind(para)
	-- Flight mode status changed

	if flymode~=para then
		flymode = para
		-- control network indicator

		procled()
	end
	-- Exit flight mode

	if not para then
		---- Processing query timer

		startcsqtimer()
		startcengtimer()
		-- Reset GSM network status

		neturc("2","+CREG")
	end
	return true
end

--Function name: workmodeind
--Function: The handler for the internal message SYS_WORKMODE_IND
--Parameters:
--para: parameter, said the system mode of operation
--Return Value: None

local function workmodeind(para)
	-- Processing query timer

	startcengtimer()
	startcsqtimer()
	return true
end

--Function name: startcsqtimer
--Function: Selectively start the "signal strength query" timer
--Parameters: None
--Return Value: None

function startcsqtimer()
	-- not flight mode and (query switch is turned on or working mode is full mode)

	if not flymode and (csqswitch or sys.getworkmode()==sys.FULL_MODE) then
		-- Send AT + CSQ query

		csqquery()
		-- Start the timer

		sys.timer_start(startcsqtimer,csqqrypriod)
	end
end

--Function name: startcengtimer
--Function: Selectively start the "current and neighboring cell information query" timer
--Parameters: None
--Return Value: None

function startcengtimer()
	-- Set query interval and not fly mode (and open the query switch or working mode is full mode)

	if cengqrypriod and not flymode and (cengswitch or sys.getworkmode()==sys.FULL_MODE) then
		-- Send AT + CENG? Query

		cengquery()
		-- Start the timer

		sys.timer_start(startcengtimer,cengqrypriod)
	end
end

--Function name: rsp
--Function: This function module "through the virtual serial port to the underlying core software AT command" response processing
--Parameters:
--cmd: AT command corresponding to this reply
--success: AT command execution result, true or false
--response: string of the execution result in the AT command's response
--intermediate: intermediate information in the response of the AT command
--Return Value: None

local function rsp(cmd,success,response,intermediate)
	local prefix = string.match(cmd,"AT(%+%u+)")

	if intermediate ~= nil then
		if prefix == "+CSQ" then
			local s = smatch(intermediate,"+CSQ:%s*(%d+)")
			if s ~= nil then
				rssi = tonumber(s)
				rssi = rssi == 99 and 0 or rssi
				-- Generate an internal message GSM_SIGNAL_REPORT_IND, indicating that the signal strength has been read

				dispatch("GSM_SIGNAL_REPORT_IND",success,rssi)
			end
		elseif prefix == "+CENG" then
		end
	end
end

--Function name: setcsqqueryperiod
--Function: Set the "signal strength" query interval
--Parameters:
--period: Query interval in milliseconds
--Return Value: None

function setcsqqueryperiod(period)
	csqqrypriod = period
	startcsqtimer()
end

--Function name: setcengqueryperiod
--Function: Set "current and neighboring cell information" query interval
--Parameters:
--period: Query interval in milliseconds. If less than or equal to 0, that stop the query function
--Return Value: None

function setcengqueryperiod(period)
	if period ~= cengqrypriod then		
		if period <= 0 then
			sys.timer_stop(startcengtimer)
		else
			cengqrypriod = period
			startcengtimer()
		end
	end
end

--Function name: cengquery
--Function: Query "current and neighboring cell information"
--Parameters: None
--Return Value: None

function cengquery()
	--Is not the flight mode, send AT + CENG?

	if not flymode then	req("AT+CENG?")	end
end

--Function name: setcengswitch
--Function: Set the "current and neighboring cell information" query switch
--Parameters:
--v: true is on, the rest is off
--Return Value: None

function setcengswitch(v)
	cengswitch = v
	-- Turned on and not in flight mode

	if v and not flymode then startcengtimer() end
end

--Function name: cellinfoind
--Function: CELL_INFO_IND message processing function
--Parameters: None
--Return Value: Returns nil if there is a user-defined callback function for obtaining multi-base station information; otherwise returns true

local function cellinfoind()
	if multicellcb then
		local cb = multicellcb
		multicellcb = nil
		cb(getcellinfoext())
	else
		return true
	end
end

--Function name: getmulticell
--Function: read "current and nearby cell information"
--Parameters:
--cb: callback function, when read to the cell information, call this callback function, call the form cb (cells), where cells is a string type, the format is:
--Current and neighboring location area, cell, mcc, mnc, and splicing string of signal strength, for example: 460.01.6311.49234.30; 460.01.6311.49233.23; 460.02.6322.49232.18;
--Return Value: None

function getmulticell(cb)
	multicellcb = cb
	cengquery()
end

--[[
Function name: csqquery
Function: Query "signal strength"
Parameters: None
Return Value: None
]]
function csqquery()
	-- Not flight mode, send AT + CSQ

	if not flymode then req("AT+CSQ") end
end

--Function name: setcsqswitch
--Function: Set the "signal strength" query switch
--Parameters:
--v: true is on, the rest is off
--Return Value: None

function setcsqswitch(v)
	csqswitch = v
	-- Turned on and not in flight mode

	if v and not flymode then startcsqtimer() end
end

--Function name: ledblinkon
--Function: light network indicator
--Parameters: None
--Return Value: None

local function ledblinkon()
	--print("ledblinkon",ledstate,ledontime,ledofftime)
	-- Pin output level control indicator lights

	pio.pin.setval(ledvalid==1 and 1 or 0,ledpin)
	-- Always off

	if ledontime==0 and ledofftime==0xFFFF then
		ledblinkoff()
	-- Always light

	elseif ledontime==0xFFFF and ledofftime==0 then
		-- Turn off the on-duration timer and off-time timer

		sys.timer_stop(ledblinkon)
		sys.timer_stop(ledblinkoff)
	-- flashing

	else
		-- Start-up time-on timer, after the timer has expired, turn off the indicator

		sys.timer_start(ledblinkoff,ledontime)
	end	
end

--Function name: ledblinkoff
--Function: turn off the network indicator
--Parameters: None
--Return Value: None

function ledblinkoff()
	--print("ledblinkoff",ledstate,ledontime,ledofftime)
	-- The pin output level control indicator is off

	pio.pin.setval(ledvalid==1 and 0 or 1,ledpin)
	-- Always off

	if ledontime==0 and ledofftime==0xFFFF then
		-- Turn off the on-duration timer and off-time timer

		sys.timer_stop(ledblinkon)
		sys.timer_stop(ledblinkoff)
	-- Always light

	elseif ledontime==0xFFFF and ledofftime==0 then
		ledblinkon()
	-- flashing

	else
		-- Start time-out timer, after timing, light indicator

		sys.timer_start(ledblinkon,ledofftime)
	end	
end

--Function name: procled
--Function: Update network indicator status and on and off duration
--Parameters: None
--Return Value: None

function procled()
	print("procled",ledflg,ledstate,flymode,usersckconnect,cgatt,state)
	-- If the network indicator is turned on

	if ledflg then
		local newstate,newontime,newofftime = "IDLE",ledidleon,ledidleoff
		-- Flight mode

		if flymode then
			newstate,newontime,newofftime = "FLYMODE",ledflymodeon,ledflymodeoff
		elseif simerrsta then
			newstate,newontime,newofftime = "SIMERR",ledsimerron,ledsimerroff
		-- User socket connected to the background

		elseif usersckconnect then
			newstate,newontime,newofftime = "SCK",ledsckon,ledsckoff
		-- Attached to the GPRS data network

		elseif cgatt then
			newstate,newontime,newofftime = "CGATT",ledcgatton,ledcgattoff
		-- Register on the GSM network

		elseif state=="REGISTERED" then
			newstate,newontime,newofftime = "CREG",ledcregon,ledcregoff		
		end
		-- Indicator status changed

		if newstate~=ledstate then
			ledstate,ledontime,ledofftime = newstate,newontime,newofftime
			ledblinkoff()
		end
	end
end

--Function name: usersckind
--Function: Handler for internal message USER_SOCKET_CONNECT
--Parameters:
--v: parameter, said user socket is connected to the background
--Return Value: None

local function usersckind(v)
	print("usersckind",v)
	if usersckconnect~=v then
		usersckconnect = v
		procled()
	end
end

--Function name: cgattind
--Function: The handler for the internal message NET_GPRS_READY
--Parameters:
--v: parameter, indicating whether the GPRS data network attached
--Return Value: None

local function cgattind(v)
	print("cgattind",v)
	if cgatt~=v then
		cgatt = v
		procled()
	end
end

--Function name: setled
--Function: Set network indicator function
--Parameters:
--v: light switch, true is on, the rest is off
--pin: LED control pin, optional
--valid: The pin output level will light the indicator, 1 is high, 0 is low, optional
--flymodeoff, simerron, simerroff, idleon, idleoff, cregon, cregoff, cgatton, cgattoff, sckon, sckoff: FLYMODE, SIMERR, IDLE, CREG, CGATT, selected
--Return Value: None

function setled(v,pin,valid,flymodeon,flymodeoff,simerron,simerroff,idleon,idleoff,cregon,cregoff,cgatton,cgattoff,sckon,sckoff)
	local c1 = (ledflg~=v or ledpin~=(pin or ledpin) or ledvalid~=(valid or ledvalid))
	local c2 = (ledidleon~=(idleon or ledidleon) or ledidleoff~=(idleoff or ledidleoff) or flymodeon~=(flymodeon or ledflymodeon) or flymodeoff~=(flymodeoff or ledflymodeoff))
	local c3 = (ledcregon~=(cregon or ledcregon) or ledcregoff~=(cregoff or ledcregoff) or ledcgatton~=(cgatton or ledcgatton) or simerron~=(simerron or ledsimerron))
	local c4 = (ledcgattoff~=(cgattoff or ledcgattoff) or ledsckon~=(sckon or ledsckon) or ledsckoff~=(sckoff or ledsckoff) or simerroff~=(simerroff or ledsimerroff))
	-- Change in switch value or change in other parameters

	if c1 or c2 or c3 or c4 then
		local oldledflg = ledflg
		ledflg = v
		-- open

		if v then
			ledpin,ledvalid,ledidleon,ledidleoff,ledcregon,ledcregoff = pin or ledpin,valid or ledvalid,idleon or ledidleon,idleoff or ledidleoff,cregon or ledcregon,cregoff or ledcregoff
			ledcgatton,ledcgattoff,ledsckon,ledsckoff = cgatton or ledcgatton,cgattoff or ledcgattoff,sckon or ledsckon,sckoff or ledsckoff
			ledflymodeon,ledflymodeoff,ledsimerron,ledsimerroff = flymodeon or ledflymodeon,flymodeoff or ledflymodeoff,simerron or ledsimerron,simerroff or ledsimerroff
			if not oldledflg then pio.pin.setdir(pio.OUTPUT,ledpin) end
			procled()
		--shut down

		else
			sys.timer_stop(ledblinkon)
			sys.timer_stop(ledblinkoff)
			if oldledflg then
				pio.pin.setval(ledvalid==1 and 0 or 1,ledpin)
				pio.pin.close(ledpin)
			end
			ledstate = "INIT"
		end		
	end
end

-- This module focuses on the internal message processing function table

local procer =
{
	SIM_IND = simind,
	FLYMODE_IND = flyind,
	SYS_WORKMODE_IND = workmodeind,
	USER_SOCKET_CONNECT = usersckind,
	NET_GPRS_READY = cgattind,
	CELL_INFO_IND = cellinfoind,
}
-- Register message processing function table

sys.regapp(procer)
-- Register handling functions for + CREG and + CENG notifications

ril.regurc("+CREG",neturc)
ril.regurc("+CENG",neturc)
ril.regurc("+CRSM",neturc)
-- Register AT + CCSQ and AT + CENG? Command response function

ril.regrsp("+CSQ",rsp)
ril.regrsp("+CENG",rsp)
-- Send AT command

req("AT+CREG=2")
req("AT+CREG?")
req("AT+CENG=1,1")
-- 8 seconds after the first query csq

sys.timer_start(startcsqtimer,8*1000)
resetcellinfo()
setled(true)
