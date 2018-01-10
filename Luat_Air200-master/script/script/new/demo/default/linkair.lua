
--Module Name: mqtt client application processing module
--Module function: connect to server, send login message, report multi-base station information regularly
--Last modified: 2017.03.30


require"misc"
require"mqtt"
module(...,package.seeall)

local lpack = require"pack"
local ssub,schar,smatch,sbyte,slen,sgmatch,sgsub,srep = string.sub,string.char,string.match,string.byte,string.len,string.gmatch,string.gsub,string.rep

-- whether to support gps
local gpsupport = false

-- If gps is supported, turn on gps
if gpsupport then
	require"agps"
	require"gps"
	gps.init()
	gps.open(gps.DEFAULT,{cause="linkair"})
end

--server
local PROT,ADDR,PORT = "TCP","lbsmqtt.airm2m.com",1884
local mqttclient



--Function name: print
--Function: Print Interface, all links in this file will be prefixed with linkair
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("linkair",...)
end

--Function name: pubqos0loginsndcb
--Function: "Post a message qos 0" (login message), send the result of the callback function
--Parameters:
--usertag: The usertag passed in when mqttclient: publish is called
--result: true means the sending succeeded, false or nil failed to be sent
--Return Value: None

local function pubqos0loginsndcb(usertag,result)
	print("pubqos0loginsndcb",usertag,result)
	sys.timer_start(pubqos0login,20000)
end

function bcd(d,n)
	local l = slen(d or "")
	local num
	local t = {}

	for i=1,l,2 do
		num = tonumber(ssub(d,i,i+1),16)

		if i == l then
			num = 0xf0+num
		else
			num = (num%0x10)*0x10 + num/0x10
		end

		table.insert(t,num)
	end

	local s = schar(_G.unpack(t))

	l = slen(s)

	if l < n then
		s = s .. srep("\255",n-l)
	elseif l > n then
		s = ssub(s,1,n)
	end

	return s
end


--Function name: pubqos0login
--Function: Publish a qos 0 message, login message
--Parameters: None
--Return Value: None

function pubqos0login()
	local payload = lpack.pack(">bbHHbHHbHAbHbbHAbHAbHA",
								14,
								0,2,22,
								1,2,300,
								2,2,bcd(sgsub(_G.VERSION,"%.",""),2),
								3,1,gpsupport and 1 or 0,
								4,slen(sim.geticcid()),sim.geticcid(),
								8,slen(_G.PROJECT),_G.PROJECT,
								13,slen(sim.getimsi()),sim.getimsi())
	mqttclient:publish("/v1/device/"..misc.getimei().."/devdata",payload,0,pubqos0loginsndcb)
end



--Function name: pubqos0locsndcb
--Function: "Post a message with a qos of 0" (location message), callback function to send the result
--Parameters:
--usertag: The usertag passed in when mqttclient: publish is called
--result: true means the sending succeeded, false or nil failed to be sent
--Return Value: None

local function pubqos0locsndcb(usertag,result)
	print("pubqos0locsndcb",usertag,result)
	sys.timer_start(pubqos0loc,60000)
end


--Function name: encellinfoext
--Function: Extended base station positioning information packet processing
--Parameters: None
--Return Value: Extended base station location information packet string

