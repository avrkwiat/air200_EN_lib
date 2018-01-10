--[[
Module Name: Program Framework
Module functions: initialization, program running framework, message distribution processing, timer interface
Last modified: 2017.02.17
]]

--Define module, import dependent libraries
require"patch"
local base = _G
local table = require"table"
local rtos = require"rtos"
local uart = require"uart"
local io = require"io"
local os = require"os"
local string = require"string"
module(...,package.seeall)

--Load common global functions to local
local print = base.print
local unpack = base.unpack
local ipairs = base.ipairs
local type = base.type
local pairs = base.pairs
local assert = base.assert
local tonumber = base.tonumber

--lib script version number, as long as any one of the lib script has been modified, you need to update this version number
SCRIPT_LIB_VER = "2.2.5"
--The latest core software version number when the script was released
CORE_MIN_VER = "Luat_V0020_Air200"

--Whether to allow the "script abnormal or script call sys.restart interface" restart, whether there is a pending event waiting to restart
local restartflg,restartpending = 0
--"whether you need to refresh the interface," the logo, a GUI project will use this logo
local refreshflag = false
--[[
Function name: refresh
Function: Set the interface refresh flag, GUI project will use this interface
Parameters: None
Return Value: None
]]
function refresh()
	refreshflag = true
end
--The maximum duration of single-step timer support, in milliseconds
local MAXMS = 0x7fffffff/17
--timer id
local uniquetid = 0
--Timer id table
local tpool = {}
--Timer parameter list
local para = {}
--whether the timer cycle table
local loop = {}
--lprfun: user-defined "low power shutdown handler"
--lpring: Whether to start the automatic shutdown timer
local lprfun,lpring
--Error message file and error message content
local LIB_ERR_FILE,liberr,extliberr = "/lib_err.txt",""
--Operating mode
--SIMPLE_MODE: simple mode, the default will not open the "generate an internal message every minute", "timing query csq", "timing query ceng" function
--FULL_MODE: full mode, the default will open the "generate an internal message every minute", "timing query csq", "timing query ceng" function
SIMPLE_MODE,FULL_MODE = 0,1
--The default is full mode
local workmode = FULL_MODE
--[[
Function name: timerfnc
Function: Handles the external timer message reported by the underlying core
Parameters:
tid: timer id
Return Value: None
]]
local function timerfnc(tid)
	--Timer id is valid
	if tpool[tid] ~= nil then
		--This timer's callback function
		local cb = tpool[tid]
		--Split into several timers if the length of time exceeds the maximum supported for one step
		if type(tpool[tid]) == "table" then
			local tval = tpool[tid]
			tval.times = tval.times+1
			--Split several timers have not been implemented, continue to the next one
			if tval.times < tval.total then
				rtos.timer_start(tid,tval.step)
				return
			end
			cb = tval.cb
		end
		--If not a recycle timer, clear the location of this timer id from the timer id table
		if not loop[tid] then tpool[tid] = nil end
		--There are custom variable parameters
		if para[tid] ~= nil then
			local pval = para[tid]
			--if not a recurring timer, clearing the location of this timer id from the timer parameter list
			if not loop[tid] then para[tid] = nil end
			--Executes the timer callback function
			cb(unpack(pval))
		--There are no custom variable parameters
		else
			--Executes the timer callback function
			cb()
		end
		--If the cycle timer, continue to start this timer
		if loop[tid] then rtos.timer_start(tid,loop[tid]) end
	end
end

--[[
Function name: comp_table
Function: compare the contents of the two tables are the same, note: the table can no longer contain the table
Parameters:
t1: the first table
t2: second table
Return value: the same return true, otherwise false
]]
local function comp_table(t1,t2)
	if not t2 then return #t1 == 0 end
	if #t1 == #t2 then
		for i=1,#t1 do
			if unpack(t1,i,i) ~= unpack(t2,i,i) then
				return false
			end
		end
		return true
	end
	return false
