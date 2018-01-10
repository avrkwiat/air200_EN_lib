
--Module Name: Data Link, SOCKET Management
--Module Function: Data Network Activation, SOCKET Creation, Connection, Data Transmission and Reception, Status Maintenance
--Last modified on: 2017.02.14

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local table = require"table"
local sys = require"sys"
local ril = require"ril"
local net = require"net"
local rtos = require"rtos"
local sim = require"sim"
module(...,package.seeall)

-- Load common global functions to local

local print = base.print
local pairs = base.pairs
local tonumber = base.tonumber
local tostring = base.tostring
local req = ril.request

-- The maximum socket id, starting from 0, so at the same time support the socket connection is 8

local MAXLINKS = 7
-- IP environment establishment failure reconnection 5 seconds later

local IPSTART_INTVL = 5000

--socket connection table

local linklist = {}
--ipstatus: IP environment status
--shuting: Whether the data network is being shut down
local ipstatus,shuting = "IP INITIAL"
-- GPRS data network attachment status, "1" attached, the rest are not attached

local cgatt
--apn, username, password

local apnname = "CMNET"
local username=''
local password=''
--socket After initiating the connection request, if there is no reply after msn connecttinterval milliseconds, restart if the connectnoretrestart is true

local connectnoretrestart = false
local connectnoretinterval
--apnflg: This function module automatically get apn information, true is false, the user application script itself calls the setapn interface to set apn, username and password
--checkciicrtm: execute AT + CIICR, if you set checkciicrtm, checkciicrtm ms, no activation is successful, then restart the software (half-way implementation of AT + CIPSHUT is no longer restart)
--flymode: Whether it is in flight mode
--updating: whether to perform remote upgrade (update.lua)
--dbging: Whether dbg functions are being executed (dbg.lua)
--ntping: Whether to perform NTP time synchronization (ntp.lua)
--shutpending: Is there any pending AT + CIPSHUT request?
local apnflag,checkciicrtm,ciicrerrcb,flymode,updating,dbging,ntping,shutpending=true

--Function name: setapn
--Function: Set apn, user name and password
--Parameters:
--a: apn
--b: user name
--c: password
--Return Value: None

function setapn(a,b,c)
	apnname,username,password = a,b or '',c or ''
	apnflag=false
end

--Function name: getapn
--Function: Get apn
--Parameters: None
--Return value: apn

function getapn()
	return apnname
end

--Function name: connectingtimerfunc
--Function: Socket connection timeout no response handler
--Parameters:
--id: socket id
--Return Value: None

local function connectingtimerfunc(id)
	print("connectingtimerfunc",id,connectnoretrestart)
	if connectnoretrestart then
		sys.restart("link.connectingtimerfunc")
	end
end

--Function name: stopconnectingtimer
--Function: Turn off "socket connection timeout did not answer" timer
--Parameters:
--id: socket id
--Return Value: None

local function stopconnectingtimer(id)
	print("stopconnectingtimer",id)
	sys.timer_stop(connectingtimerfunc,id)
end

--Function name: startconnectingtimer
--Function: Enable "socket connection timeout did not answer" timer
--Parameters:
--id: socket id
--Return Value: None

local function startconnectingtimer(id)
	print("startconnectingtimer",id,connectnoretrestart,connectnoretinterval)
	if id and connectnoretrestart and connectnoretinterval and connectnoretinterval > 0 then
		sys.timer_start(connectingtimerfunc,connectnoretinterval,id)
	end
end

--Function name: setconnectnoretrestart
--Function: Set the control parameters of "socket connection timeout does not answer"
--Parameters:
--flag: function switch, true or false
--interval: Timeout in milliseconds
--Return Value: None

function setconnectnoretrestart(flag,interval)
	connectnoretrestart = flag
	connectnoretinterval = interval
end

--Function name: setupIP
--Function: Send activate IP network request
--Parameters: None
--Return Value: None

function setupIP()
	print("link.setupIP:",ipstatus,cgatt,flymode)
	-- The data network is active or in flight mode, returning directly

	if ipstatus ~= "IP INITIAL" or flymode then
		return
	end
	--gprs data network is not attached

	if cgatt ~= "1" then
		print("setupip: wait cgatt")
		return
	end

	-- Activate IP network request

	req("AT+CSTT=\""..apnname..'\",\"'..username..'\",\"'..password.. "\"")
	req("AT+CIICR")
	-- Check the activation status

	req("AT+CIPSTATUS")
	ipstatus = "IP START"
