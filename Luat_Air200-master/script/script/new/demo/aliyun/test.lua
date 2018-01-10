module(...,package.seeall)

require"aliyuniot"
-- Ali cloud created on the key and secret, the user if you create a project in Aliyun, according to their own project information, modify these two values
local PRODUCT_KEY,PRODUCT_SECRET = "1000163201","4K8nYcT4Wiannoev"

-- In addition to the two messages above, DEVICE_NAME and DEVICE_SECRET are required
--lib will use device IMEI and SN as DEVICE_NAME and DEVICE_SECRET, so when adding a device to Aliyun, DEVICE_NAME will use IMEI and then write the generated DEVICE_SECRET as SN into the device

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
	
	-- Note: Here to control the content of the payload encoding, aliyuniot library will not payload content of any encoding conversion
	aliyuniot.publish("/"..PRODUCT_KEY.."/"..misc.getimei().."/update","qos1data",1,pubqos1testackcb,"publish1test_"..qos1cnt)
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


--Function name: connectedcb
--Function: MQTT CONNECT successful callback function
--Parameters: None
--Return Value: None

local function connectedcb()
	print("connectedcb")
	-- Subscribe to the theme
	aliyuniot.subscribe({{topic="/"..PRODUCT_KEY.."/"..misc.getimei().."/get",qos=0}, {topic="/"..PRODUCT_KEY.."/"..misc.getimei().."/get",qos=1}}, subackcb, "subscribegetopic")
	
	-- Registration event callback function, MESSAGE event that received a PUBLISH message
	aliyuniot.regevtcb({MESSAGE=rcvmessagecb})
	
	-- Post a message with a qos of 1
	pubqos1test()
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

aliyuniot.config(PRODUCT_KEY,PRODUCT_SECRET)
aliyuniot.regcb(connectedcb,connecterrcb)
