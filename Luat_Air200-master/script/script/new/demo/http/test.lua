module(...,package.seeall)
require"misc"
require"http"
require"common"


--Features: http short connection, first of all need to provide ADDR and PORT, the data is the client needs to connect the client
--1. Need to call the function, to set the url, add the header, add the entity, here note that adding the first Host, ADDR and PORT in front of the same, the use of long socket connection
--2. Call request function, the function is necessary to send the message to be called
--3.rcvcb function is to receive the callback function, returns the result, status code, the first (a table), entity, the function is a custom function, the customer can define their own needs
--4. After receiving the data, if there is no reprocessing within five seconds, it will restart and will reconnect

local ssub,schar,smatch,sbyte,slen = string.sub,string.char,string.match,string.byte,string.len
-- When testing, please first write the IP address and port, the first written behind should be consistent with the host here, the following values ??are the default value
local ADDR,PORT ="www.linuxhub.org",80
-- The address used to test the POST method
--local ADDR,PORT ="www.luam2m.com",80
local httpclient


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end



--Function name: rcvcb
--Function: Receive callback function, user-defined to receive parameters to operate
--Parameters: result: 0: The received entity length is the same as the actual one. Correct output 1: No entity 2: The entity is beyond the actual entity, error is not output entity content 3: Receive timeout 4: Indicates that the server is in split transport mode
--return value:

local function rcvcb(result,statuscode,head,body)
	print("resultrcvcb: ",result)  
	print("statuscodercvcb: ",statuscode)
	if	head==nil	then	print("headrcvcb:	nil")
	else
		print("headrcvcb:")
		
		-- Traversal print out all the head, the key is the first name, the key corresponding to the value of the first field value
		for k,v in pairs(head) do		
			print(k..": "..v)
		end
	end
	print("bodyrcvcb:")
	print(body)
	httpclient:disconnect(discb)
end



--Function name: connectedcb
--Function: SOCKET connected successful callback function
--Parameters:
--return value:

local function connectedcb()
	
	--GET default method
	-- Set the URL
	httpclient:seturl("/")
	
	-- Add the first, pay attention to the Host header value and addr, port above
	httpclient:addhead("Host","112.29.250.194")
	--	httpclient:addhead("Connection","keep-alive")
	
	-- Add entity content
	httpclient:setbody("")
	
	-- Call this function to send a message, you need to use the POST method, the GET to POST
    httpclient:request("GET",rcvcb)
end 


--Function name: sckerrcb
--Function: SOCKET failed callback function
--Parameters:
--r: string type, failure reason value
--CONNECT: socket has been connected failed, no longer try to reconnect automatically
--Return Value: None

local function sckerrcb(r)
	print("sckerrcb",r)
end

--Function name: connect
--Function: Connect to the server
--parameter:
--connectedcb: connection successful callback function
--sckerrcb: http lib socket has been reconnection failure, it will not automatically restart the software, but call sckerrcb function
--return:

local function connect()
	httpclient:connect(connectedcb,sckerrcb)
end

--Function name: discb
--Function: callback after HTTP connection is disconnected
--Parameters: None
--Return Value: None

function discb()
	print("http discb")
	
	-- 20 seconds to re-establish the HTTP connection
	sys.timer_start(connect,20000)
end


--Function name: http_run
--Function: Create http client and connect
--Parameters: None
--Return Value: None

function http_run()
	
	-- Because the http protocol must be based on the "TCP" protocol, there is no need to pass PROT parameters
	httpclient=http.create(ADDR,PORT)	
	-- establish http connection
	connect()	
end


-- Call the function to run
http_run()