local function encellinfoext()
	local info,ret,t,mcc,mnc,lac,ci,rssi,k,v,m,n,cntrssi = net.getcellinfoext(),"",{}
	print("encellinfoext",info)
	for mcc,mnc,lac,ci,rssi in sgmatch(info,"(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+);") do
		mcc,mnc,lac,ci,rssi = tonumber(mcc),tonumber(mnc),tonumber(lac),tonumber(ci),(tonumber(rssi) > 31) and 31 or tonumber(rssi)
		local handle = nil
		for k,v in pairs(t) do
			if v.lac == lac and v.mcc == mcc and v.mnc == mnc then
				if #v.rssici < 8 then
					table.insert(v.rssici,{rssi=rssi,ci=ci})
				end
				handle = true
				break
			end
		end
		if not handle then
			table.insert(t,{mcc=mcc,mnc=mnc,lac=lac,rssici={{rssi=rssi,ci=ci}}})
		end
	end
	for k,v in pairs(t) do
		ret = ret .. lpack.pack(">HHb",v.lac,v.mcc,v.mnc)
		for m,n in pairs(v.rssici) do
			cntrssi = bit.bor(bit.lshift(((m == 1) and (#v.rssici-1) or 0),5),n.rssi)
			ret = ret .. lpack.pack(">bH",cntrssi,n.ci)
		end
	end

	return schar(#t)..ret
end

local function getstatus()
	local t = {}

	t.shake = 0
	t.charger = 0
	t.acc = 0
	t.gps = gpsupport and 1 or 0
	t.sleep = 0
	t.volt = misc.getvbatvolt()
	t.fly = 0
	t.poweroff = 0
	t.poweroffreason = 0
	return t
end

local function getgps()
	local t = {}
	if gpsupport then
		print("getgps:",gps.getgpslocation(),gps.getgpscog(),gps.getgpsspd())
		t.fix = gps.isfix()
		t.lng,t.lat = smatch(gps.getgpslocation(),"[EW]*,(%d+%.%d+),[NS]*,(%d+%.%d+)")
		t.lng,t.lat = t.lng or "",t.lat or ""
		t.cog = gps.getgpscog()
		t.spd = gps.getgpsspd()
	end
	return t
end

local function getgpstat()
	local t = {}
	if gpsupport then
		t.satenum = gps.getgpssatenum()
	end
	return t
end


--Function name: enstat
--Function: basic status information packet processing
--Parameters: None
--Return Value: The basic status information packet string

local function enstat()	
	local stat = getstatus()
	local rssi = net.getrssi()
	local gpstat = getgpstat()
	local satenum = gpstat.satenum or 0

	local n1 = stat.shake + stat.charger*2 + stat.acc*4 + stat.gps*8 + stat.sleep*16+stat.fly*32+stat.poweroff*64
	rssi = rssi > 31 and 31 or rssi
	satenum = satenum > 7 and 7 or satenum
	local n2 = rssi + satenum*32
	return lpack.pack(">bbH",n1,n2,stat.volt)
end

local function enlnla(v,s)
	if not v then return common.hexstobins("FFFFFFFFFF") end
	
	local v1,v2 = smatch(s,"(%d+)%.(%d+)")

	if slen(v1) < 3 then v1 = srep("0",3-slen(v1)) .. v1 end

	return bcd(v1..v2,5)
end


--Function name: pubqos0loc
--Function: Publish a message qos 0, location message
--Parameters: None
--Return Value: None

function pubqos0loc()
	local payload
	if gpsupport then
		local t = getgps()
		lng = enlnla(t.fix,t.lng)
		lat = enlnla(t.fix,t.lat)
		payload = lpack.pack(">bAAHbAbA",7,lng,lat,t.cog,t.spd,encellinfoext(),net.getta(),enstat())
	else
		payload = lpack.pack(">bAbA",5,encellinfoext(),net.getta(),enstat())
	end
	mqttclient:publish("/v1/device/"..misc.getimei().."/devdata",payload,0,pubqos0locsndcb)
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
--topic: the subject of the message
--payload: message load
--qos: message quality level
--Return Value: None

local function rcvmessagecb(topic,payload,qos)
	print("rcvmessagecb",topic,common.binstohexs(payload),qos)
	if slen(payload)>2 and ssub(payload,1,2)==common.hexstobins("3C00") then
		sys.timer_stop(pubqos0login)
	end
end


--Function name: connectedcb
--Function: MQTT CONNECT successful callback function
--Parameters: None
--Return Value: None

local function connectedcb()
	print("connectedcb")	
	-- Subscribe to the theme
	mqttclient:subscribe({{topic="/v1/device/"..misc.getimei().."/set",qos=0}},subackcb,"subscribetest")
	-- Registration event callback function, MESSAGE event that received a PUBLISH message
	mqttclient:regevtcb({MESSAGE=rcvmessagecb})	
	-- Issue a message with qos 0, log in to the message
	pubqos0login()	
	-- Post a message with a qos of 1 and a location message
	pubqos0loc()
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


--Function name: imeirdy
--Function: IMEI read successfully, after successful, to create mqtt client, connect to the server, because of the use of IMEI number
--Parameters: None
--Return Value: None

local function imeirdy()
	-- Create a mqtt client
	mqttclient = mqtt.create(PROT,ADDR,PORT)
	-- Connect mqtt server
	mqttclient:connect(misc.getimei(),600,"user","password",connectedcb,connecterrcb)
end

local procer =
{
	IMEI_READY = imeirdy,
}

-- Registered message processing functions
sys.regapp(procer)
-- Set 30 seconds to inquire about a base station information
net.setcengqueryperiod(30000)
