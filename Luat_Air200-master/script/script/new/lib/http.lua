
module(...,package.seeall)

require "common"
require"socket"
local lpack=require"pack"

local sfind, slen,sbyte,ssub,sgsub,schar,srep,smatch,sgmatch= string.find ,string.len,string.byte,string.sub,string.gsub,string.char,string.rep,string.match,string.gmatch

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("http",...)
end



--http clients storage table

local tclients = {}

--Function name: getclient
--Function: Returns an http client index in tclients
--Parameters:
--sckidx: http client corresponding socket index
--Return values: Index of http client corresponding to sckidx in tclients

local function getclient(sckidx)
	for k,v in pairs(tclients) do
		if v.sckidx==sckidx then return k end
	end
end



--Function name: datinactive
--Function: Data communication exception handling
--Parameters:
--sckidx: socket idx
--Return Value: None

local function datinactive(sckidx)
    sys.restart("SVRNODATA")
end

--Function name: snd
--Function: Call the sending interface to send data
--Parameters:
--sckidx: socket idx
--???????? data: The data sent, in the send result event handler ntfy, will be assigned to item.data
--para: send the parameters, in the send result event handler ntfy, will be assigned to the item.para
--Return Value: The result of invoking the sending interface (not the result of data sending success or not, the result of data sending success is notified in the SEND event in ntfy), true is success and the others are failed

function snd(sckidx,data,para)
    return socket.send(sckidx,data,para)
end


local RECONN_MAX_CNT,RECONN_PERIOD,RECONN_CYCLE_MAX_CNT,RECONN_CYCLE_PERIOD = 3,5,3,20




--Function name: reconn
--Function: socket reconnect background processing
--???????? A connection cycle of action: If the connection fails the background, will try to reconnect, reconnect interval RECONN_PERIOD seconds, up to reconnect RECONN_MAX_CNT times
--???????? If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
--???????? If consecutive RECONN_CYCLE_MAX_CNT secondary connection cycles are not connected successfully, then restart the software
--Parameters:
--sckidx: socket idx
--Return Value: None

function reconn(sckidx)
	local httpclientidx = getclient(sckidx)
	print("reconn"--[[,httpclientidx,tclients[httpclientidx].sckreconncnt,tclients[httpclientidx].sckconning,tclients[httpclientidx].sckreconncyclecnt]])
	--sckconning Indicates that you are trying to connect to the background, be sure to judge this variable, otherwise it may initiate unnecessary reconnection, resulting in increased sckreconncnt, reduce the actual number of reconnections
	if tclients[httpclientidx].sckconning then return end
	-- Reconnect within a connection cycle

	if tclients[httpclientidx].sckreconncnt < RECONN_MAX_CNT then		
		tclients[httpclientidx].sckreconncnt = tclients[httpclientidx].sckreconncnt+1
		link.shut()
		for k,v in pairs(tclients) do
			connect(v.sckidx,v.prot,v.host,v.port)
		end
	-- Reconnection of one connection cycle failed

	else
		tclients[httpclientidx].sckreconncnt,tclients[httpclientidx].sckreconncyclecnt = 0,tclients[httpclientidx].sckreconncyclecnt+1
		if tclients[httpclientidx].sckreconncyclecnt >= RECONN_CYCLE_MAX_CNT then
			if tclients[httpclientidx].sckerrcb then
				tclients[httpclientidx].sckreconncnt=0
				tclients[httpclientidx].sckreconncyclecnt=0
				tclients[httpclientidx].sckerrcb("CONNECT")
			else
				sys.restart("connect fail")
			end
		else
			sys.timer_start(reconn,RECONN_CYCLE_PERIOD*1000,sckidx)
		end		
	end
end

--Function name: ntfy
--Function: Socket state processing function
--Parameters:
--???????? idx: number type socket socket ID maintained socket the same as the first argument passed socket.connect, the program can ignore the non-processing
--???????? evt: string type, the message event type
--result: bool type, the result of the message event, true is successful, others are failed
--The item: table type, {data =, para =}, parameters and data returned by the message, is currently only used in SEND type events such as the second and third passed in when socket.send is called The parameters are dat and par, then item = {data = dat, para = par}
--Return Value: None

