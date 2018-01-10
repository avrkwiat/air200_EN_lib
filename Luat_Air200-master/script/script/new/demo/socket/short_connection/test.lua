require"socket"
module(...,package.seeall)

--This example is a short connection
--Functional Requirements:
--1, every 10 seconds to send a location package "loc data \ r \ n" to the background, regardless of the success or failure of the transmission, are disconnected after 5 seconds;
--2, received the background data, print out in the rcv function
--Please set up your own test server, and modify the following PROT, ADDR, PORT, support for domain names and IP addresses


local ssub,schar,smatch,sbyte,slen = string.sub,string.char,string.match,string.byte,string.len
-- Please set up your own server test
local SCK_IDX,PROT,ADDR,PORT = 1,"TCP","120.26.196.195",9999
--linksta: Socket connection status with the background
local linksta
-- The server was successfully connected
local hasconnected
-- After boot if there is no connection to the background, there will be the following exception handling
-- Actions in a connection cycle: If the connection to the background fails, a reconnection will be attempted with a reconnection interval of RECONN_PERIOD seconds and a maximum of RECONN_MAX_CNT times
-- If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
-- If no consecutive RECONN_CYCLE_MAX_CNT connection cycles are successful, restart the software
local RECONN_MAX_CNT,RECONN_PERIOD,RECONN_CYCLE_MAX_CNT,RECONN_CYCLE_PERIOD = 3,5,3,20
--reconncnt: The number of reconnections in the current connection cycle
--reconncyclecnt: how many consecutive connection cycle, no connection is successful
-- Once the connection is successful, both flags are reset
--conning: Whether or not you are trying to connect
local reconncnt,reconncyclecnt,conning = 0,0

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

--Function name: snd
--Function: Call the sending interface to send data
--Parameters:
--???????? data: The data sent, in the send result event handler ntfy, will be assigned to item.data
--para: send the parameters, in the send result event handler ntfy, will be assigned to the item.para
--Return Value: The result of invoking the sending interface (not the result of data sending success or not, the result of data sending success is notified in the SEND event in ntfy), true is success and the others are failed

function snd(data,para)
	return socket.send(SCK_IDX,data,para)
end
--Function name: locrpt
--Function: send location package data to the background
--Parameters: None
--Return Value: None

function locrpt()
	print("locrpt",linksta)
	--if linksta then
		if not snd("loc data\r\n","LOCRPT")	then locrptcb({data="loc data\r\n",para="LOCRPT"},false) end	
	--end
end

--Function name: locrptcb
--Function: location package send result processing, start timer, send location package again after 10 seconds
--Parameters:
--???????? result: bool type, the results of the transmission or whether overtime, true for the success or overtime, the other failure
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socket.send is called are dat and par, then item = {data = dat, para = par}
--Return Value: None

function locrptcb(item,result)
	print("locrptcb",linksta)
	--if linksta then
		-- 5 seconds later to disconnect the socket connection, which is used to receive the server's data within 5 seconds
		sys.timer_start(socket.disconnect,5000,SCK_IDX)
		sys.timer_start(locrpt,10000)
	--end
end

--Function name: sndcb
--Function: Send data result event processing
--Parameters:
--???????? result: bool type, the result of the message event, true is successful, others are failed
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socket.send is called are dat and par, then item = {data = dat, para = par}
--Return Value: None

local function sndcb(item,result)
	print("sndcb",item.para,result)
	if not item.para then return end
	if item.para=="LOCRPT" then
		locrptcb(item,result)
	end
	if not result then link.shut() end
end

--Function name: reconn
--Function: Reconnection background processing
--???????? A connection cycle of action: If the connection fails the background, will try to reconnect, reconnect interval RECONN_PERIOD seconds, up to reconnect RECONN_MAX_CNT times
--???????? If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
--???????? If consecutive RECONN_CYCLE_MAX_CNT secondary connection cycles are not connected successfully, then restart the software
--Parameters: None
--Return Value: None

local function reconn()
	print("reconn",reconncnt,conning,reconncyclecnt)
	-- Conning that is trying to connect to the background, be sure to judge this variable, otherwise it may initiate unnecessary reconnection, resulting in reconncnt increase, the actual number of reconnections decreased
	if conning then return end
	-- Reconnect within a connection cycle
	if reconncnt < RECONN_MAX_CNT then
		reconncnt = reconncnt+1
		link.shut()
		connect()
	-- Reconnection of one connection cycle failed
	else
		reconncnt,reconncyclecnt = 0,reconncyclecnt+1
		if reconncyclecnt >= RECONN_CYCLE_MAX_CNT then
			sys.restart("connect fail")
		end
		sys.timer_start(reconn,RECONN_CYCLE_PERIOD*1000)
	end
end

--Function name: ntfy
--Function: Socket state processing function
--Parameters:
--???????? idx: number type, the socket idx maintained in socket.lua, the same as the first argument passed when socket.connect was invoked, the program can ignore the non-processing
--???????? evt: string type, the message event type
--result: bool type, the result of the message event, true is successful, others are failed
--The item: table type, {data =, para =}, parameters and data returned by the message, is currently only used in SEND type events such as the second and third passed in when socket.send is called The parameters are dat and par, then item = {data = dat, para = par}
--Return Value: None

function ntfy(idx,evt,result,item)
	print("ntfy",evt,result,item,hasconnected)
	-- connection result (asynchronous event after socket.connect call)
	if evt == "CONNECT" then
		conning = false
		--connection succeeded
		if result then
			reconncnt,reconncyclecnt,linksta = 0,0,true
			-- Stop the reconnection timer
			sys.timer_stop(reconn)
			-- The first connection after power on is successful
			if not hasconnected then
				hasconnected = true
				-- send the location package to the background
				locrpt()
			end
		--Connection failed
		else
			if not hasconnected then
				-- Reconnect after 5 seconds
				sys.timer_start(reconn,RECONN_PERIOD*1000)
			else				
				link.shut()
			end			
		end	
	-- Data transmission result (asynchronous event after socket.send is called)
	elseif evt == "SEND" then
		if item then
			sndcb(item,result)
		end
	-- The connection is disconnected passively
	elseif evt == "STATE" and result == "CLOSED" then
		linksta = false
		-- Supplement custom function code
	-- Active disconnect (asynchronous after calling link.shut)
	elseif evt == "STATE" and result == "SHUTED" then
		linksta = false
		-- Supplement custom function code
	-- Active disconnect (asynchronous after calling socket.disconnect)
	elseif evt == "DISCONNECT" then
		linksta = false
		-- Supplement custom function code	
	end
	-- Other error handling
	if smatch((type(result)=="string") and result or "","ERROR") then
		-- Disconnect the data link and reactivate it
		link.shut()
	end
end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? idx: socket idx maintained in socket.lua, the same as the first parameter passed in when socket.connect is invoked, and the program can ignore the non-processing
--???????? data: received data
--Return Value: None

function rcv(idx,data)
	print("rcv",data)
end

--Function name: connect
--Function: to create a connection to the background server;
--???????? If the data network is ready, it will understand the background connection; otherwise, the connection request will be suspended, and so the data network is ready, automatically connect to the background
--ntfy: socket state handler
--rcv: socket receive data processing functions
--Parameters: None
--Return Value: None

function connect()
	socket.connect(SCK_IDX,PROT,ADDR,PORT,ntfy,rcv)
	conning = true
end

connect()