end
--[[
Function name: timer_start
Function: Turn on a timer
Parameters:
fnc: timer callback function
ms: timer duration in milliseconds
...: Custom variable parameters, call the callback function, the custom variable parameters will be passed back to the user
Note: fnc and variable parameters ... collectively mark the only timer
Return Value: ID of the timer, if failed nil
]]
function timer_start(fnc,ms,...)
	--The callback function and duration must be valid, otherwise the crash restarts
	assert(fnc~=nil,"timer_start:callback function==nil")
	assert(ms>0,"timer_start:ms==0")
	--Turn off exactly the same timer
	if arg.n == 0 then
		timer_stop(fnc)
	else
		timer_stop(fnc,unpack(arg))
	end
	--Split into several timers if the length of time exceeds the maximum supported for one step
	if ms > MAXMS then
		local count = ms/MAXMS + (ms%MAXMS == 0 and 0 or 1)
		local step = ms/count
		tval = {cb = fnc, step = step, total = count, times = 0}
		ms = step
	--The maximum duration of one-step support does not exceed
	else
		tval = fnc
	end
	--Find an unused id from the timer id table to use
	while true do
		uniquetid = uniquetid + 1
		if tpool[uniquetid] == nil then
			tpool[uniquetid] = tval
			break
		end
	end
	--Call the underlying interface to start the timer
	if rtos.timer_start(uniquetid,ms) ~= 1 then print("rtos.timer_start error") return end
	--If there is a variable parameter, save the parameter in the timer parameter list
	if arg.n ~= 0 then
		para[uniquetid] = arg
	end
	--return timer id
	return uniquetid
end
--[[
Function name: timer_loop_start
Function: Turn on a cycle timer
Parameters:
fnc: timer callback function
ms: timer duration in milliseconds
...: Custom variable parameters, call the callback function, the custom variable parameters will be passed back to the user
Note: fnc and variable parameters ... collectively mark the only timer
Return Value: ID of the timer, if failed nil
]]
function timer_loop_start(fnc,ms,...)
	local tid = timer_start(fnc,ms,unpack(arg))
	if tid then loop[tid] = ms end
	return tid
end
--[[
Function name: timer_stop
Function: Turn off a timer
Parameters:
val: There are two forms:
One is the timer id returned when the timer is turned on. This form does not need to pass in the variable parameter ... and can uniquely mark a timer
The other is the callback function when the timer is on, in which case you must pass variable arguments ... to uniquely mark a timer
...: Custom variable, same as variable in timer_start and timer_loop_start
Return Value: None
]]
function timer_stop(val,...)
	--val is the timer id
	if type(val) == "number" then
		tpool[val],para[val],loop[val] = nil
		rtos.timer_stop(val)
	else
		for k,v in pairs(tpool) do
			--The same callback function
			if type(v) == "table" and v.cb == val or v == val then
				--Custom variable parameters are the same
				if comp_table(arg,para[k])then
					rtos.timer_stop(k)
					tpool[k],para[k],loop[k] = nil
					break
				end
			end
		end
	end
end
--[[
Function name: timer_stop_all
Function: Turn off all the timers marked by a callback function, whether or not a custom variable is passed in when the timer is on
Parameters:
fnc: callback function when the timer is on
Return Value: None
]]
function timer_stop_all(fnc)
	for k,v in pairs(tpool) do
		if type(v) == "table" and v.cb == fnc or v == fnc then
			rtos.timer_stop(k)
			tpool[k],para[k],loop[k] = nil
		end
	end
end
--[[
Function name: timer_is_active
Function: to determine whether a timer is turned on
Parameters:
val: There are two forms:
One is the timer id returned when the timer is turned on. This form does not need to pass in the variable parameter ... and can uniquely mark a timer
The other is the callback function when the timer is on, in which case you must pass variable arguments ... to uniquely mark a timer
...: Custom variable, same as variable in timer_start and timer_loop_start
Return Value: open return true, otherwise false
]]
function timer_is_active(val,...)
	if type(val) == "number" then
		return tpool[val] ~= nil
	else
		for k,v in pairs(tpool) do
			if type(v) == "table" and v.cb == val or v == val then
				if comp_table(arg,para[k]) then
					return true
				end
			end
		end
		return false
	end