end

--Function name: emptylink
--Function: Get available socket id
--Parameters: None
--Return Value: Available socket id, return nil if not available

local function emptylink()
	for i = 0,MAXLINKS do
		if linklist[i] == nil then
			return i
		end
	end

	return nil
end

--Function name: validaction
--Function: Check a socket id action is valid
--Parameters:
--id: socket id
--action: action
--Return Value: true is valid, false is invalid

local function validaction(id,action)
	--socket invalid

	if linklist[id] == nil then
		print("link.validaction:id nil",id)
		return false
	end

	-- The same state is not repeated

	if action.."ING" == linklist[id].state then
		print("link.validaction:",action,linklist[id].state)
		return false
	end

	local ing = string.match(linklist[id].state,"(ING)",-3)

	if ing then
		-- There are other tasks in the handling, not allowed to deal with the connection, broken chain or closed is possible
		if action == "CONNECT" then
			print("link.validaction: action running",linklist[id].state,action)
			return false
		end
	end

	-- No other tasks in the implementation, to allow execution

	return true
end

--Function name: openid
--Function: Save socket parameter information
--Parameters:
--id: socket id
--notify: socket state handler
--recv: socket data reception and processing functions
--tag: socket Create a tag
--Return Value: true successful, false failed

function openid(id,notify,recv,tag)
	--id Out of bounds or id socket already exists

	if id > MAXLINKS or linklist[id] ~= nil then
		print("openid:error",id)
		return false
	end

	local link = {
		notify = notify,
		recv = recv,
		state = "INITIAL",
		tag = tag,
	}

	linklist[id] = link

	-- Register to connect urc

	ril.regurc(tostring(id),urc)

	-- Activate IP network

	if ipstatus ~= "IP STATUS" and ipstatus ~= "IP PROCESSING" then
		setupIP()
	end

	return true
end

--Function name: open
--Function: Create a socket
--Parameters:
--notify: socket state handler
--recv: socket data reception and processing functions
--tag: socket Create a tag
--Return value: Id of number type indicates success, nil indicates failure

function open(notify,recv,tag)
	local id = emptylink()

	if id == nil then
		return nil,"no empty link"
	end

	openid(id,notify,recv,tag)

	return id
end

--Function name: close
--Function: Close a socket (socket will clear all the parameters of information)
--Parameters:
--id: socket id
--Return Value: true successful, false failed

function close(id)
	-- Check if it is allowed to close

	if validaction(id,"CLOSE") == false then
		return false
	end
	-- closing

	linklist[id].state = "CLOSING"
	-- Send AT command to close the request

	req("AT+CIPCLOSE="..id)

	return true
end

--Function name: asyncLocalEvent
--Function: socket asynchronous notification message handler
--Parameters:
--msg: Asynchronous Notification Message "LINK_ASYNC_LOCAL_EVENT"
--cbfunc: message callback
--id: socket id
--val: parameters of the notification message
--Return Value: true successful, false failed

function asyncLocalEvent(msg,cbfunc,id,val)
	cbfunc(id,val)
end

-- Registration message handler for LINK_ASYNC_LOCAL_EVENT

sys.regapp(asyncLocalEvent,"LINK_ASYNC_LOCAL_EVENT")

--Function name: connect
--Function: socket connection server request
--Parameters:
--id: socket id
--protocol: transport layer protocol, TCP or UDP
--address: server address
--port: server port
--Return Value: The request successfully synchronized to return true, otherwise false;

function connect(id,protocol,address,port)
	-- Not allowed to initiate connection action

	if validaction(id,"CONNECT") == false or linklist[id].state == "CONNECTED" then
		return false
	end
	print("link.connect",id,protocol,address,port,ipstatus,shuting,shutpending)

	linklist[id].state = "CONNECTING"

	if cc and cc.anycallexist() then
		-- If the call feature is turned on and the call is currently being used asynchronously, the connection fails

		print("link.connect:failed cause call exist")
		sys.dispatch("LINK_ASYNC_LOCAL_EVENT",statusind,id,"CONNECT FAIL")
		return true
	end

	local connstr = string.format("AT+CIPSTART=%d,\"%s\",\"%s\",%s",id,protocol,address,port)

	if (ipstatus ~= "IP STATUS" and ipstatus ~= "IP PROCESSING") or shuting or shutpending then
		--ip environment is not ready to join the wait

		linklist[id].pending = connstr
	else
		-- Send AT command to connect to the server

		req(connstr)
		startconnectingtimer(id)
	end

	return true
