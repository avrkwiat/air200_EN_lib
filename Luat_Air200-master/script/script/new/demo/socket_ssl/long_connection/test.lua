require"socketssl"
module(...,package.seeall)


--Functional Requirements:
--1, the data network is ready, connect https background
--2, After the connection is successful, every 20 seconds to send a GET command to the background
--3, keep a long connection with the background, take the initiative again after disconnecting reconnection, the connection is still successful in accordance with Article 2 to send data
--4, received the background data, print out in the rcv function
--Please set up your own test server, and modify the following PROT, ADDR, PORT, support for domain names and IP addresses

--This example is a long connection, as long as the software can detect the network anomalies, you can automatically re-connect


local ssub,schar,smatch,sbyte,slen = string.sub,string.char,string.match,string.byte,string.len
-- Please set up your own server test
local SCK_IDX,PROT,ADDR,PORT = 1,"TCP","36.7.87.100",4433
--linksta: Socket connection status with the background
local linksta
-- Actions in a connection cycle: If the connection to the background fails, a reconnection will be attempted with a reconnection interval of RECONN_PERIOD seconds and a maximum of RECONN_MAX_CNT times
-- If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
-- If no consecutive RECONN_CYCLE_MAX_CNT connection cycles are successful, restart the software
local RECONN_MAX_CNT,RECONN_PERIOD,RECONN_CYCLE_MAX_CNT,RECONN_CYCLE_PERIOD = 3,5,3,20
--reconncnt: The number of reconnections in the current connection cycle
--reconncyclecnt: how many consecutive connection cycle, no connection is successful
-- Once the connection is successful, both flags are reset
--conning: Whether or not you are trying to connect
local reconncnt,reconncyclecnt,conning = 0,0

local sndata = "GET / HTTP/1.1\r\nHost: 36.7.87.100\r\nConnection: keep-alive\r\n\r\n"

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
	return socketssl.send(SCK_IDX,data,para)
end


--Function name: httpget
--Function: send GET command to the background
--Parameters: None
--Return Value: None

function httpget()
	print("httpget",linksta)
	if linksta then
		snd(sndata,"HTTPGET")		
	end
end


--Function name: httpgetcb
--Function: The GET command sends a callback, starts the timer, and sends the GET command again after 20 seconds
--Parameters:
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socketssl.send is called are dat and par respectively, item = {data = dat, para = par}
--result: bool type, send the result, true is successful, the other is failed
--Return Value: None

function httpgetcb(item,result)
	print("httpgetcb",linksta)
	if linksta then
		sys.timer_start(httpget,20000)
	end
end

--Function name: sndcb
--Function: Data transmission result processing
--Parameters:
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socketssl.send is called are dat and par respectively, item = {data = dat, para = par}
--result: bool type, send the result, true is successful, the other is failed
--Return Value: None

local function sndcb(item,result)
	print("sndcb",item.para,result)
	if not item.para then return end
	if item.para=="HTTPGET" then
		httpgetcb(item,result)
	end
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
		socketssl.disconnect(SCK_IDX)
		link.shut()		
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
--???????? idx: number type, the socket idx maintained in socketssl.lua, the same as the first parameter passed in when socketssl.connect is called, the program can ignore the non-processing
--???????? evt: string type, the message event type
--result: bool type, the result of the message event, true is successful, others are failed
--The item: table type, {data =, para =}, parameters and data returned by the message, is currently only used in SEND type events such as the second and third passed in when socketssl.send is called The parameters are dat and par, then item = {data = dat, para = par}
--Return Value: None

function ntfy(idx,evt,result,item)
	print("ntfy",evt,result,item)
	-- connection result (asynchronous event after calling socketssl.connect)
	if evt == "CONNECT" then
		conning = false
		--connection succeeded
		if result then
			reconncnt,reconncyclecnt,linksta = 0,0,true
			-- Stop the reconnection timer
			sys.timer_stop(reconn)
			-- send GET command to the background
			httpget()
		--Connection failed
		else
			-- RECONN_PERIOD seconds later reconnect
			sys.timer_start(reconn,RECONN_PERIOD*1000)
		end	
	-- Data transmission result (asynchronous event after calling socketssl.send)
	elseif evt == "SEND" then
		if item then
			sndcb(item,result)
		end
		-- failed to send, RECONN_PERIOD seconds later reconnect background, do not call reconn, socket status is still CONNECTED, will not be able to even have the server
		--if not result then sys.timer_start(reconn,RECONN_PERIOD*1000) end
		if not result then link.shut() end
	-- The connection is disconnected passively
	elseif evt == "STATE" and result == "CLOSED" then
		linksta = false
		sys.timer_stop(httpget)
		reconn()
	-- Active disconnect (asynchronous after calling link.shut)
	elseif evt == "STATE" and result == "SHUTED" then
		linksta = false
		sys.timer_stop(httpget)
		reconn()
	-- Active disconnect (asynchronous after socketssl.disconnect)
	elseif evt == "DISCONNECT" then
		linksta = false
		sys.timer_stop(httpget)
		--reconn()
		connect()
	end
	-- Other error handling, disconnect the data link, reconnect
	if smatch((type(result)=="string") and result or "","ERROR") then
		-- RECONN_PERIOD seconds after reconnection, do not call reconn, socket state is still CONNECTED, will result in the server has been unable to even
		--sys.timer_start(reconn,RECONN_PERIOD*1000)
		link.shut()
	end
end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? idx: socket idl maintained in socketssl.lua, the same as the first argument passed in when socketssl.connect is invoked, and the program can ignore the non-processing
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
	--The file name in --verifysvrcerts must be the same as the second parameter in linkcss called linkssl.inputcrt
	socketssl.connect(SCK_IDX,PROT,ADDR,PORT,ntfy,rcv,true,{verifysvrcerts={"server.crt"}})
	conning = true
end
--Function name: initcrt
--Function: Create a certificate file
--Parameters: None
--Return Value: None

local function initcrt()
	local fconfig = io.open("/ldata/ca_crt.mp3","rb")
	if not fconfig then print("initcrt err open") return end
	local s = fconfig:read("*a")
	fconfig:close()
	linkssl.inputcrt("cacrt","server.crt",s)
end

initcrt()
connect()
