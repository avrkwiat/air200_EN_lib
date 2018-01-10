
--Module Name: Miscellaneous Management
--Module features: serial number, IMEI, the underlying software version number, clock, whether calibration, flight mode, check the battery power and other functions
--Last modified on: 2017.02.14

-- Define module, import dependent libraries
local string = require"string"
local ril = require"ril"
local sys = require"sys"
local base = _G
local os = require"os"
local io = require"io"
local rtos = require"rtos"
local pmd = require"pmd"
module(...)

-- Load common global functions to local

local tonumber,tostring,print,req,smatch = base.tonumber,base.tostring,base.print,ril.request,string.match

--sn: serial number
--snrdy: has successfully read the serial number
--imei: IMEI
--imeirdy: Has the IMEI been successfully read?
--ver: the underlying software version number
--clkswitch: whole clock notification switch
--updating: whether to perform remote upgrade (update.lua)
--dbging: Whether dbg functions are being executed (dbg.lua)
--ntping: Whether to perform NTP time synchronization (ntp.lua)
--flypending: Is there any pending flight mode request?
local sn,snrdy,imeirdy,--[[ver,]]imei,clkswitch,updating,dbging,ntping,flypending

--calib: calibration mark, true is calibrated, the rest is not calibrated
--setclkcb: execute AT + CCLK command, the user-defined callback function after the reply
-- wimeicb: execute AT + WIMEI command, the user-defined callback function after the reply
--wsncb: execute AT + WISN command, the user-defined callback function after the reply
local calib,setclkcb,wimeicb,wsncb

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
	-- Query the serial number
	if cmd == "AT+WISN?" then
		sn = intermediate
		-- If the serial number has not been successfully read, an internal message SN_READY is generated indicating that the serial number has been read

		if not snrdy then sys.dispatch("SN_READY") snrdy = true end
	-- Query the underlying software version number
	--[[elseif cmd == "AT + VER" then
		ver = intermediate]]
	-- Query IMEI
	elseif cmd == "AT+CGSN" then
		imei = intermediate
		-- If no IMEI has been successfully read, an internal message IMEI_READY is generated indicating that the IMEI has been read

		if not imeirdy then sys.dispatch("IMEI_READY") imeirdy = true end
	-- Write IMEI

	elseif smatch(cmd,"AT%+WIMEI=") then
		if wimeicb then wimeicb(success) end
	-- Write the serial number

	elseif smatch(cmd,"AT%+WISN=") then
		if wsncb then wsncb(success) end
	-- Set the system time

	elseif prefix == "+CCLK" then
		startclktimer()
		-- AT command response processing is completed, if there is a callback function

		if setclkcb then
			setclkcb(cmd,success,response,intermediate)
		end
	-- Check whether the calibration

	elseif cmd == "AT+ATWMFT=99" then
		print('ATWMFT',intermediate)
		if intermediate == "SUCC" then
			calib = true
		else
			calib = false
		end
	-- Enter or exit flight mode

	elseif smatch(cmd,"AT%+CFUN=[01]") then
		-- Generate an internal message FLYMODE_IND indicating that the flight mode status has changed

		sys.dispatch("FLYMODE_IND",smatch(cmd,"AT%+CFUN=(%d)")=="0")
	end
	
end

--Function name: setclock
--Function: Set the system time
--Parameters:
--t: system timeframe, format reference: {year = 2017, month = 2, day = 14, hour = 14, min = 2, sec = 58}
--rspfunc: Set user-defined callback function after system time
--Return Value: None

function setclock(t,rspfunc)
	if t.year - 2000 > 38 then return end
	setclkcb = rspfunc
	req(string.format("AT+CCLK=\"%02d/%02d/%02d,%02d:%02d:%02d+32\"",string.sub(t.year,3,4),t.month,t.day,t.hour,t.min,t.sec),nil,rsp)
end

--Function name: getclockstr
--Function: Get the system time string
--Parameters: None
--Return Value: The system time string, the format is YYMMDDhhmmss, for example, 170214141602, February 14, 17 14:16:02

function getclockstr()
	local clk = os.date("*t")
	clk.year = string.sub(clk.year,3,4)
	return string.format("%02d%02d%02d%02d%02d%02d",clk.year,clk.month,clk.day,clk.hour,clk.min,clk.sec)
end

--Function name: getweek
--Function: Get the week
--Parameters: None
--Return value: Weekday, number type, 1-7 correspond to Monday to Sunday respectively

function getweek()
	local clk = os.date("*t")
	return ((clk.wday == 1) and 7 or (clk.wday - 1))
end

--Function name: getclock
--Function: Get the system schedule
--Parameters: None
--Returns: The time of the table type, for example {year = 2017, month = 2, day = 14, hour = 14, min = 19, sec = 23}

function getclock()
	return os.date("*t")
end
--Function name: startclktimer
--Function: Selective start of the whole clock notification timer
--Parameters: None
--Return Value: None

function startclktimer()
	-- The switch is on or the operating mode is full mode

	if clkswitch or sys.getworkmode()==sys.FULL_MODE then
		-- Generate an internal message CLOCK_IND, that is now the whole point, for example, 12:13:00, 14:34:00

		sys.dispatch("CLOCK_IND")
		print('CLOCK_IND',os.date("*t").sec)
		-- Start the timer for next notification

		sys.timer_start(startclktimer,(60-os.date("*t").sec)*1000)
	end
