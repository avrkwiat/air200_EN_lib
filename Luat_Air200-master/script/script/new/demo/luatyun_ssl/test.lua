module(...,package.seeall)

require"luatyuniotssl"

local qos1cnt = 1

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
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
	-- Note: Here to control the content of the payload encoding, luatyuniotssl library will not do any encoding conversion of the content
	luatyuniotssl.publish("qos1data",1,pubqos1testackcb,"publish1test_"..qos1cnt)
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

--Function name: connectedcb
--Function: MQTT CONNECT successful callback function
--Parameters: None
--Return Value: None

local function connectedcb()
	print("connectedcb")
	-- Post a message with a qos of 1
	pubqos1test()
end

-- Registered MQTT CONNECT successful callbacks and received PUBLISH message callbacks
luatyuniotssl.regcb(connectedcb,rcvmessagecb)

