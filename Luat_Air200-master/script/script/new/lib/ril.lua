--Module Name: Virtual Serial Port AT Command Interaction Management
--Module Function: AT interaction
--Last modified: 2017.02.13

-- Define module, import dependent libraries
local base = _G
local table = require"table"
local string = require"string"
local uart = require"uart"
local rtos = require"rtos"
local sys = require"sys"
module("ril")

-- Load common global functions to local

local setmetatable = base.setmetatable
local print = base.print
local type = base.type
local smatch = string.match
local sfind = string.find
local vwrite = uart.write
local vread = uart.read

-- Whether transparent mode, true for transparent mode, false or nil for non-transparent mode
-- Default non-transparent mode
local transparentmode
-- Transparent transmission mode, the virtual serial port receive data processing functions

local rcvfunc

--There is no feedback 1 minute after the AT command is executed. If at command execution fails, restart the software

local TIMEOUT = 60000 

--AT command response type
--NORESULT: received response data as urc notification processing, if the AT command is not sent to respond or not set the type, the default is this type
--NUMBERIC: pure numeric type; for example, send AT + CGSN command, the content of the reply is: 862991527986589 \ r \ nOK, this type refers to 862991527986589 This part is of pure numeric type
--SLINE: a single-line prefix string type; for example, send AT + CSQ command, the response is: + CSQ: 23,99 \ r \ nOK, this type refers to + CSQ: 23,99 This part is a single line String type
--MLINE: Prefix multi-line string type; for example, send the AT + CMGR = 5 command, the content of the reply is: + CMGR: 0,, 84 \ r \ n0891683108200105F76409A001560889F80008712031523842342050003590404590D003A59 \ r \ nOK, Multi-line string type
--STRING: Unbounded string type, for example, send AT + ATWMFT = 99 command, the contents of the response is: SUCC \ r \ nOK, this type refers to the SUCC
--SPECIAL: special type that needs special handling for AT commands such as CIPSEND, CIPCLOSE, CIFSR
local NORESULT,NUMBERIC,SLINE,MLINE,STRING,SPECIAL = 0,1,2,3,4,10

-- AT command response type table, preset the following items

local RILCMD = {
	["+CSQ"] = 2,
	["+CGSN"] = 1,
	["+WISN"] = 4,
	["+CIMI"] = 1,
	["+CCID"] = 1,
	["+CGATT"] = 2,
	["+CCLK"] = 2,
	["+ATWMFT"] = 4,
	["+CMGR"] = 3,
	["+CMGS"] = 2,
	["+CPBF"] = 3,
	["+CPBR"] = 3,
 	["+CIPSEND"] = 10,
	["+CIPCLOSE"] = 10,
	["+SSLINIT"] = 10,
	["+SSLCERT"] = 10,
	["+SSLCREATE"] = 10,
	["+SSLCONNECT"] = 10,
	["+SSLSEND"] = 10,
	["+SSLDESTROY"] = 10,
	["+SSLTERM"] = 10,
	["+CIFSR"] = 10,
}

--radioready: AT command channel is ready
--delaying: Before executing some AT commands, it needs to be delayed for a period of time before allowing these AT commands to be executed. This flag indicates whether the device is in a delaying state
local radioready,delaying = false

--AT command queue

local cmdqueue = {
	"ATE0",
	"AT+CMEE=0",
}
-- currently executing AT command, parameters, feedback callback, delayed execution time, command header, type, feedback format

local currcmd,currarg,currsp,curdelay,cmdhead,cmdtype,rspformt
-- Feedback results, intermediate information, result information

local result,interdata,respdata

--ril there will be three cases:
-- Send AT command, receive reply
-- Send AT command, command timeout not answered
-- The bottom of the initiative to report the notification software, hereinafter we are referred to as urc

--Function name: atimeout
--Function: send AT command, the command does not respond to the timeout processing
--Parameters: None
--Return Value: None

local function atimeout()
	-- Restart the software

	sys.restart("ril.atimeout_"..(currcmd or ""))
end

--Function name: defrsp
--Function: Default reply handling of AT command. If you do not define an AT response handler, you will come to this function
--Parameters:
--cmd: AT command corresponding to this reply
--success: AT command execution result, true or false
--response: string of the execution result in the AT command's response
--intermediate: intermediate information in the response of the AT command
--Return Value: None