end

--Function name: setclkswitch
--Function: Set the "Divide Clock Notification" switch
--Parameters:
--v: true is on, the rest is off
--Return Value: None

function setclkswitch(v)
	clkswitch = v
	if v then startclktimer() end
end

--Function name: getsn
--Function: Get the serial number
--Parameters: None
--Return value: serial number, if it is not returned, return ""

function getsn()
	return sn or ""
end

--Function name: isnvalid
--Function: to determine whether sn is valid
--Parameters: None
--Returns: valid Returns true, false otherwise

function isnvalid()
	local snstr,sninvalid = getsn(),""
	local len,i = string.len(snstr)
	for i=1,len do
		sninvalid = sninvalid.."0"
	end
	return snstr~=sninvalid
end

--Function name: getimei
--Function: Get IMEI
--Parameters: None
--Return value: IMEI number, if not get back ""
--Note: After the boot lua script is run, it will send the at command to query imei, so take some time to get imei. Call this interface immediately after powering on, basically returning ""

function getimei()
	return imei or ""
end

--Function name: setimei
--Function: Set IMEI
--If incoming cb, then set IMEI will not automatically restart, the user must ensure that the success of their own settings, call sys.restart or dbg.restart interface for a soft restart;
--If not imported cb, the software will automatically restart after setting
--Parameters:
--s: new IMEI
--cb: Set the callback function, call the settings will be passed out, true said that the setting was successful, false or nil that failed;
--Return Value: None

function setimei(s,cb)
	if s==imei then
		if cb then cb(true) end
	else
		req("AT+AMFAC="..(cb and "0" or "1"))
		req("AT+WIMEI=\""..s.."\"")
		wimeicb = cb
	end
end

--Function name: setsn
--Function: Set SN
--If incoming cb, then set the SN does not automatically restart, the user must ensure that the success of their own settings, call sys.restart or dbg.restart interface for a soft restart;
--If not imported cb, the software will automatically restart after setting
--Parameters:
--s: new SN
--cb: Set the callback function, call the settings will be passed out, true said that the setting was successful, false or nil that failed;
--Return Value: None

function setsn(s,cb)
	if s==sn then
		if cb then cb(true) end
	else
		req("AT+AMFAC="..(cb and "0" or "1"))
		req("AT+WISN=\""..s.."\"")
		wsncb = cb
	end
end


--Function name: setflymode
--Function: Control flight mode
--Parameters:
--val: true to enter the flight mode, false to exit the flight mode
--Return Value: None

function setflymode(val)
	-- If it is in flight mode

	if val then
		-- Delay in flight mode if you are performing a remote upgrade feature or dbg feature or ntp feature

		if updating or dbging or ntping then flypending = true return end
	end
	-- Send AT commands to enter or exit flight mode

	req("AT+CFUN="..(val and 0 or 1))
	flypending = false
end

--Function name: set
--Function: compatible with the old program written before, currently empty function
--Parameters: None
--Return Value: None

function set() end

--Function name: getcalib
--Function: Get the calibration flag
--Parameters: None
--Return value: true for the calibration, the rest is not calibrated

function getcalib()
	return calib
end

--Function name: getvbatvolt
--Function: Get VBAT battery voltage
--Parameters: None
--Return Value: voltage, number type, millivolt

function getvbatvolt()
	local v1,v2,v3,v4,v5 = pmd.param_get()
	return v2
end

--Function name: ind
--Function: This module registers the internal message processing function
--Parameters:
--id: internal message id
--para: internal message parameter
--Return value: true

local function ind(id,para)
	-- The working model has changed

	if id=="SYS_WORKMODE_IND" then
		startclktimer()
	-- Remote upgrade begins

	elseif id=="UPDATE_BEGIN_IND" then
		updating = true
	-- Remote upgrade finished

	elseif id=="UPDATE_END_IND" then
		updating = false
		if flypending then setflymode(true) end
	--dbg function started

	elseif id=="DBG_BEGIN_IND" then
		dbging = true
	--dbg function is over

	elseif id=="DBG_END_IND" then
		dbging = false
		if flypending then setflymode(true) end
	-- NTP synchronization starts

	elseif id=="NTP_BEGIN_IND" then
		ntping = true
	-- NTP synchronization ends

	elseif id=="NTP_END_IND" then
		ntping = false
		if flypending then setflymode(true) end
	end

	return true
end

-- Register the response handler for the following AT commands

ril.regrsp("+ATWMFT",rsp)
ril.regrsp("+WISN",rsp)
--ril.regrsp("+VER",rsp,4,"^[%w_]+$")
ril.regrsp("+CGSN",rsp)
ril.regrsp("+WIMEI",rsp)
ril.regrsp("+AMFAC",rsp)
ril.regrsp("+CFUN",rsp)
-- Check whether the calibration

req("AT+ATWMFT=99")
-- Query the serial number

req("AT+WISN?")
-- Query the underlying software version number
--req("AT+VER")
-- Query IMEI

req("AT+CGSN")
-- Start whole clock notification timer
startclktimer()
-- Register the handler for the internal message of interest to this module

sys.regapp(ind,"SYS_WORKMODE_IND","UPDATE_BEGIN_IND","UPDATE_END_IND","DBG_BEGIN_IND","DBG_END_IND","NTP_BEGIN_IND","NTP_END_IND")
