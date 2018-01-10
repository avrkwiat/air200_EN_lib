
--Module Name: Call Management
--Module Features: Incoming, outgoing, answering, hanging up
--Module last modified: 2017.02.20

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local table = require"table"
local sys = require"sys"
local ril = require"ril"
local net = require"net"
local pm = require"pm"
module(...)

-- Load common global functions to local
local ipairs,pairs,print,unpack,type = base.ipairs,base.pairs,base.print,base.unpack,base.type
local req = ril.request

-- The underlying call module is ready, true ready, false or nil not ready
local ccready = false
-- call presence flag, true if:
-- The caller is calling out, the called party is ringing, and the call is in progress
local callexist = false
-- Record the caller ID to ensure that the same phone rings more than once only
local incoming_num = nil 
-- emergency number table
local emergency_num = {"112", "911", "000", "08", "110", "119", "118", "999"}
-- Call list
local oldclcc,clcc = {},{}
-- Status change notification callback
local usercbs = {}


--Function name: print
--Function: Print Interface, all print in this file will be added cc prefix
--Parameters: None
--Return Value: None

local function print(...)
	base.print("cc",...)
end

--Function name: dispatch
--Function: Performs the user callback corresponding to each internal message
--Parameters:
--evt: message type
--para: message parameter
--Return Value: None

local function dispatch(evt,para)
	local tag = string.match(evt,"CALL_(.+)")
	if usercbs[tag] then usercbs[tag](para) end
end

--Function name: regcb
--Function: User callback function to register one or more messages
--Parameters:
--evt1: message type, currently only supports "READY", "INCOMING", "CONNECTED", "DISCONNECTED", "DTMF", "ALERTING"
--cb1: user callback function corresponding to the message
--...: evt and cb appear in pairs
--Return Value: None

function regcb(evt1,cb1,...)
	usercbs[evt1] = cb1
	local i
	for i=1,arg.n,2 do
		usercbs[unpack(arg,i,i)] = unpack(arg,i+1,i+1)
	end
end

--Function name: deregcb
--Function: Undo the user callback function to register one or more messages
--Parameters:
--evt1: message type, currently only supports "READY", "INCOMING", "CONNECTED", "DISCONNECTED", "DTMF", "ALERTING"
--...: 0 or more evt
--Return Value: None

function deregcb(evt1,...)
	usercbs[evt1] = nil
	local i
	for i=1,arg.n do
		usercbs[unpack(arg,i,i)] = nil
	end
end

--Function name: isemergencynum
--Function: Check whether the number is emergency number
--Parameters:
--num: number to be checked
--Return Value: true is the emergency number, false is not the emergency number

local function isemergencynum(num)
	for k,v in ipairs(emergency_num) do
		if v == num then
			return true
		end
	end
	return false
end

--Function name: clearincomingflag
--Function: Clear caller ID
--Parameters: None
--Return Value: None

local function clearincomingflag()
	incoming_num = nil
end

--Function name: discevt
--Function: call end message processing
--Parameters:
--reason: the end reason
--Return Value: None

local function discevt(reason)
	callexist = false -- End of call Clears the call status flag

	if incoming_num then sys.timer_start(clearincomingflag,1000) end
	pm.sleep("cc")
	-- Generate an internal message CALL_DISCONNECTED to notify the user that the call ends

	dispatch("CALL_DISCONNECTED",reason)
	sys.timer_stop(qrylist,"MO")
end

--Function name: anycallexist
--Function: Is there a call?
--Parameters: None
--Return Value: The call returns true, otherwise it returns false

function anycallexist()
	return callexist
end

--Function name: qrylist
--Function: Check the call list
--Parameters: None
--Return Value: None

function qrylist()
	oldclcc = clcc
	clcc = {}
	req("AT+CLCC")
end

