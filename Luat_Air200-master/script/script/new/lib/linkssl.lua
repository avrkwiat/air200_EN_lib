
--Module Name: SSL SOCKET Management
--Module Function: SSL SOCKET creation, connection, data transceiver, status maintenance
--Last modified on: 2017.04.26

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local table = require"table"
local sys = require"sys"
local ril = require"ril"
local net = require"net"
local rtos = require"rtos"
local sim = require"sim"
local link = require"link"
module("linkssl",package.seeall)

-- Load common global functions to local

local print = base.print
local pairs = base.pairs
local tonumber = base.tonumber
local tostring = base.tostring
local req = ril.request

local ipstatus,shuting
-- The maximum socket id, starting from 0, so at the same time support the socket connection is 8

local MAXLINKS = 7
--socket connection table

local linklist = {}
-- Whether to initialize

local inited
local crtpending = {}

local function print(...)
	_G.print("linkssl",...)
end

--Function name: init
--Function: Initialize ssl function module
--Parameters: None
--Return Value: None

local function init()
	if not inited then
		inited = true
		req("AT+SSLINIT")
		local i,item
		for i=1,#crtpending do
			item = table.remove(crtpending,1)
			req(item.cmd,item.arg)
		end
	end
end

--Function name: term
--Function: Turn off the ssl function module
--Parameters: None
--Return Value: None

local function term()
	if inited then
		inited = false
		req("AT+SSLTERM")
	end
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
		print("validaction:id nil",id)
		return false
	end

	-- The same state is not repeated

	if action.."ING" == linklist[id].state then
		print("validaction:",action,linklist[id].state)
		return false
	end

	local ing = string.match(linklist[id].state,"(ING)",-3)

	if ing then
		-- There are other tasks in the handling, not allowed to deal with the connection, broken chain or closed is possible

		if action == "CONNECT" then
			print("validaction: action running",linklist[id].state,action)
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

	local item = {
		notify = notify,
		recv = recv,
		state = "INITIAL",
		tag = tag,
	}

	linklist[id] = item

	-- Register to connect urc

	ril.regurc("SSL&"..id,urc)
	
	-- Activate IP network

	if not ipstatus then
		link.setupIP()
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

	req("AT+SSLDESTROY="..id)

	return true
end

--Function name: connect
--Function: socket connection server request
--Parameters:
--id: socket id
--protocol: transport layer protocol, TCP or UDP
--address: server address
--port: server port
--chksvrcrt: boolean type, whether to check the server certificate
--crtconfig: nil or table type, {verifysvrcerts = {"filepath1", "filepath2", ...}, clientcert = "filepath", clientcertpswd = "password", clientkey = "filepath"}
--Return Value: The request successfully synchronized to return true, otherwise false;

function connect(id,protocol,address,port,chksvrcrt,crtconfig)
	-- Not allowed to initiate connection action

	if validaction(id,"CONNECT") == false or linklist[id].state == "CONNECTED" then
		return false
	end

	linklist[id].state = "CONNECTING"

	local createstr = string.format("AT+SSLCREATE=%d,\"%s\",%d",id,address..":"..port,chksvrcrt and 0 or 1)
	local configcrtstr,i = {}
	if crtconfig then
		if chksvrcrt and crtconfig.verifysvrcerts then
			for i=1,#crtconfig.verifysvrcerts do
				table.insert(configcrtstr,"AT+SSLCERT=1,"..id..",\"cacrt\",\""..crtconfig.verifysvrcerts[i].."\"")
			end
		end
		if crtconfig.clientcert then
			table.insert(configcrtstr,"AT+SSLCERT=1,"..id..",\"localcrt\",\""..crtconfig.clientcert.."\",\""..(crtconfig.clientcertpswd or "").."\"")
		end
		if crtconfig.clientkey then
			table.insert(configcrtstr,"AT+SSLCERT=1,"..id..",\"localprivatekey\",\""..crtconfig.clientkey.."\"")
		end
	end
	local connstr = "AT+SSLCONNECT="..id

	if not ipstatus or shuting then
		--ip environment is not ready to join the wait

		linklist[id].pending = createstr.."\r\n"
		for i=1,#configcrtstr do
			linklist[id].pending = linklist[id].pending..configcrtstr[i].."\r\n"
		end
		linklist[id].pending = linklist[id].pending..connstr.."\r\n"
	else
		init()
		-- Send AT command to connect to the server

		req(createstr)
		for i=1,#configcrtstr do
			req(configcrtstr[i])
		end
		req(connstr)
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
		if not ipstatus and linklist[id].state == "CONNECTING" then
			print("disconnect: ip not ready",ipstatus)
			linklist[id].state = "DISCONNECTING"
			return
		end
	end

	linklist[id].state = "DISCONNECTING"
	-- Send AT command to disconnect

	req("AT+SSLDESTROY="..id)

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
		print("send:error",id)
		return false
	end

	-- Send AT command to send data

	req(string.format("AT+SSLSEND=%d,%d",id,string.len(data)),data)

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
		print("recv:error",id)
		return
	end
	-- Call socket id corresponding to the user registration data reception processing functions

	if linklist[id].recv then
		linklist[id].recv(id,data)
	else
		print("recv:nil recv",id)
	end
