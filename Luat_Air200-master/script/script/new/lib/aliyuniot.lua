-- Define module, import dependent libraries
local base = _G
local string = require"string"
local sys  = require"sys"
local mqtt = require"mqtt"
require"aliyuniotauth"
module(...,package.seeall)

--mqtt client object, data server address, data server port table
local mqttclient,gaddr,gports,gclientid,gusername
-- The index currently used in the gport table
local gportidx = 1
local gconnectedcb,gconnecterrcb

--Function name: print
--Function: Print Interface, all prints in this file will be prefixed with aliyuniot
--Parameters: None
--Return Value: None

local function print(...)
	base.print("aliyuniot",...)
end

--Function name: sckerrcb
--Function: SOCKET failed callback function
--Parameters:
--r: string type, failure reason value
--CONNECT: mqtt internal socket always failed to connect, no longer try to reconnect automatically
--Return Value: None

local function sckerrcb(r)
	print("sckerrcb",r,gportidx,#gports)
	if r=="CONNECT" then
		if gportidx<#gports then
			gportidx = gportidx+1
			connect(true)
		else
			sys.restart("aliyuniot sck connect err")
		end
	end
end

function connect(change)
	if change then
		mqttclient:change("TCP",gaddr,gports[gportidx])
	else
		-- Create a mqtt client
		mqttclient = mqtt.create("TCP",gaddr,gports[gportidx])
	end
	-- Configure testament parameters, if necessary, open the following line of code, and according to their own needs will be adjusted parameters
	--mqttclient: configwill (1,0,0, "/ willtopic", "will payload")
	-- Connect mqtt server
	mqttclient:connect(gclientid,240,gusername,"",gconnectedcb,gconnecterrcb,sckerrcb)
end

--Function name: databgn
--Function: The authentication server succeeds in authentication, allowing the device to connect to the data server
--Parameters: None
--Return Value: None

local function databgn(host,ports,clientid,username)
	gaddr,gports,gclientid,gusername = host or gaddr,ports or gports,clientid,username
	gportidx = 1
	connect()
end

local procer =
{
	ALIYUN_DATA_BGN = databgn,
}

sys.regapp(procer)


--Function name: config
--Function: Configure Aliyun IoT product information and device information
--Parameters:
--productkey: string type, product ID, required parameters
--productsecret: string type, product key, required parameters
--Return Value: None

function config(productkey,productsecret)
	sys.dispatch("ALIYUN_AUTH_BGN",productkey,productsecret)
end

function regcb(connectedcb,connecterrcb)
	gconnectedcb,gconnecterrcb = connectedcb,connecterrcb
end

function subscribe(topics,ackcb,usertag)
	mqttclient:subscribe(topics,ackcb,usertag)
end

function regevtcb(evtcbs)
	mqttclient:regevtcb(evtcbs)
end

function publish(topic,payload,qos,ackcb,usertag)
	mqttclient:publish(topic,payload,qos,ackcb,usertag)
end