end

--Function name: disconnect
--Function: Disconnect a socket (does not clear all the socket parameter information)
--Parameters:
--id: socket id
--Return Value: true successful, false failed

function disconnect(id)
	-- Disconnection is not allowed

	if validaction(id,"DISCONNECT") == false then
		return false
	end
	-- If the socket id corresponding connection is still waiting, and did not really launch

	if linklist[id].pending then
		linklist[id].pending = nil
		if ipstatus ~= "IP STATUS" and ipstatus ~= "IP PROCESSING" and linklist[id].state == "CONNECTING" then
			print("link.disconnect: ip not ready",ipstatus)
			linklist[id].state = "DISCONNECTING"
			sys.dispatch("LINK_ASYNC_LOCAL_EVENT",closecnf,id,"DISCONNECT","OK")
			return
		end
	end

	linklist[id].state = "DISCONNECTING"
	-- Send AT command to disconnect

	req("AT+CIPCLOSE="..id)

	return true
end

--Function name: send
--Function: send data to the server
--Parameters:
--id: socket id
--data: data to send
--Return Value: true successful, false failed

function send(id,data)
	--socket invalid, or socket is not connected

	if linklist[id] == nil or linklist[id].state ~= "CONNECTED" then
		print("link.send:error",id)
		return false
	end

	if cc and cc.anycallexist() then
		-- If the call feature is turned on and the call is currently being used asynchronously, the connection fails

		print("link.send:failed cause call exist")
		return false
	end
	-- Send AT command to send data

	req(string.format("AT+CIPSEND=%d,%d",id,string.len(data)),data)

	return true
end

--Function name: getstate
--Function: Get a socket connection status
--Parameters:
--id: socket id
--Return Value: Socket is valid to return the connection status, otherwise return "NIL LINK"

function getstate(id)
	return linklist[id] and linklist[id].state or "NIL LINK"
end

--Function name: recv
--Function: a socket data reception and processing functions
--Parameters:
--id: socket id
--len: received data length, in bytes
--data: The data content received
--Return Value: None

local function recv(id,len,data)
	--socket id is invalid

	if linklist[id] == nil then
		print("link.recv:error",id)
		return
	end
	-- Call socket id corresponding to the user registration data reception processing functions

	if linklist[id].recv then
		linklist[id].recv(id,data)
	else
		print("link.recv:nil recv",id)
	end
end

--[[ipstatus query status returned does not suggest
function linkstatus (data)
end
]]

--Function name: usersckisactive
--Function: to determine whether the user-created socket connection is active
--Parameters: None
--Return Value: Returns true as long as any user socket is connected, otherwise it returns nil

local function usersckisactive()
	for i = 0,MAXLINKS do
		-- User-defined socket, no tag value

		if linklist[i] and not linklist[i].tag and linklist[i].state=="CONNECTED" then
			return true
		end
	end
end

--Function name: usersckntfy
--Function: User-created socket connection status change notification
--Parameters:
--id: socket id
--Return Value: None

local function usersckntfy(id)
	-- Generates an internal message "USER_SOCKET_CONNECT" informing "User-created socket connection status has changed"

	if not linklist[id].tag then sys.dispatch("USER_SOCKET_CONNECT",usersckisactive()) end
end

--Function name: sendcnf
--Function: Socket data transmission results confirmed
--Parameters:
--id: socket id
--result: send the result string
--Return Value: None

local function sendcnf(id,result)
	local str = string.match(result,"([%u ])")
	--Failed to send

	if str == "TCP ERROR" or str == "UDP ERROR" or str == "ERROR" then
		linklist[id].state = result
	end
	-- Call user registration status handler

	linklist[id].notify(id,"SEND",result)
end

--Function name: closecnf
--Function: socket close the results confirmed
--Parameters:
--id: socket id
--result: closes the result string
--Return Value: None