end
--[[
Function name: readtxt
Function: read the entire contents of the text file
Parameters:
f: file path
Return Value: The entire contents of the text file, read failed to empty string or nil
]]
local function readtxt(f)
	local file,rt = io.open(f,"r")
	if not file then print("sys.readtxt no open",f) return "" end
	rt = file:read("*a")
	file:close()
	return rt
end
--[[
Function name: writetxt
Function: Write a text file
Parameters:
f: file path
v: text content to be written
Return Value: None
]]
local function writetxt(f,v)
	local file = io.open(f,"w")
	if not file then print("sys.writetxt no open",f) return end	
	file:write(v)
	file:close()
end
--[[
Function name: appenderr
Function: Append error message to LIB_ERR_FILE file
Parameters:
s: error message, user-defined, usually string type, restart the trace will print out this error message
Return Value: None
]]
local function appenderr(s)
	print("appenderr",string.len(liberr),s)
	if string.len(liberr)<2048 then
		liberr = liberr..s
		writetxt(LIB_ERR_FILE,liberr)
	end	
end
--[[
Function name: initerr
Function: Print the error message in the LIB_ERR_FILE file
Parameters: None
Return Value: None
]]
local function initerr()
	extliberr = readtxt(LIB_ERR_FILE) or ""
	print("sys.initerr",extliberr)
	--Delete the LIB_ERR_FILE file
	os.remove(LIB_ERR_FILE)
end
--[[
Function name: getextliberr
Function: Get the error message in LIB_ERR_FILE file for external module
Parameters: None
Return Value: Error message in LIB_ERR_FILE file
]]
function getextliberr()
	return extliberr or (readtxt(LIB_ERR_FILE) or "")
end


local function saferestart(r)
	print("saferestart",r,restartflg)
	appenderr(r or "")
	if restartflg==0 then
		rtos.restart()
	else		
		restartpending = true
	end
end
--[[
Function name: restart
Function: Software reboot
Parameters:
r: reboot reasons, user-defined, usually string type, restart the trace will print out this restart reason
Return Value: None
]]
function restart(r)
	assert(r and r ~= "","sys.restart cause null")
	saferestart("restart["..r.."];")
end
--[[
Function name: getcorever
Function: Get the underlying software version number
Parameters: None
Return value: version number string
]]
function getcorever()
	return rtos.get_version()
end

--Function name: checkcorever
--Function: Check whether the underlying software version number and the minimum underlying software version number required by the lib script match
--Parameters: None
--Return Value: None

local function checkcorever()
	local realver = getcorever()
	--If you do not get the underlying software version number
	if not realver or realver=="" then
		appenderr("checkcorever[no core ver error];")
		return
	end
	
	local buildver = string.match(realver,"Luat_V(%d+)_Air200")
	--If the underlying software version number is in the wrong format
	if not buildver then
		appenderr("checkcorever[core ver format error]"..realver..";")
		return
	end
	
	--lib script needs the underlying software version number is greater than the actual version number of the underlying software
	if tonumber(string.match(CORE_MIN_VER,"Luat_V(%d+)_Air200"))>tonumber(buildver) then
		print("checkcorever[core ver match warn]"..realver..","..CORE_MIN_VER..";")
	end
end


--Function name: init
--Function: lua application initialization
--Parameters:
--mode: Whether charging starts GSM protocol stack, 1 does not start, or start
--lprfnc: "low power shutdown handler" as defined in the user application script. If there is a function name, the run interface in this file will not perform any action at low power. Otherwise, it will delay for 1 minute and automatically shut down
--Return Value: None