local function defrsp(cmd,success,response,intermediate)
	print("default response:",cmd,success,response,intermediate)
end

--AT command response processing table

local rsptable = {}
setmetatable(rsptable,{__index = function() return defrsp end})

-- Custom AT command response format table, when the AT command response STRING format, the user can further define the format inside

local formtab = {}

--Function name: regrsp
--Function: Register the handler for an AT command reply
--Parameters:
--head: This response corresponds to the AT command header, removed the first two AT characters
--fnc: AT command response handler
--typ: Response type of the AT command, in the range of NORESULT, NUMBERIC, SLINE, MLINE, STRING, SPECIAL
--Formt: typ is STRING, further define the detailed format in STRING
--Return Value: Returns true if successful, false otherwise

function regrsp(head,fnc,typ,formt)
	-- No response type is defined

	if typ == nil then
		rsptable[head] = fnc
		return true
	end
	-- defines the legal response type

	if typ == 0 or typ == 1 or typ == 2 or typ == 3 or typ == 4 or typ == 10 then
		-- If the AT command's reply type already exists and is not consistent with the new setting

		if RILCMD[head] and RILCMD[head] ~= typ then
			return false
		end
		--save

		RILCMD[head] = typ
		rsptable[head] = fnc
		formtab[head] = formt
		return true
	else
		return false
	end
end

--Function name: rsp
--Function: AT command response processing
--Parameters: None
--Return Value: None

local function rsp()
	-- Stop the reply timeout timer

	sys.timer_stop(atimeout)
	-- If the AT command has been sent, the response handler has been specified

	if currsp then
		currsp(currcmd,result,respdata,interdata)
	-- The user registered response handler function table found in the handler

	else
		rsptable[cmdhead](currcmd,result,respdata,interdata)
	end
	-- Reset global variables

	currcmd,currarg,currsp,curdelay,cmdhead,cmdtype,rspformt = nil
	result,interdata,respdata = nil
end

--Function name: defurc
--Function: urc default processing. If you do not define a urc response handler, will come to this function
--Parameters:
--data: urc content
--Return Value: None

local function defurc(data)
	print("defurc:",data)
end

-- urc processing table

local urctable = {}
setmetatable(urctable,{__index = function() return defurc end})

--Function name: regurc
--Function: register a urc handler
--Parameters:
--prefix: urc prefix, the first continuous string, including +, uppercase characters, a combination of numbers
--handler: urc handler
--Return Value: None

function regurc(prefix,handler)
	urctable[prefix] = handler
end

--Function name: deregurc
--Function: Solution Register a urc handler
--Parameters:
--prefix: urc prefix, the first continuous string, including +, uppercase characters, a combination of numbers
--Return Value: None

function deregurc(prefix)
	urctable[prefix] = nil
end

-- "Data Filter", virtual serial port received data, you first need to call this function filter processing

local urcfilter

--Function name: urc
--Function: urc processing
--Parameters:
--data: urc data
--Return Value: None

local function urc(data)
	--AT channel is ready

	if data == "RDY" then
		radioready = true
	else
		local prefix = smatch(data,"(%+*[%u%d& ]+)")
		-- Executes the prefix's urc handler and returns the data filter

		urcfilter = urctable[prefix](data,prefix)
	end
end

--Function name: procatc
--Function: Processing the data received by the virtual serial port
--Parameters:
--data: data received
--Return Value: None