function closecnf(id,result)
	--socket id is invalid

	if not id or not linklist[id] then
		print("link.closecnf:error",id)
		return
	end
	-- No matter what the close result, the link is always disconnected successfully, so the link is disconnected

	if linklist[id].state == "DISCONNECTING" then
		linklist[id].state = "CLOSED"
		linklist[id].notify(id,"DISCONNECT","OK")
		usersckntfy(id,false)
		stopconnectingtimer(id)
	-- Connection logout, clear the maintenance of the connection information, clear urc attention

	elseif linklist[id].state == "CLOSING" then		
		local tlink = linklist[id]
		usersckntfy(id,false)
		linklist[id] = nil
		ril.deregurc(tostring(id),urc)
		tlink.notify(id,"CLOSE","OK")		
		stopconnectingtimer(id)
	else
		print("link.closecnf:error",linklist[id].state)
	end
end

--Function name: statusind
--Function: Socket state conversion processing
--Parameters:
--id: socket id
--state: status string
--Return Value: None

function statusind(id,state)
	--socket invalid

	if linklist[id] == nil then
		print("link.statusind:nil id",id)
		return
	end

	-- In express mode, data transmission failed

	if state == "SEND FAIL" then
		if linklist[id].state == "CONNECTED" then
			linklist[id].notify(id,"SEND",state)
		else
			print("statusind:send fail state",linklist[id].state)
		end
		return
	end

	local evt
	--socket if it is in the connected state, or returned a status notification that the connection was successful

	if linklist[id].state == "CONNECTING" or state == "CONNECT OK" then
		-- Connection type event

		evt = "CONNECT"		
	else
		-- Status type of event

		evt = "STATE"
	end

	-- Unless the connection is successful, the connection is still closed

	if state == "CONNECT OK" then
		linklist[id].state = "CONNECTED"		
	else
		linklist[id].state = "CLOSED"
	end
	-- Call usersckntfy to determine if it needs to notify "User socket connection status has changed"

	usersckntfy(id,state == "CONNECT OK")
	-- Call user registration status handler

	linklist[id].notify(id,evt,state)
	stopconnectingtimer(id)
end

--Function name: connpend
--Function: Performs socket connection requests that are suspended because the IP network is not ready
--Parameters: None
--Return Value: None

local function connpend()
	for i = 0,MAXLINKS do
		if linklist[i] ~= nil then
			if linklist[i].pending then
				req(linklist[i].pending)
				local id = string.match(linklist[i].pending,"AT%+CIPSTART=(%d)")
				if id then
					startconnectingtimer(tonumber(id))
				end
				linklist[i].pending = nil
			end
		end
	end	
end

local ipstatusind
function regipstatusind()
	ipstatusind = true
end

local function ciicrerrtmfnc()
	print("ciicrerrtmfnc")
	if ciicrerrcb then
		ciicrerrcb()
	else
		sys.restart("ciicrerrtmfnc")
	end
end

--Function name: setIPStatus
--Function: Set the IP network status
--Parameters:
--status: IP network status
--Return Value: None

local function setIPStatus(status)
	print("ipstatus:",status)
	
	if ipstatusind and ipstatus~=status then
		sys.dispatch("IP_STATUS_IND",status=="IP GPRSACT" or status=="IP PROCESSING" or status=="IP STATUS")
	end
	
	if not sim.getstatus() then
		status = "IP INITIAL"
	end

	if ipstatus ~= status or status=="IP START" or status == "IP CONFIG" or status == "IP GPRSACT" or status == "PDP DEACT" then
		if status=="IP GPRSACT" and checkciicrtm then
			-- The IP network timeout timer has not been activated successfully after "AT + CIICR" is disabled

			print("ciicrerrtmfnc stop")
			sys.timer_stop(ciicrerrtmfnc)
		end
		ipstatus = status
		if ipstatus == "IP PROCESSING" then
		--IP network is ready

		elseif ipstatus == "IP STATUS" then
			-- Performs a pending socket connection request

			connpend()
		--IP network is closed

		elseif ipstatus == "IP INITIAL" then
			--IPSTART_INTVLRemove the IP network after a few milliseconds

			sys.timer_start(setupIP,IPSTART_INTVL)
		-- IP network is active

		elseif ipstatus == "IP CONFIG" or ipstatus == "IP START" then
			-- 2 seconds to check the IP network status

			sys.timer_start(req,2000,"AT+CIPSTATUS")
		-- IP network activated successfully

		elseif ipstatus == "IP GPRSACT" then
			-- Get IP address, IP address is successfully obtained, the IP network status will switch to "IP STATUS"

			req("AT+CIFSR")
			-- Check the IP network status

			req("AT+CIPSTATUS")
		else -- Other abnormal states close to IP INITIAL

			shut()
			sys.timer_stop(req,"AT+CIPSTATUS")
		end
	end