function ntfy(idx,evt,result,item)
	local httpclientidx = getclient(idx)
	print("ntfy",evt,result,item)
	-- connection result (asynchronous event after socket.connect call)

	if evt == "CONNECT" then
		tclients[httpclientidx].sckconning = false
		--connection succeeded

		if result then
			tclients[httpclientidx].sckconnected=true
			tclients[httpclientidx].sckreconncnt=0
			tclients[httpclientidx].sckreconncyclecnt=0
			-- Stop the reconnection timer

			sys.timer_stop(reconn,idx)
			tclients[httpclientidx].connectedcb()
		--	snd(idx,"GET / HTTP/1.1\r\nHost: www.openluat.com\r\nConnection: keep-alive\r\n\r\n","GET")
		-- Connection failed

		else
			-- RECONN_PERIOD seconds later reconnect

			sys.timer_start(reconn,RECONN_PERIOD*1000,idx)
		end	
	-- Data transmission result (asynchronous event after socket.send is called)

	elseif evt == "SEND" then
		if not result then
			print("error code")	     	
		end
	-- The connection is disconnected passively

	elseif evt == "STATE" and result == "CLOSED" then
		tclients[httpclientidx].sckconnected=false
		tclients[httpclientidx].httpconnected=false
		tclients[httpclientidx].sckconning = false
		-- Used when connecting long

		if tclients[httpclientidx].mode then
			reconn(idx)
		end
	-- Active disconnect (asynchronous after calling link.shut)

	elseif evt == "STATE" and result == "SHUTED" then
		tclients[httpclientidx].sckconnected=false
		tclients[httpclientidx].httpconnected=false
		tclients[httpclientidx].sckconning = false
		-- Used when connecting long

		if tclients[httpclientidx].mode then
			reconn(idx)
		end
	-- Active disconnect (asynchronous after calling socket.disconnect)

	elseif evt == "DISCONNECT" then
		tclients[httpclientidx].sckconnected=false
		tclients[httpclientidx].httpconnected=false
		tclients[httpclientidx].sckconning = false
		if item=="USER" then
			if tclients[httpclientidx].discb then tclients[httpclientidx].discb(idx) end
			tclients[httpclientidx].discing = false
		end	
	-- Used when connecting long

		if tclients[httpclientidx].mode then
			reconn(idx)
		end
	-- The connection is actively disconnected and destroyed (an asynchronous event after socket.close is called)

	elseif evt == "CLOSE" then
		local cb = tclients[httpclientidx].destroycb
		table.remove(tclients,httpclientidx)
		if cb then cb() end
	end
	-- Other error handling, disconnect the data link, reconnect

	if smatch((type(result)=="string") and result or "","ERROR") then
		link.shut()
	end
end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? idx: Socket socket idx maintained socket, the same as the first argument passed socket.connect, the program can ignore the non-processing
--???????? data: received data
--Return Value: None

--Function name: Timerfnc
--Function: Start the timer when the received data times out
--Parameters: ID of the SOCKER corresponding to the client
--return value:

function  timerfnc(httpclientidx)
	tclients[httpclientidx].result=3
	tclients[httpclientidx].statuscode=nil
	tclients[httpclientidx].rcvhead=nil
	tclients[httpclientidx].rcvbody=nil
	tclients[httpclientidx].rcvcb(tclients[httpclientidx].result)
	tclients[httpclientidx].status=false
	tclients[httpclientidx].result=nil
	tclients[httpclientidx].statuscode=nil
	tclients[httpclientidx].data=nil
end

--Function name: data reception processing function
--Function: The server returns the data for processing
--Parameters: idx: port corresponding to the client data: data returned by the server
--Return Value: None

