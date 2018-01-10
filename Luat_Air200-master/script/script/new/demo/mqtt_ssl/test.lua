require"misc"
require"mqttssl"
require"common"
module(...,package.seeall)

local ssub,schar,smatch,sbyte,slen = string.sub,string.char,string.match,string.byte,string.len
-- Please set up your own server test
local PROT,ADDR,PORT = "TCP","mqtt.test.com",18883
local mqttclient


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

local qos0cnt,qos1cnt = 1,1

--Function name: pubqos0testsndcb
--Function: "Post a qos message for 0" Send the result of the callback function
--Parameters:
--usertag: The usertag passed in when mqttclient: publish is called
--result: true means the sending succeeded, false or nil failed to be sent
--Return Value: None

local function pubqos0testsndcb(usertag,result)
	print("pubqos0testsndcb",usertag,result)
	sys.timer_start(pubqos0test,10000)
	qos0cnt = qos0cnt+1
end

--Function name: pubqos0test
--Function: Publish a qos 0 message
--Parameters: None
--Return Value: None

function pubqos0test()
	-- Note: here to control the contents of the payload encoding, mqtt library payload content will not do any encoding conversion
	mqttclient:publish("/qos0topic","qos0data",0,pubqos0testsndcb,"publish0test_"..qos0cnt)
end


--Function name: pubqos1testackcb
--Function: PUBACK callback function is received after a message of 1 qos is released
--Parameters:
--usertag: The usertag passed in when mqttclient: publish is called
--result: true indicates that the publication succeeded, false or nil failed
--Return Value: None

local function pubqos1testackcb(usertag,result)
	print("pubqos1testackcb",usertag,result)
	sys.timer_start(pubqos1test,20000)
	qos1cnt = qos1cnt+1
end

--Function name: pubqos1test
--Function: Post a qos message
--Parameters: None
--Return Value: None

function pubqos1test()
	-- Note: here to control the contents of the payload encoding, mqtt library payload content will not do any encoding conversion
	mqttclient:publish("/中文qos1topic","中文qos1data",1,pubqos1testackcb,"publish1test_"..qos1cnt)
end

--Function name: subackcb
--Function: SUBACK callback function received after MQTT SUBSCRIBE
--Parameters:
--usertag: usertag passed in when calling mqttclient: subscribe
--result: true indicates that the subscription is successful, false or nil indicates a failure
--Return Value: None

local function subackcb(usertag,result)
	print("subackcb",usertag,result)
end

--Function name: rcvmessage
--Function: Callback function when PUBLISH message is received
--Parameters:
--topic: Message Topic (gb2312 encoding)
--payload: message load (the original encoding, what is the payload of the received content, what is the content, did not do any encoding conversion)
--qos: message quality level
--Return Value: None

local function rcvmessagecb(topic,payload,qos)
	print("rcvmessagecb",topic,payload,qos)
end

--Function name: discb
--Function: Callback after MQTT connection is broken
--Parameters: None
--Return Value: None

local function discb()
	print("discb")
	-- 20 seconds to re-establish the MQTT connection
	sys.timer_start(connect,20000)
end

--Function name: disconnect
--Function: Disconnect MQTT
--Parameters: None
--Return Value: None

local function disconnect()
	mqttclient:disconnect(discb)
end


--Function name: connectedcb
--Function: MQTT CONNECT successful callback function
--Parameters: None
--Return Value: None

local function connectedcb()
	print("connectedcb")
	-- Subscribe to the theme
	mqttclient:subscribe({{topic="/event0",qos=0}, {topic="/中文event1",qos=1}}, subackcb, "subscribetest")
	-- Registration event callback function, MESSAGE event that received a PUBLISH message
	mqttclient:regevtcb({MESSAGE=rcvmessagecb})
	-- Post a message with a 'qos' of 0
	pubqos0test()
	-- Post a message with a 'qos' of 1
	pubqos1test()
	-- Automatically disconnect the MQTT connection after 20 seconds
	--sys.timer_start(disconnect,20000)
end

--Function name: connecterrcb
--Function: MQTT CONNECT failed callback function
--Parameters:
--r: Failure reason value
--1: Connection Refused: unacceptable protocol version
--2: Connection Refused: identifier rejected
--3: Connection Refused: server unavailable
--4: Connection Refused: bad user name or password
--5: Connection Refused: not authorized
--Return Value: None

local function connecterrcb(r)
	print("connecterrcb",r)
end

--Function name: sckerrcb
--Function: SOCKET abnormal callback function (Note: Here is a way to restore anomalies <enter the flight mode, exit Fetion mode after half a minute>, if you can not meet their own needs, you can do exception handling)
--Parameters:
--r: string type, failure reason value
--CONNECT: mqtt internal socket always failed to connect, no longer try to reconnect automatically
--SVRNODATA: mqtt internal, three times the KEEP ALIVE time + half a minute, the terminal and the server without any data communication, then think there is abnormal communication
--Return Value: None

local function sckerrcb(r)
	print("sckerrcb",r)
	misc.setflymode(true)
	sys.timer_start(misc.setflymode,30000,false)
end

function connect()
	-- Connect mqtt server
	-- mqtt lib, if socket abnormal, the default will automatically restart the software
	-- Note sckerrcb parameters, if you open the commented sckerrcb, mqtt lib socket abnormal, no longer automatically restart the software, but call sckerrcb function
	mqttclient:connect(misc.getimei(),240,"user","password",connectedcb,connecterrcb--[[,sckerrcb]])
end

local function statustest()
	print("statustest",mqttclient:getstatus())
end

--Function name: imeirdy
--Function: IMEI read successfully, after successful, to create mqtt client, connect to the server, because of the use of IMEI number
--Parameters: None
--Return Value: None

local function imeirdy()
	-- Create a mqtt client, the default version of the MQTT protocol is 3.1, if you want to use 3.1.1, open the following comment - [[, "3.1.1"]]
	mqttclient = mqttssl.create(PROT,ADDR,PORT,nil--[[,"3.1.1"]])
	-- Configure testament parameters, if necessary, open the following line of code, and according to their own needs will be adjusted parameters
	--mqttclient:configwill(1,0,0,"/willtopic","will payload")
	-- Configure the clean session flag, if necessary, open the following line of code, and configure cleansession according to their own needs; if not configured, the default is 1
	--mqttclient:setcleansession(0)
	-- Query client status test
	--sys.timer_loop_start(statustest,1000)
	connect()
end

local procer =
{
	IMEI_READY = imeirdy,
}
-- Registered message processing functions
sys.regapp(procer)