local function proclist()
	local k,v,isactive
	for k,v in pairs(clcc) do
		if v.sta == "0" then isactive = true break end
	end
	if isactive and #clcc > 1 then
		for k,v in pairs(clcc) do
			if v.sta ~= "0" then req("AT+CHLD=1"..v.id) end			
		end
	end
	
	if usercbs["ALERTING"] and #clcc >= 1 then
		for k,v in pairs(clcc) do
			if v.sta == "3" then
				--[[dispatch("CALL_ALERTING")
				break]]
				for m,n in pairs(oldclcc) do
					if v.id==n.id and v.dir==n.dir and n.sta~="3" then
						dispatch("CALL_ALERTING")
						break
					end
				end
			end
		end
	end
end

--Function name: dial
--Function: Call a number
--Parameters:
--number: number
--delay: delay at least milliseconds before sending at command call, the default is not delayed
--Return value: true means that at command dialing is allowed and send at, false means at command dialing is not allowed

function dial(number,delay)
	if number == "" or number == nil then
		return false
	end

	if ccready == false and not isemergencynum(number) then
		return false
	end

	pm.wake("cc")
	req(string.format("%s%s;","ATD",number),nil,nil,delay)
	callexist = true -- The caller is calling out


	return true
end

--Function name: hangupnxt
--Function: take the initiative to hang up all the calls
--Parameters: None
--Return Value: None

local function hangupnxt()
	req("AT+CHUP")
end

--Function name: hangup
--Function: take the initiative to hang up all the calls
--Parameters: None
--Return Value: None

function hangup()
	-- if audio module exists
	if audio and type(audio)=="table" and audio.play then
		-- Stop audio playback first
		sys.dispatch("AUDIO_STOP_REQ",hangupnxt)
	else
		hangupnxt()
	end
end

--Function name: acceptnxt
--Function: answer the call
--Parameters: None
--Return Value: None

local function acceptnxt()
	req("ATA")
	pm.wake("cc")
end

--Function name: accept
--Function: answer the call
--Parameters: None
--Return Value: None

function accept()
	-- if audio module exists
	if audio and type(audio)=="table" and audio.play then
		-- Stop audio playback first
		sys.dispatch("AUDIO_STOP_REQ",acceptnxt)
	else
		acceptnxt()
	end		
end

--Function name: transvoice
--Function: Send voice to peer during call, it must be 12.2K AMR format
--Parameters:
--Return Value: true is successful, false is failed

function transvoice(data,loop,loop2)
	local f = io.open("/RecDir/rec000","wb")

	if f == nil then
		print("transvoice:open file error")
		return false
	end

	-- File header and is 12.2K frames
	if string.sub(data,1,7) == "#!AMR\010\060" then
	-- No file header and is 12.2K frames
	elseif string.byte(data,1) == 0x3C then
		f:write("#!AMR\010")
	else
		print("transvoice:must be 12.2K AMR")
		return false
	end

	f:write(data)
	f:close()

	req(string.format("AT+AUDREC=%d,%d,2,0,50000",loop2 == true and 1 or 0,loop == true and 1 or 0))

	return true
end

--Function name: dtmfdetect
--Function: Set dtmf detection is enabled and the sensitivity
--Parameters:
--enable: true enable, false or nil disable
--sens: sensitivity, the default 3, the most sensitive to 1
--Return Value: None

function dtmfdetect(enable,sens)
	if enable == true then
		if sens then
			req("AT+DTMFDET=2,1," .. sens)
		else
			req("AT+DTMFDET=2,1,3")
		end
	end

	req("AT+DTMFDET="..(enable and 1 or 0))
end

--Function name: senddtmf
--Function: Send dtmf to the opposite end
--Parameters:
--str: dtmf string
--playtime: Each dtmf play time in milliseconds, the default 100
--intvl: two dtmf intervals, in milliseconds, the default 100
--Return Value: None

function senddtmf(str,playtime,intvl)
	if string.match(str,"([%dABCD%*#]+)") ~= str then
		print("senddtmf: illegal string "..str)
		return false
	end

	playtime = playtime and playtime or 100
	intvl = intvl and intvl or 100

	req("AT+SENDSOUND="..string.format("\"%s\",%d,%d",str,playtime,intvl))
end

local dtmfnum = {[71] = "Hz1000",[69] = "Hz1400",[70] = "Hz2300"}