function rcv(idx,data)
    local httpclientidx = getclient(idx)
	-- Set a timer for 5 seconds

	sys.timer_start(timerfnc,5000,httpclientidx)
	-- if there is no data

	if not data then 
		print("rcv: no data receive")
	-- Receive feedback function if present

	elseif tclients[httpclientidx].rcvcb then 
		-- Create receive data

		if not tclients[httpclientidx].data then tclients[httpclientidx].data="" end 
		tclients[httpclientidx].data=tclients[httpclientidx].data..data
		local h1,h2 = sfind(tclients[httpclientidx].data,"\r\n\r\n")
		-- get the status line and header, determine the status
		-- parse the status line and all headers
		if sfind(tclients[httpclientidx].data,"\r\n\r\n") and not tclients[httpclientidx].status then 
			-- Set status parameters, if it is true next time you do not need to run this process

			tclients[httpclientidx].status=true 
			local totil=ssub(tclients[httpclientidx].data,1,h2+1)
			tclients[httpclientidx].statuscode=smatch(totil,"%s(%d+)%s")
			tclients[httpclientidx].contentlen=tonumber(smatch(totil,":%s(%d+)\r\n"),10)
			local total=smatch(totil,"\r\n(.+\r\n)\r\n")
			-- judge total is empty

			if	total~=""	then	
				if	not tclients[httpclientidx].rcvhead	 then	tclients[httpclientidx].rcvhead={}	end
				for k,v in sgmatch(total,"(.-):%s(.-)\r\n") do
					if	v=="chunked"	then
						chunked=true
					end
					tclients[httpclientidx].rcvhead[k]=v
				end
			end
		end
		-- If you have already got the header and there is a receive feedback function

		if	tclients[httpclientidx].rcvhead	and tclients[httpclientidx].rcvcb then
			-- whether the head is Transfer-Encoding = chunked, if the block transfer encoding is used

			if	chunked	then
				if	sfind(ssub(tclients[httpclientidx].data,h2,-1),"\r\n%s-0%s-\r\n")	then
					local	chunkedbody = ""
					for k in sgmatch(ssub(tclients[httpclientidx].data,h2+1,-1),"%x-\r\n(.-)\r\n") do
						chunkedbody=chunkedbody..k
					end
					tclients[httpclientidx].rcvbody=chunkedbody
					tclients[httpclientidx].result=4
					tclients[httpclientidx].rcvcb(tclients[httpclientidx].result,tclients[httpclientidx].statuscode,tclients[httpclientidx].rcvhead,tclients[httpclientidx].rcvbody)
					sys.timer_stop(timerfnc,httpclientidx)
					tclients[httpclientidx].result=nil
					tclients[httpclientidx].statuscode=nil
					tclients[httpclientidx].statuscode=nil
					tclients[httpclientidx].rcvhead=nil
					tclients[httpclientidx].rcvbody=nil
					tclients[httpclientidx].data=""
					tclients[httpclientidx].status=false
					chunked=false
				end		
			-- Whether to get the entity if it is running below

			elseif ssub(tclients[httpclientidx].data,h2+1,-1) then
				-- There is an entity and the length of the entity is equal to the actual length

				if	 slen(ssub(tclients[httpclientidx].data,h2+1,-1)) == tclients[httpclientidx].contentlen	then
					tclients[httpclientidx].result=0
					tclients[httpclientidx].rcvbody=ssub(tclients[httpclientidx].data,h2+1,-1)
					-- Get the entity

					tclients[httpclientidx].rcvcb(tclients[httpclientidx].result,tclients[httpclientidx].statuscode,tclients[httpclientidx].rcvhead,tclients[httpclientidx].rcvbody)
					sys.timer_stop(timerfnc,httpclientidx)
					tclients[httpclientidx].result=nil
					tclients[httpclientidx].statuscode=nil
					tclients[httpclientidx].statuscode=nil
					tclients[httpclientidx].rcvhead=nil
					tclients[httpclientidx].rcvbody=nil
					tclients[httpclientidx].data=""
					tclients[httpclientidx].status=false
				elseif	slen(ssub(tclients[httpclientidx].data,h2+1,-1)) > tclients[httpclientidx].contentlen	then
					-- There are entities and the entity length is greater than the actual length

					tclients[httpclientidx].result=2
					tclients[httpclientidx].rcvbody=nil
					tclients[httpclientidx].rcvcb(tclients[httpclientidx].result,tclients[httpclientidx].statuscode,tclients[httpclientidx].rcvhead)
					sys.timer_stop(timerfnc,httpclientidx)
					tclients[httpclientidx].result=nil
					tclients[httpclientidx].statuscode=nil
					tclients[httpclientidx].statuscode=nil
					tclients[httpclientidx].rcvhead=nil
					tclients[httpclientidx].data=""
					tclients[httpclientidx].status=false										
				end
			-- There is a header, but the entity length is 0

			elseif	 tclients[httpclientidx].contentlen==0	then
				tclients[httpclientidx].result=1
				tclients[httpclientidx].rcvcb(tclients[httpclientidx].result,tclients[httpclientidx].statuscode,tclients[httpclientidx].rcvhead)
				sys.timer_stop(timerfnc,httpclientidx)
				tclients[httpclientidx].result=nil
				tclients[httpclientidx].statuscode=nil
				tclients[httpclientidx].statuscode=nil
				tclients[httpclientidx].rcvhead=nil
				tclients[httpclientidx].data=""
				tclients[httpclientidx].status=false
			end
		-- There is data and no feedback function is received

		elseif	not tclients[httpclientidx].rcvhead	then
			print("no message reback")
		else
			print("rcv",data)
		end
	end
end



--Function name: connect
--Function: create a socket connection to the background server;
--???????? If the data network is ready, it will understand the background connection; otherwise, the connection request will be suspended, and so the data network is ready, automatically connect to the background
--ntfy: socket state handler
--rcv: socket receive data processing functions
--Parameters:
--sckidx: socket idx
--prot: string type, transport layer protocol, only supports "TCP"
--host: string type, server address, supporting domain name and IP address [Required]
--port: number type, server port [Required]
--Return Value: None

function connect(sckidx,prot,host,port)
	socket.connect(sckidx,prot,host,port,ntfy,rcv)
	tclients[getclient(sckidx)].sckconning=true