function init(mode,lprfnc)
	--The user application script must define PROJECT and VERSION two global variables, otherwise it will crash reboot, how to define please refer to the main.lua
	assert(base.PROJECT and base.PROJECT ~= "" and base.VERSION and base.VERSION ~= "","Undefine PROJECT or VERSION")
	base.collectgarbage("setpause",80)
	require"net"
	--Set the AT command virtual serial port
	uart.setup(uart.ATC,0,0,uart.PAR_NONE,uart.STOP_1)
	print("poweron reason:",rtos.poweron_reason(),base.PROJECT,base.VERSION,SCRIPT_LIB_VER,getcorever())
	if mode == 1 then
		--Charging the boot
		if rtos.poweron_reason() == rtos.POWERON_CHARGER then
			--Close GSM protocol stack
			rtos.poweron(0)
		end
	end
	--If there is a script to run the error file, open the file and print the error message
	local f = io.open("/luaerrinfo.txt","r")
	if f then
		print(f:read("*a") or "")
		f:close()
	end
	--Save the user's application script defined in the "low power shutdown handler"
	lprfun = lprfnc
	initerr()
	checkcorever()
end

--Function name: poweron
--Function: Start GSM protocol stack. For example, if the user does not activate the GSM protocol stack when the power is turned on, if the user presses a key for a long time, the interface is started to activate the GSM protocol stack
--Parameters: None
--Return Value: None

function poweron()
	rtos.poweron(1)
end
--[[
Function name: setworkmode
Function: Set the working mode
Parameters:
v: work mode
Returns: successful return true, otherwise return nil
]]
function setworkmode(v)
	if workmode~=v and (v==SIMPLE_MODE or v==FULL_MODE) then
		workmode = v
		--Generate a working mode change in the internal message "SYS_WORKMODE_IND"
		dispatch("SYS_WORKMODE_IND")
		return true
	end
end
--[[
Function name: getworkmode
Function: Get working mode
Parameters: None
Return Value: The current working mode
]]
function getworkmode()
	return workmode
end

--Function name: opntrace
--Function: Enable or disable the print output function of print
--Parameters:
--v: false or nil is off, the rest is on
--uartid: Output Luatrace port: nil said the host port, 1 said uart1, 2 said uart2
--baudrate: number type, uartid is not nil, this parameter makes sense, that the baud rate, the default 115200
--Only support 1200,2400,4800,9600,14400,19200,28800,38400,57600,76800,115200,230400,460800,576000,921600,1152000,4000000
--Return Value: None

function opntrace(v,uartid,baudrate)
	if uartid then
		if v then
			uart.setup(uartid,baudrate or 115200,8,uart.PAR_NONE,uart.STOP_1)
		else
			uart.close(uartid)
		end
	end
	rtos.set_trace(v and 1 or 0,uartid)
end

--app storage table
local apps = {}
--[[
Function name: regapp
Function: Register app
Parameters: variable parameters, app parameters, in the following two forms:
Functionally registered apps such as regapp (fncname, "MSG1", "MSG2", "MSG3")
Table registered app, such as regapp ({MSG1 = fnc1, MSG2 = fnc2, MSG3 = fnc3})
Return Value: None
]]
function regapp(...)
	local app = arg[1]
	--table way
	if type(app) == "table" then
	--Function method
	elseif type(app) == "function" then
		app = {procer = arg[1],unpack(arg,2,arg.n)}
	else
		error("unknown app type "..type(app),2)
	end
	--Generate an internal message to increase the app
	dispatch("SYS_ADD_APP",app)
	return app
end
--[[
Function name: deregapp
Function: Solution registration app
Parameters:
id: app id, id There are two ways, one is the function name, the other is the table name
Return Value: None
]]
function deregapp(id)
	--Generate an internal message to remove the app
	dispatch("SYS_REMOVE_APP",id)
end

--Function name: addapp
--Function: increase app
--Parameters:
--app: an app, in the following two forms:
--If it is a functionally registered app such as regapp (fncname, "MSG1", "MSG2", "MSG3"), the form is: {procer = arg [1], "MSG1", "MSG2", "MSG3" }
--For example, regapp ({MSG1 = fnc1, MSG2 = fnc2, MSG3 = fnc3}) is an app registered in a table format of {MSG1 = fnc1, MSG2 = fnc2, MSG3 = fnc3}
--Return Value: None