end

--Function name: shutcnf
--Function: Turn off IP network result processing
--Parameters:
--result: closes the result string
--Return Value: None

local function shutcnf(result)
	shuting = false
	if ipstatusind then sys.dispatch("IP_SHUTING_IND",false) end
	-- closed successfully

	if result == "SHUT OK" or not sim.getstatus() then
		setIPStatus("IP INITIAL")
		-- Disconnect all socket connections without clearing socket parameter information

		for i = 0,MAXLINKS do
			if linklist[i] then
				if linklist[i].state == "CONNECTING" and linklist[i].pending then
					-- Do not prompt for the connection request has not been done close, IP environment is established automatically connected

				elseif linklist[i].state == "INITIAL" then -- Not connected nor prompted

				else
					linklist[i].state = "CLOSED"
					linklist[i].notify(i,"STATE","SHUTED")
					usersckntfy(i,false)
				end
				stopconnectingtimer(i)
			end
		end
	else
		--req("AT+CIPSTATUS")
		sys.timer_start(req,10000,"AT+CIPSTATUS")
	end
	if checkciicrtm and result=="SHUT OK" and not ciicrerrcb then
		-- The IP network timeout timer has not been activated successfully after "AT + CIICR" is disabled

		print("ciicrerrtmfnc stop")
		sys.timer_stop(ciicrerrtmfnc)
	end
end

--local function reconnip(force)
--	print("link.reconnip",force,ipstatus,cgatt)
--	if force then
--		setIPStatus("PDP DEACT")
--	else
--		if ipstatus == "IP START" or ipstatus == "IP CONFIG" or ipstatus == "IP GPRSACT" or ipstatus == "IP STATUS" or ipstatus == "IP PROCESSING" then
--			setIPStatus("PDP DEACT")
--		end
--		cgatt = "0"
--	end
--end


-- Maintain a "socket received data from a server" received from the AT channel
--id: socket id
--len: The total length of data received this time
--data: data content that has been received
local rcvd = {id = 0,len = 0,data = ""}

--Function name: rcvdfilter
--Function: Receive a packet of data from the AT channel
--Parameters:
--data: Data parsed
--Return Value: Two return values, the first return value represents the unprocessed data and the second return value represents the data filter function of the AT channel

local function rcvdfilter(data)
	-- If the total length is 0, this function does not process the data received, return directly

	if rcvd.len == 0 then
		return data
	end
	-- The remaining data length is not received

	local restlen = rcvd.len - string.len(rcvd.data)
	if  string.len(data) > restlen then -- The content of the at channel is more than the remaining data that has not been received

		-- Intercept the data sent from the network

		rcvd.data = rcvd.data .. string.sub(data,1,restlen)
		-- The rest of the data is still at the follow-up treatment

		data = string.sub(data,restlen+1,-1)
	else
		rcvd.data = rcvd.data .. data
		data = ""
	end

	if rcvd.len == string.len(rcvd.data) then
		-- Notify receiving data

		recv(rcvd.id,rcvd.len,rcvd.data)
		rcvd.id = 0
		rcvd.len = 0
		rcvd.data = ""
		return data
	else
		return data, rcvdfilter
	end
end

--Function name: urc
--Function: The function of "registered core layer through the virtual serial port initiative to report the notification" of the processing
--Parameters:
--data: The complete string information for the notification
--prefix: The prefix of the notification
--Return Value: None

function urc(data,prefix)
	--IP network status notification

	if prefix == "STATE" then
		setIPStatus(string.sub(data,8,-1))
	elseif prefix == "C" then
		--linkstatus(data)
	--IP network passive to activate

	elseif prefix == "+PDP" then
		--req("AT+CIPSTATUS")
		shut()
		sys.timer_stop(req,"AT+CIPSTATUS")
	--socket received the data sent by the server

	elseif prefix == "+RECEIVE" then
		local lid,len = string.match(data,",(%d),(%d+)",string.len("+RECEIVE")+1)
		rcvd.id = tonumber(lid)
		rcvd.len = tonumber(len)
		return rcvdfilter
	--socket status notification

	else
		local lid,lstate = string.match(data,"(%d), *([%u :%d]+)")

		if lid then
			lid = tonumber(lid)
			statusind(lid,lstate)
		end
	end
