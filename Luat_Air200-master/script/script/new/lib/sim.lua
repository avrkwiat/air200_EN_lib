
--Module Name: sim card function
--Module Function: Check sim card status, iccid, imsi, mcc, mnc
--Last modified: 2017.02.13

-- Define module, import dependent libraries
local string = require"string"
local ril = require"ril"
local sys = require"sys"
local base = _G
local os = require"os"
module(...)

-- Load common global functions to local

local tonumber = base.tonumber
local tostring = base.tostring
local req = ril.request

-- sim card imsi, sim card iccid

local imsi,iccid,status

--Function name: geticcid
--Function: get iccid sim card
--Parameters: None
--Return Value: iccid, nil if not already read
--Note: After the boot lua script is run, it will send at command to query iccid, so it takes some time to get to iccid. Call this interface immediately after boot, basically returns nil

function geticcid()
	return iccid
end

--Function name: getimsi
--Function: Get sim card imsi
--Parameters: None
--Return Value: imsi, nil if not read
--Note: boot lua script is running, it will send the at command to query imsi, it takes some time to get imsi. Call this interface immediately after boot, basically returns nil

function getimsi()
	return imsi
end

--Function name: getmcc
--Function: Get sim card mcc
--Parameters: None
--Return Value: mcc, if not read, return ""
--Note: boot lua script is running, it will send the at command to query imsi, it takes some time to get imsi. Call this interface immediately after powering on, basically returning ""

function getmcc()
	return (imsi ~= nil and imsi ~= "") and string.sub(imsi,1,3) or ""
end

--Function name: getmnc
--Function: Get sim card getmnc
--Parameters: None
--Return Value: mnc, if not read, return ""
--Note: boot lua script is running, it will send the at command to query imsi, it takes some time to get imsi. Call this interface immediately after powering on, basically returning ""

function getmnc()
	return (imsi ~= nil and imsi ~= "") and string.sub(imsi,4,5) or ""
end

--Function name: getstatus
--Function: Get the status of sim card
--Parameters: None
--Return Value: true means the card is normal, false or nil means no card or card is detected
--Note: boot lua script is running, it will send at command to check the status, it takes some time to get to the state. Call this interface immediately after boot, basically returns nil

function getstatus()
	return status
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
	if cmd == "AT+CCID" then
		iccid = intermediate
	elseif cmd == "AT+CIMI" then
		imsi = intermediate
		-- Generate an internal message IMSI_READY, informing that imsi has been read

		sys.dispatch("IMSI_READY")
	end
end

--Function name: urc
--Function: The function of "registered core layer through the virtual serial port initiative to report the notification" of the processing
--Parameters:
--data: The complete string information for the notification
--prefix: The prefix of the notification
--Return Value: None

local function urc(data,prefix)
	--sim card status notification

	if prefix == "+CPIN" then
		status = false
		--sim card is normal

		if data == "+CPIN: READY" then
			status = true
			req("AT+CCID")
			req("AT+CIMI")
			sys.dispatch("SIM_IND","RDY")
		-- No sim card detected

		elseif data == "+CPIN: NOT INSERTED" then
			sys.dispatch("SIM_IND","NIST")
		else
			--sim card pin open

			if data == "+CPIN: SIM PIN" then
				sys.dispatch("SIM_IND","SIM_PIN")	
			end
			sys.dispatch("SIM_IND","NORDY")
		end
	end
end

-- Register AT + CCID command response function

ril.regrsp("+CCID",rsp)
-- Register AT + CIMI command response handler

ril.regrsp("+CIMI",rsp)
-- Register + CPIN notification handler

ril.regurc("+CPIN",urc)