--Function name: parsedtmfnum
--Function: dtmf decoding, decoding, it will generate an internal message AUDIO_DTMF_DETECT, carrying the decoded DTMF characters
--Parameters:
--data: dtmf string data
--Return Value: None

local function parsedtmfnum(data)
	local n = base.tonumber(string.match(data,"(%d+)"))
	local dtmf

	if (n >= 48 and n <= 57) or (n >=65 and n <= 68) or n == 42 or n == 35 then
		dtmf = string.char(n)
	else
		dtmf = dtmfnum[n]
	end

	if dtmf then
		dispatch("CALL_DTMF",dtmf)
	end
end

--Function name: ccurc
--Function: The function of "registered core layer through the virtual serial port initiative to report the notification" of the processing
--Parameters:
--data: The complete string information for the notification
--prefix: The prefix of the notification
--Return Value: None

local function ccurc(data,prefix)
	-- The floor call module is ready
	if data == "CALL READY" then
		ccready = true
		dispatch("CALL_READY")
		req("AT+CCWA=1")
	-- call establishment notification
	elseif data == "CONNECT" then
		qrylist()		
		dispatch("CALL_CONNECTED")
		sys.timer_stop(qrylist,"MO")
		-- Stop audio playback first
		sys.dispatch("AUDIO_STOP_REQ")
	-- Call hang up notification
	elseif data == "NO CARRIER" or data == "BUSY" or data == "NO ANSWER" then
		qrylist()
		discevt(data)
	-- incoming call ringing
	elseif prefix == "+CLIP" then
		qrylist()
		local number = string.match(data,"\"(%+*%d*)\"",string.len(prefix)+1)
		callexist = true -- called ringing
		if incoming_num ~= number then
			incoming_num = number
			dispatch("CALL_INCOMING",number)
		end
	elseif prefix == "+CCWA" then
		qrylist()
	-- Call list information
	elseif prefix == "+CLCC" then
		local id,dir,sta = string.match(data,"%+CLCC:%s*(%d+),(%d),(%d)")
		if id then
			table.insert(clcc,{id=id,dir=dir,sta=sta})
			proclist()
		end
	--DTMF receive test
	elseif prefix == "+DTMFDET" then
		parsedtmfnum(data)
	end
end

--Function name: ccrsp
--Function: This function module "through the virtual serial port to the underlying core software AT command" response processing
--Parameters:
--cmd: AT command corresponding to this reply
--success: AT command execution result, true or false
--response: string of the execution result in the AT command's response
--intermediate: intermediate information in the response of the AT command
--Return Value: None

local function ccrsp(cmd,success,response,intermediate)
	local prefix = string.match(cmd,"AT(%+*%u+)")
	-- Dial-up reply
	if prefix == "D" then
		if not success then
			discevt("CALL_FAILED")
		else
			if usercbs["ALERTING"] then sys.timer_loop_start(qrylist,1000,"MO") end
		end
	-- Hang up all call answering
	elseif prefix == "+CHUP" then
		discevt("LOCAL_HANG_UP")
	-- Answer the call
	elseif prefix == "A" then
		incoming_num = nil
		dispatch("CALL_CONNECTED")
		sys.timer_stop(qrylist,"MO")
	end
	qrylist()
end

-- Register the handler for the notification below
ril.regurc("CALL READY",ccurc)
ril.regurc("CONNECT",ccurc)
ril.regurc("NO CARRIER",ccurc)
ril.regurc("NO ANSWER",ccurc)
ril.regurc("BUSY",ccurc)
ril.regurc("+CLIP",ccurc)
ril.regurc("+CLCC",ccurc)
ril.regurc("+CCWA",ccurc)
ril.regurc("+DTMFDET",ccurc)
-- Register the response handler for the following AT commands
ril.regrsp("D",ccrsp)
ril.regrsp("A",ccrsp)
ril.regrsp("+CHUP",ccrsp)
ril.regrsp("+CHLD",ccrsp)

-- Turn on dial tone, busy tone detection
req("ATX4") 
-- Open call urc reported
req("AT+CLIP=1")
dtmfdetect(true)
