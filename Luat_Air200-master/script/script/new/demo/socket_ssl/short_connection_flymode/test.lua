require"socketssl"
require"misc"
module(...,package.seeall)


--This example is a short connection, send data, enter the flight mode, and then regularly exit the flight mode and then send the data, so cycle
--Functional Requirements:
--1, connect the background to send GET command to the background, the timeout period is 2 minutes, 2 minutes if it fails, will always try, send successfully or after the timeout have entered the flight mode;
--2, after entering the flight mode 5 minutes, exit the flight mode, and then continue to the first step
--Loop the above two steps
--2, received the background data, print out in the rcv function
--Please set up your own test server, and modify the following PROT, ADDR, PORT, support for domain names and IP addresses

local ssub,schar,smatch,sbyte,slen = string.sub,string.char,string.match,string.byte,string.len
-- Please set up your own server test
local SCK_IDX,PROT,ADDR,PORT = 1,"TCP","36.7.87.100",4433
-- Each connection to the background, there will be the following exception handling
-- Actions in a connection cycle: If the connection to the background fails, a reconnection will be attempted with a reconnection interval of RECONN_PERIOD seconds and a maximum of RECONN_MAX_CNT times
-- If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
-- If no consecutive RECONN_CYCLE_MAX_CNT connection cycles are successful, restart the software
local RECONN_MAX_CNT,RECONN_PERIOD,RECONN_CYCLE_MAX_CNT,RECONN_CYCLE_PERIOD = 3,5,1,20
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


--Function name: httpgetimeout
--Function: GET command send timeout processing, direct access to flight mode
--Parameters: None
--Return Value: None

local function httpgetimeout()
	print("httpgetimeout")
	httpgetcb(true)
end

--Function name: httpget
--Function: send GET command to the background
--Parameters: None
--Return Value: None

function httpget()
	print("httpget")	
	-- call the sending interface is successful, not the data is sent successfully, the data is sent successfully, notify in SEND event in ntfy
	if snd(sndata,"HTTPGET") then
		-- Set the 2-minute timer, if the data is not successfully transmitted for 2 minutes, enter the flight mode directly
		sys.timer_start(httpgetimeout,120000)
	-- Calling the sending interface failed to do reconnection
	else
		httpgetcb()
	end	
end

--Function name: httpgetcb
--Function: The GET command sends a callback, send successfully or overtime, will enter the flight mode, start 5 minutes of "exit flight mode, connect the background" timer
--Parameters:
--???????? result: bool type, the results of the transmission or whether overtime, true for the success or overtime, the other failure
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socketssl.send is called are dat and par respectively, item = {data = dat, para = par}
--Return Value: None

function httpgetcb(result,item)
	print("httpgetcb",result)
	if result then
		socketssl.disconnect(SCK_IDX)
		link.shut()
		misc.setflymode(true)
		sys.timer_start(connect,300000)
		sys.timer_stop(httpgetimeout)
	else
		sys.timer_start(reconn,RECONN_PERIOD*1000)
	end
end

--Function name: sndcb
--Function: Send data result event processing
--Parameters:
--???????? result: bool type, the result of the message event, true is successful, others are failed
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socketssl.send is called are dat and par respectively, item = {data = dat, para = par}
--Return Value: None

local function sndcb(item,result)
	print("sndcb",item.para,result)
	if not item.para then return end
	if item.para=="HTTPGET" then
		httpgetcb(result,item)
	end	
end

--Function name: reconn
--Function: Reconnection background processing
--???????? A connection cycle of action: If the connection fails the background, will try to reconnect, reconnect interval RECONN_PERIOD seconds, up to reconnect RECONN_MAX_CNT times
--???????? If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
--???????? If consecutive RECONN_CYCLE_MAX_CNT secondary connection cycles are not connected successfully, then restart the software
--Parameters: None
--Return Value: None

function reconn()
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
			reconncnt,reconncyclecnt = 0,0
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
	-- The connection is disconnected passively
	elseif evt == "STATE" and result == "CLOSED" then
		-- Supplement custom function code
	-- Active disconnect (asynchronous after calling link.shut)
	elseif evt == "STATE" and result == "SHUTED" then
		-- Supplement custom function code
	-- Active disconnect (asynchronous after socketssl.disconnect)
	elseif evt == "DISCONNECT" then
		if not sys.timer_is_active(connect) then
			connect()
		end
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
--???????? idx: socket idl maintained in socketssl.lua, the same as the first argument passed in when socketssl.connect is invoked, and the program can ignore the non-processing
--???????? data: received data
--Return Value: None

function rcv(idx,data)
	print("rcv",data)
end

--F-unction name: connect
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
	local fconfig = io.open("/ldata/servercrt.mp3","rb")
	if not fconfig then print("initcrt err open") return end
	local s = fconfig:read("*a")
	fconfig:close()
	linkssl.inputcrt("cacrt","server.crt",s)
end

initcrt()
connect()