local function addapp(app)
	--Insert the tail
	table.insert(apps,#apps+1,app)
end
--[[
Function name: removeapp
Function: Remove app
Parameters:
id: app id, id There are two ways, one is the function name, the other is the table name
Return Value: None
]]
local function removeapp(id)
	--Traverse app table
	for k,v in ipairs(apps) do
		--app id if it is a function name
		if type(id) == "function" then
			if v.procer == id then
				table.remove(apps,k)
				return
			end
		--app id if the table name
		elseif v == id then
			table.remove(apps,k)
			return
		end
	end
end
--[[
Function name: callapp
Function: Process internal messages
By traversing each app for processing
Parameters:
msg: message
Return Value: None
]]
local function callapp(msg)
	local id = msg[1]
	--Add app message
	if id == "SYS_ADD_APP" then
		addapp(unpack(msg,2,#msg))
	--Remove app message
	elseif id == "SYS_REMOVE_APP" then
		removeapp(unpack(msg,2,#msg))
	else
		local app
		--Traverse app table
		for i=#apps,1,-1 do
			app = apps[i]
			--function registration method app, with the message id notification
			if app.procer then 
				for _,v in ipairs(app) do
					if v == id then
						--If the message's handler does not return true, then the life of the message is over; otherwise, it is traversing the app
						if app.procer(unpack(msg)) ~= true then
							return
						end
					end
				end
			--table registration app, without the message id notification
			elseif app[id] then 
				--If the message's handler does not return true, then the life of the message is over; otherwise, it is traversing the app
				if app[id](unpack(msg,2,#msg)) ~= true then
					return
				end
			end
		end
	end
end

--Internal message queue
local qmsg = {}
--[[
Function name: dispatch
Function: Generate internal messages, stored in the internal message queue
Parameters: variable parameters, user-defined
Return Value: None
]]
function dispatch(...)
	table.insert(qmsg,arg)
end
--[[
Function name: getmsg
Function: read internal message
Parameters: None
Return Value: The first message in the internal message queue, returns nil if it does not exist
]]
local function getmsg()
	if #qmsg == 0 then
		return nil
	end

	return table.remove(qmsg,1)
end

--Interface refresh internal message
local refreshmsg = {"MMI_REFRESH_IND"}

--[[
Function name: runqmsg
Function: Process internal messages
Parameters: None
Return Value: None
]]
local function runqmsg()
	local inmsg

	while true do
		--read internal messages
		inmsg = getmsg()
		--Internal message is empty
		if inmsg == nil then
			--need to refresh the interface
			if refreshflag == true then
				refreshflag = false
				--Generate an interface to refresh internal messages
				inmsg = refreshmsg
			else
				break
			end
		end
		--Process internal messages
		callapp(inmsg)
	end
end

--a handler function table of "other external messages other than a timer message, a physical serial port message (for example, a virtual serial port data reception message, an audio message, a charging management message, a key press message, etc. of an AT command)
local handlers = {}
base.setmetatable(handlers,{__index = function() return function() end end,})


--Function name: regmsg
--Function: Register the processing function of "external serial port messages other than the timer message or physical serial port message (such as the AT command virtual serial port data receive message, audio message, charging management message, key message, etc.)
--Parameters:
--id: message type id
--fnc: message processing function
--Return Value: None

function regmsg(id,handler)
	handlers[id] = handler
end

--Each physical serial port data reception function table
local uartprocs = {}

--Each physical serial port to send data to complete the notification function table

local uartxprocs = {}

--Function name: reguart
--Function: Register the physical serial port data receive and process function
--Parameters:
--id: Physical serial port number, 1 for UART1 and 2 for UART2
--fnc: data receive processing function name
--Return Value: None

function reguart(id,fnc)
	uartprocs[id] = fnc
end


--Function name: reguartx
--Function: register the physical serial port to send the data to complete the processing function
--Parameters:
--id: Physical serial port number, 1 for UART1 and 2 for UART2
--fnc: call uart.write interface to send data, the data is sent after the callback function
--Return Value: None

function reguartx(id,fnc)
	uartxprocs[id] = fnc
end

--Function name: setrestart (Warning: This interface only allows update.lua and dbg.lua calls, do not use it elsewhere)
--Function: Set whether to allow "reboot function when script abnormal or script calls sys.restart interface"
--Parameters:
--flg: true allows restart, the rest does not allow restart
--tag: 1 or 2,1 means update, 2 means dbg
--Return Value: None

function setrestart(flg,tag)
	if flg then
		if bit.band(restartflg,tag)~=0 then restartflg = restartflg-tag end
	else
		if bit.band(restartflg,tag)==0 then restartflg = restartflg+tag end
	end
	if flg and restartflg==0 and restartpending then restart("restartpending") end
end

local msg,msgpara
local function saferun()
	--while true do
		--Process internal messages
		runqmsg()
		--Obstruction to read external messages
		msg,msgpara = rtos.receive(rtos.INF_TIMEOUT)

		--0% battery power, no "low power shutdown handler" is defined in the user application script, and no automatic shutdown timer is activated
		if --[[not lprfun and ]]not lpring and type(msg) == "table" and msg.id == rtos.MSG_PMD and msg.level == 0 then
			--Start the automatic shutdown timer, shut down after 60 seconds
			lpring = true
			timer_start(rtos.poweroff,60000,"r1")
		end

		--The external message is table type
		if type(msg) == "table" then
			--Timer type message
			if msg.id == rtos.MSG_TIMER then
				timerfnc(msg.timer_id)
			--AT Command virtual serial port data receive message
			elseif msg.id == rtos.MSG_UART_RXDATA and msg.uart_id == uart.ATC then
				handlers.atc()
			else
				--Physical serial port data receive message
				if msg.id == rtos.MSG_UART_RXDATA then
					if uartprocs[msg.uart_id] ~= nil then
						uartprocs[msg.uart_id]()
					else
						handlers[msg.id](msg)
					end
				--Serial port to send data to complete the message
				elseif msg.id == rtos.MSG_UART_TX_DONE then
					if uartxprocs[msgpara] then
						uartxprocs[msgpara]()				
					end
				--Other messages (audio messages, charge management messages, key messages, etc.)
				else
					handlers[msg.id](msg)
				end
			end
		--External message is not a table type
		else
			--Timer type message
			if msg == rtos.MSG_TIMER then
				timerfnc(msgpara)
			--Serial data receive message
			elseif msg == rtos.MSG_UART_RXDATA then
				--AT command virtual serial port
				if msgpara == uart.ATC then
					handlers.atc()
				--physical serial port
				else
					if uartprocs[msgpara] ~= nil then
						uartprocs[msgpara]()
					else
						handlers[msg](msg,msgpara)
					end
				end
			--Serial port to send data to complete the message
			elseif msg == rtos.MSG_UART_TX_DONE then
				if uartxprocs[msgpara] then
					uartxprocs[msgpara]()				
				end
			end
		end
		--Print lua script program memory, the unit is K bytes
		--print("mem:",base.collectgarbage("count"))
	--end
end

--Function name: run
--Function: Lua application framework for the operation of the entrance
--Parameters: None
--Return Value: None

--Operating framework based on the message processing mechanism, a total of two kinds of news: internal information and external information
--Internal Messages: The lua script calls the message generated by the dispatch interface for this file, which is stored in the qmsg table
--External messages: messages generated by the underlying core software, the lua script reads these external messages via the rtos.receive interface

function run()
	local status,err
	while true do
		status,err = pcall(saferun)
		--Operation error
		if not status then
			print("run",status,err)
			saferestart(err or "")			
		end
	end
end