end

--Function name: shut
--Function: Turn off the IP network
--Parameters: None
--Return Value: None

function shut()
	-- Delay off if you are performing remote upgrade or dbg or ntp functions

	if updating or dbging or ntping then shutpending = true return end
	-- Send AT command off

	req("AT+CIPSHUT")
	-- Set the close flag

	shuting = true
	if ipstatusind then sys.dispatch("IP_SHUTING_IND",true) end
	shutpending = false
end
reset = shut

--Function name: getresult
--Function: Parse socket status string
--Parameters:
--str: Wang Zheng's status string, such as ERROR, 1, SEND OK, 1, CLOSE OK
--Return Value: socket status, does not contain socket id, such as ERROR, SEND OK, CLOSE OK

local function getresult(str)
	return str == "ERROR" and str or string.match(str,"%d, *([%u :%d]+)")
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
	local id = tonumber(string.match(cmd,"AT%+%u+=(%d)"))
	-- Send data to the server's reply

	if prefix == "+CIPSEND" then
		if response == "+PDP: DEACT" then
			req("AT+CIPSTATUS")
			response = "ERROR"
		end
		if string.match(response,"DATA ACCEPT") then
			sendcnf(id,"SEND OK")
		else
			sendcnf(id,getresult(response))
		end
	-- Turn off the socket response

	elseif prefix == "+CIPCLOSE" then
		closecnf(id,getresult(response))
	-- Turn off the IP network reply

	elseif prefix == "+CIPSHUT" then
		shutcnf(response)
	-- Answer to connect to the server

	elseif prefix == "+CIPSTART" then
		if response == "ERROR" then
			statusind(id,"ERROR")
		end
	-- Activate the IP network reply

	elseif prefix == "+CIICR" then
		if success then
			-- After the success, the bottom will activate the IP network, lua applications need to send AT + CIPSTATUS query IP network status

			if checkciicrtm and not sys.timer_is_active(ciicrerrtmfnc) then
				-- Start the "Activate IP network timeout" timer

				print("ciicrerrtmfnc start")
				sys.timer_start(ciicrerrtmfnc,checkciicrtm)
			end
		else
			shut()
			sys.timer_stop(req,"AT+CIPSTATUS")
		end
	end
end

-- Register the following urc notification handler

ril.regurc("STATE",urc)
ril.regurc("C",urc)
ril.regurc("+PDP",urc)
ril.regurc("+RECEIVE",urc)
-- Register the response handler for the following AT commands

ril.regrsp("+CIPSTART",rsp)
ril.regrsp("+CIPSEND",rsp)
ril.regrsp("+CIPCLOSE",rsp)
ril.regrsp("+CIPSHUT",rsp)
ril.regrsp("+CIICR",rsp)

-- gprs network is not attached, regularly check the attachment status of the interval

local QUERYTIME = 2000

--Function name: cgattrsp
--Function: Check GPRS network attachment status response processing
--Parameters:
--cmd: AT command corresponding to this reply
--success: AT command execution result, true or false
--response: string of the execution result in the AT command's response
--intermediate: intermediate information in the response of the AT command
--Return Value: None

local function cgattrsp(cmd,success,response,intermediate)
	-- Attached

	if intermediate == "+CGATT: 1" then
		cgatt = "1"
		sys.dispatch("NET_GPRS_READY",true)

		-- If there is a link, then activate the IP network automatically after gprs is attached

		if base.next(linklist) then
			if ipstatus == "IP INITIAL" then
				setupIP()
			else
				req("AT+CIPSTATUS")
			end
		end
	-- not attached

	elseif intermediate == "+CGATT: 0" then
		if cgatt ~= "0" then
			cgatt = "0"
			sys.dispatch("NET_GPRS_READY",false)
		end
		-- Set the timer, continue to query

		sys.timer_start(querycgatt,QUERYTIME)
	end
end

--Function name: querycgatt
--Function: Check GPRS data network attachment status
--Parameters: None
--Return Value: None

function querycgatt()
	-- Not a flight mode, just to check

	if not flymode then req("AT+CGATT?",nil,cgattrsp) end
end

-- Configure the interface