end

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
	--Failed to send

	if string.match(result,"ERROR") then
		linklist[id].state = "ERROR"
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
		print("closecnf:error",id)
		return
	end
	-- No matter what the close result, the link is always disconnected successfully, so the link is disconnected

	if linklist[id].state == "DISCONNECTING" then
		linklist[id].state = "CLOSED"
		linklist[id].notify(id,"DISCONNECT","OK")
		usersckntfy(id,false)
	-- Connection logout, clear the maintenance of the connection information, clear urc attention

	elseif linklist[id].state == "CLOSING" then		
		local tlink = linklist[id]
		usersckntfy(id,false)
		linklist[id] = nil
		ril.deregurc("SSL&"..id,urc)
		tlink.notify(id,"CLOSE","OK")		
	else
		print("closecnf:error",linklist[id].state)
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
		print("statusind:nil id",id)
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
end

--Function name: connpend
--Function: Performs socket connection requests that are suspended because the IP network is not ready
--Parameters: None
--Return Value: None

local function connpend()
	for i = 0,MAXLINKS do
		if linklist[i] ~= nil then
			if linklist[i].pending then
				init()
				local item
				for item in string.gmatch(linklist[i].pending,"(.-)\r\n") do
					req(item)
				end
				linklist[i].pending = nil
			end
		end
	end	
end

--Function name: ipstatusind
--Function: IP network status change processing
--Parameters:
--s: IP network status
--Return Value: None

local function ipstatusind(s)
	print("ipstatus:",ipstatus,s)
	if ipstatus ~= s then
		ipstatus = s
		-- Performs a pending socket connection request

		if s then connpend() end
	end
end

--Function name: shutcnf
--Function: Turn off IP network result processing
--Parameters:
--result: closes the result string
--Return Value: None

local function shutcnf(result)
	shuting = false
	-- closed successfully

	if result == "SHUT OK" then
		ipstatusind(false)
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
			end
		end
	end
end

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
	--socket received the data sent by the server

	if prefix == "+SSL RECEIVE" then
		local lid,len = string.match(data,",(%d),(%d+)",string.len("+SSL RECEIVE")+1)
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

--Function name: getresult
--Function: Parse socket status string
--Parameters:
--str: socket status string, such as SSL & 1, SEND OK
--Return Value: Socket state, does not contain socket id, for example, SEND OK

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
	
	if prefix == "+SSLCONNECT" then
		--statusind(id,getresult(response))
		if response == "ERROR" then
			statusind(id,"ERROR")
		end
	-- Send data to the server's reply

	elseif prefix == "+SSLSEND" then
		sendcnf(id,getresult(response))
	-- Turn off the socket response

	elseif prefix == "+SSLDESTROY" then
		closecnf(id,getresult(response))	
	end
end

local function ipshutingind(s)
	if s then
		shuting = true
	else
		shutcnf("SHUT OK")
	end
end

local function gprsind(s)
	if s and base.next(linklist) and not ipstatus then
		link.setupIP()
	end
end

function inputcrt(t,f,d)
	table.insert(crtpending,{cmd="AT+SSLCERT=0,\""..t.."\",\""..f.."\",1,"..string.len(d),arg=d})
end

local procer =
{
	IP_STATUS_IND = ipstatusind,
	IP_SHUTING_IND = ipshutingind,
	NET_GPRS_READY = gprsind,
}

sys.regapp(procer)
-- Register the following urc notification handler

ril.regurc("+SSL RECEIVE",urc)
-- Register the response handler for the following AT commands

ril.regrsp("+SSLCONNECT",rsp)
ril.regrsp("+SSLSEND",rsp)
ril.regrsp("+SSLDESTROY",rsp)

link.regipstatusind()