local function procatc(data)
	print("atc:",data)
	-- If the command's response is a multi-line string format

	if interdata and cmdtype == MLINE then
		-- OK \ r \ n does not appear, then the reply is considered not finished yet

		if data ~= "OK\r\n" then
			-- Remove the last \ r \ n

			if sfind(data,"\r\n",-2) then
				data = string.sub(data,1,-3)
			end
			-- Spliced to the middle data

			interdata = interdata .. "\r\n" .. data
			return
		end
	end
	-- If there is a "data filter"

	if urcfilter then
		data,urcfilter = urcfilter(data)
	end
	-- Remove the last \ r \ n

	if sfind(data,"\r\n",-2) then
		data = string.sub(data,1,-3)
	end
	-- data is empty

	if data == "" then
		return
	end
	-- Currently there are no orders in the implementation is judged as urc

	if currcmd == nil then
		urc(data)
		return
	end

	local isurc = false

	-- Some special error messages, converted to ERROR unified processing

	if sfind(data,"^%+CMS ERROR:") or sfind(data,"^%+CME ERROR:") or (data == "CONNECT FAIL" and currcmd and smatch(currcmd,"CIPSTART")) then
		data = "ERROR"
	end
	-- A successful response

	if data == "OK" or data == "SHUT OK" then
		result = true
		respdata = data
	-- Failed response

	elseif data == "ERROR" or data == "NO ANSWER" or data == "NO DIALTONE" then
		result = false
		respdata = data
	-- AT Command Response to continue parameter input

	elseif data == "> " then
		--send messages

		if cmdhead == "+CMGS" then
			print("send:",currarg)
			vwrite(uart.ATC,currarg,"\026")
		--send data

		elseif cmdhead == "+CIPSEND" or cmdhead == "+SSLSEND" or cmdhead == "+SSLCERT" then
			print("send:",currarg)
			vwrite(uart.ATC,currarg)
		else
			print("error promot cmd:",currcmd)
		end
	else
		-- No type

		if cmdtype == NORESULT then
			isurc = true
		-- All-digital type

		elseif cmdtype == NUMBERIC then
			local numstr = smatch(data,"(%x+)")
			if numstr == data then
				interdata = data
			else
				isurc = true
			end
		-- String type

		elseif cmdtype == STRING then
			-- further check the format

			if smatch(data,rspformt or "^%w+$") then
				interdata = data
			else
				isurc = true
			end
		elseif cmdtype == SLINE or cmdtype == MLINE then
			if interdata == nil and sfind(data, cmdhead) == 1 then
				interdata = data
			else
				isurc = true
			end
		-- special treatment

		elseif cmdhead == "+CIFSR" then
			local s = smatch(data,"%d+%.%d+%.%d+%.%d+")
			if s ~= nil then
				interdata = s
				result = true
			else
				isurc = true
			end
		-- special treatment

		elseif cmdhead == "+CIPSEND" or cmdhead == "+CIPCLOSE" then
			local keystr = cmdhead == "+CIPSEND" and "SEND" or "CLOSE"
			local lid,res = smatch(data,"(%d), *([%u%d :]+)")

			if lid and res then
				if (sfind(res,keystr) == 1 or sfind(res,"TCP ERROR") == 1 or sfind(res,"UDP ERROR") == 1 or sfind(data,"DATA ACCEPT")) and (lid == smatch(currcmd,"=(%d)")) then
					result = true
					respdata = data
				else
					isurc = true
				end
			elseif data == "+PDP: DEACT" then
				result = true
				respdata = data
			else
				isurc = true
			end
		elseif cmdhead=="+SSLINIT" or cmdhead=="+SSLCERT" or cmdhead=="+SSLCREATE" or cmdhead=="+SSLCONNECT" or cmdhead=="+SSLSEND" or cmdhead=="+SSLDESTROY" or cmdhead=="+SSLTERM" then
			if smatch(data,"^SSL&%d,") then
				respdata = data
				if smatch(data,"ERROR") then
					result = false
				else
					result = true
				end
			else
				isurc = true
			end
		else
			isurc = true
		end
	end
	-- urc processing

	if isurc then
		urc(data)
	-- Answer processing

	elseif result ~= nil then
		rsp()
	end
end

-- Whether to read the virtual serial port data

local readat = false

--Function name: getcmd
--Function: parse an AT command
--Parameters:
--item: AT command
--Return Value: The content of the current AT command

local function getcmd(item)
	local cmd,arg,rsp,delay
	-- The command is a string type

	if type(item) == "string" then
		-- command content

		cmd = item
	-- The command is a table type

	elseif type(item) == "table" then
		-- command content

		cmd = item.cmd
		-- Command parameters

		arg = item.arg
		-- Command response handler

		rsp = item.rsp
		-- Command delay execution time

		delay = item.delay
	else
		print("getpack unknown item")
		return
	end
	-- command prefix

	head = smatch(cmd,"AT([%+%*]*%u+)")

	if head == nil then
		print("request error cmd:",cmd)
		return
	end
	-- These two commands must have parameters

	if head == "+CMGS" or head == "+CIPSEND" then -- must have parameters

		if arg == nil or arg == "" then
			print("request error no arg",head)
			return
		end
	end

	-- Assign global variables

	currcmd = cmd
	currarg = arg
	currsp = rsp
	curdelay = delay
	cmdhead = head
	cmdtype = RILCMD[head] or NORESULT
	rspformt = formtab[head]

	return currcmd