local qsend = 0
function SetQuickSend(mode)
	--qsend = mode
end

local inited = false
--Function name: initial
--Function: Configure some initialization parameters for the function of this module
--Parameters: None
--Return Value: None

local function initial()
	if not inited then
		inited = true
		req("AT+CIICRMODE=2") --ciicr asynchronous

		req("AT+CIPMUX=1") -- Multiple links

		req("AT+CIPHEAD=1")
		req("AT+CIPQSEND=" .. qsend)-- send mode

	end
end

--Function name: netmsg
--Function: GSM network registration status change processing
--Parameters: None
--Return value: true

local function netmsg(id,data)
	-- GSM network is registered

	if data == "REGISTERED" then
		-- Initialize the configuration

		initial() 
		-- Regularly check GPRS data network attachment status

		sys.timer_start(querycgatt,QUERYTIME)
	end

	return true
end

-- sim card default apn table

local apntable =
{
	["46000"] = "CMNET",
	["46002"] = "CMNET",
	["46004"] = "CMNET",
	["46007"] = "CMNET",
	["46001"] = "UNINET",
	["46006"] = "UNINET",
}

--Function name: proc
--Function: This module registers the internal message processing function
--Parameters:
--id: internal message id
--para: internal message parameter
--Return value: true

local function proc(id,para)
	--IMSI read successfully

	if id=="IMSI_READY" then
		-- This module automatically get apn information for internal configuration

		if apnflag then
			if apn then
				local temp1,temp2,temp3=apn.get_default_apn(tonumber(sim.getmcc(),16),tonumber(sim.getmnc(),16))
				if temp1 == '' or temp1 == nil then temp1="CMNET" end
				setapn(temp1,temp2,temp3)
			else
				setapn(apntable[sim.getmcc()..sim.getmnc()] or "CMNET")
			end
		end
	-- Flight mode status change

	elseif id=="FLYMODE_IND" then
		flymode = para
		if para then
			sys.timer_stop(req,"AT+CIPSTATUS")
		else
			req("AT+CGATT?",nil,cgattrsp)
		end
	-- Remote upgrade begins

	elseif id=="UPDATE_BEGIN_IND" then
		updating = true
	-- Remote upgrade finished

	elseif id=="UPDATE_END_IND" then
		updating = false
		if shutpending then shut() end
	--dbg function started

	elseif id=="DBG_BEGIN_IND" then
		dbging = true
	--dbg function is over

	elseif id=="DBG_END_IND" then
		dbging = false
		if shutpending then shut() end
	-- NTP synchronization starts

	elseif id=="NTP_BEGIN_IND" then
		ntping = true
	-- NTP synchronization ends

	elseif id=="NTP_END_IND" then
		ntping = false
		if shutpending then shut() end
	end
	return true
end

--Function name: checkciicr
--Function: Set the overtime unsuccessful overtime time after setting IP network request activation. After executing AT + CIICR, if checkciicrtm is set, after checkciicrtm milliseconds, if the activation is not successful, restart the software (AT + CIPSHUT is not restarted during the execution)
--Parameters:
--tm: Timeout in milliseconds
--Return value: true

function checkciicr(tm)
	checkciicrtm = tm
	ril.regrsp("+CIICR",rsp)
end

--Function name: setiperrcb
--Function: Set the user callback function of "overtime unsuccessful" after activating IP network request
--Parameters:
--cb: callback function
--Return Value: None

function setiperrcb(cb)
	ciicrerrcb = cb
end


--Function name: setretrymode
--Function: Set "reconnection parameter of TCP protocol during connection process and data sending"
--Parameters:
--md: number type, only 0 and 1 are supported
--0 as much reconnection (it may take a long time to return to connect or send interface)
--1 for moderate reconnection (if the network is poor or no network, you can return the result of a few tenths of seconds)
--Return Value: None

function setretrymode(md)
	ril.request("AT+TCPUSERPARAM=6,"..(md==0 and 3 or 2)..",7200")
end

-- Register the handler for the internal message of interest to this module

sys.regapp(proc,"IMSI_READY","FLYMODE_IND","UPDATE_BEGIN_IND","UPDATE_END_IND","DBG_BEGIN_IND","DBG_END_IND","NTP_BEGIN_IND","NTP_END_IND")
sys.regapp(netmsg,"NET_STATE_CHANGED")
checkciicr(120000)