end


-- used to create the meta-table

local thttp = {}
thttp.__index = thttp



--Function name: create
--Function: Create a http client
--Parameters:
--prot: string type, transport layer protocol, only supports "TCP"
--host: string type, server address, supporting domain name and IP address [Required]
--port: number type, server port [Required]
--Return Value: None

function create(host,port)
	if #tclients>=4 then assert(false,"tclients maxcnt error") return end
	local http_client =
	{
		prot="TCP",
		-- defaults to "www.openluat.com"

		host=host or "36.7.87.100",
		-- The default port is 80

		port=port or 81 ,		
		sckidx=socket.SCK_MAX_CNT-#tclients,
		sckconning=false,
		sckconnected=false,
		sckreconncnt=0,
		sckreconncyclecnt=0,
		httpconnected=false,
		discing=false,
		status=false,
		rcvbody=nil,
		rcvhead={},
		result=nil,
		statuscode=nil,
		contentlen=nil
	}
	setmetatable(http_client,thttp)
	table.insert(tclients,http_client)
	return(http_client)
end

--Function name: connect
--Function: connect http server
--Parameters:
--???????? connectedcb: function type, socket connected successful callback function
--sckerrcb: function type, socket connection failed callback function [optional]
--Return Value: None

function thttp:connect(connectedcb,sckerrcb)
	self.connectedcb=connectedcb
	self.sckerrcb=sckerrcb
	
	tclients[getclient(self.sckidx)]=self
	
	if self.httpconnected then print("thttp:connect already connected") return end
	if not self.sckconnected then
		--carried out

		connect(self.sckidx,self.prot,self.host,self.port) 
    end
end

--Function name: setconnectionmode
--Function: Set the connection mode, long connection or short link
--Parameters: v, true for the long connection, false for the short link
--return:

function thttp:setconnectionmode(v)
	self.mode=v
end

--Function name: disconnect
--Function: Disconnect a http client, and disconnect the socket
--Parameters:
--discb: function type, callback function after disconnection [optional]
--Return Value: None

function thttp:disconnect(discb)
	print("thttp:disconnect")
	self.discb=discb
	self.discing = true
	socket.disconnect(self.sckidx,"USER")
end

--Function name: destroy
--Function: Destroys an http client
--Parameters:
--destroycb: function type, mqtt client callback function after destruction [optional]
--Return Value: None

function thttp:destroy(destroycb)
	local k,v
	self.destroycb = destroycb
	for k,v in pairs(tclients) do
		if v.sckidx==self.sckidx then
			socket.close(v.sckidx)
		end
	end
end


--Function name: seturl
--Function: Add the given parameters into the table
--Parameters: url A generic identifier describing the path to the resource
--return value:

function thttp:seturl(url) 
	url=url
	self.url=url
end

--Function name: addhead
--Function: Add the first section
--Parameters: name, val The first parameter is the name of the first part, the second parameter is the value of the first part, the first part of the method
--return value:

function thttp:addhead(name,val)
	if not self.head then self.head = {} end
	self.head[name]=val
end

--Function name: setbody
--Function: Add entity
--Parameters: body entity content
--return value:

function thttp:setbody(body)
	self.body=body
end
 
--Function name: request
--Function: The message data integration, and then follow the given command to send
--Parameters: cmdtyp (method of sending a message)
--Return Value: None

function thttp:request(cmdtyp,rcvcb)
	self.cmdttyp=cmdtye
	self.rcvcb=rcvcb
	-- The default url path is the root directory

    if	not	self.url	then
		self.url="/"
	end
	-- The default header is Connection: keep-alive

	if	not	self.head	then
		self.head={}
--		self.head["Host"]="36.7.87.100"
		self.head["Connection"]="keep-alive"
	end
	-- The default entity is empty

	if 	not	self.body	then
		self.body=""
	end
	if	cmdtyp	then
		val=cmdtyp.." "..self.url.." HTTP/1.1"..'\r\n'
		for k,v in pairs(self.head) do
			val=val..k..": "..v..'\r\n'
		end
		if self.body then 
			val=val.."\r\n"..self.body
		end
	end 	
	snd(self.sckidx,val,cmdtyp)	
end

--Function name: getstatus
--Function: Get the status of HTTP CLIENT
--Parameters: None
--Return Value: HTTP CLIENT state, string type, a total of 3 states:
--DISCONNECTED: Not connected status
--CONNECTING: connection status
--CONNECTED: connection status

function thttp:getstatus()
	if self.httpconnected then
		return "CONNECTED"
	elseif self.sckconnected or self.sckconning then
		return "CONNECTING"
	elseif self.disconnect then
		return "DISCONNECTED"
	end
end