end

--Function name: sendat
--Function: send AT command
--Parameters: None
--Return Value: None

local function sendat()
	--AT channel is not ready, is reading the virtual serial port data, there are no AT command execution or queue command, is sending an AT delay

	if not radioready or readat or currcmd ~= nil or delaying then		
		return
	end

	local item

	while true do
		-- Queue without AT command

		if #cmdqueue == 0 then
			return
		end
		-- read the first command

		item = table.remove(cmdqueue,1)
		-- parse the command

		getcmd(item)
		-- need to delay sending

		if curdelay then
			-- Start the delayed send timer

			sys.timer_start(delayfunc,curdelay)
			-- Clear global variables

			currcmd,currarg,currsp,curdelay,cmdhead,cmdtype,rspformt = nil
			item.delay = nil
			-- Set delay to send flag

			delaying = true
			-- Re-insert the command into the queue of the command queue

			table.insert(cmdqueue,1,item)
			return
		end

		if currcmd ~= nil then
			break
		end
	end
	-- Start the AT command reply timeout timer

	sys.timer_start(atimeout,TIMEOUT)

	print("sendat:",currcmd)
	-- Send AT command to the virtual serial port

	vwrite(uart.ATC,currcmd .. "\r")
end

--Function name: delayfunc
--Function: Delay the execution of an AT command timer callback
--Parameters: None
--Return Value: None

function delayfunc()
	-- Clear the delay flag

	delaying = nil
	-- Execute AT command to send

	sendat()
end

--Function name: atcreader
--Function: "AT command virtual serial port data receive message" processing function, when the virtual serial port receives the data, it will come to this function
--Parameters: None
--Return Value: None

local function atcreader()
	local s

	if not transparentmode then readat = true end
	-- Cyclic read the data received by the virtual serial port

	while true do
		-- read one line at a time

		s = vread(uart.ATC,"*l",0)
		if string.len(s) ~= 0 then
			if transparentmode then
				-- Forwarding data directly in transparent mode

				rcvfunc(s)
			else
				-- Processing received data in non-transparent mode

				procatc(s)
			end
		else
			break
		end
	end
	if not transparentmode then
		readat = false
		-- Continue to execute AT command after data processing finished

		sendat()
	end
end

-- Register the processing function of "AT Command virtual serial port data receive message"

sys.regmsg("atc",atcreader)

--Function name: request
--Function: send AT command to the underlying software
--Parameters:
--cmd: AT command content
--arg: AT command parameters, such as AT + CMGS = 12 command is executed, the next will send this parameter; AT + CIPSEND = 14 command is executed, the next will send this parameter
--onrsp: AT command response handler, but the current AT command response is valid, after processing fails
--delay: This command is sent only after delay of milliseconds
--Return Value: None

function request(cmd,arg,onrsp,delay)
	if transparentmode then return end
	-- Insert the buffer queue

	if arg or onrsp or delay or formt then
		table.insert(cmdqueue,{cmd = cmd,arg = arg,rsp = onrsp,delay = delay})
	else
		table.insert(cmdqueue,cmd)
	end
	-- Execute AT command to send

	sendat()
end

--Function name: setransparentmode
--Function: AT command channel is set to transparent mode
--Parameters:
--fnc: Transparent transmission mode, the virtual serial port data received processing function
--Return Value: None
--Note: transparent mode and non-transparent mode, only supports the first set of boot, does not support midway switch

function setransparentmode(fnc)
	transparentmode,rcvfunc = true,fnc
end

--Function name: sendtransparentdata
--Function: send data in transparent mode
--Parameters:
--data: data
--Return Value: Returns true if successful, nil if failed

function sendtransparentdata(data)
	if not transparentmode then return end
	vwrite(uart.ATC,data)
	return true
end
