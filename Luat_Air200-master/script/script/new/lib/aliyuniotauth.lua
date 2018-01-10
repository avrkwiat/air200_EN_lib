-- Define module, import dependent libraries
local base = _G
local string = require"string"
local io = require"io"
local os = require"os"
local sys  = require"sys"
local misc = require"misc"
local link = require"link"
local socket = require"socket"
local crypto = require"crypto"
module(...,package.seeall)


local ssub,schar,smatch,sbyte,slen,sfind = string.sub,string.char,string.match,string.byte,string.len,string.find
local tonumber = base.tonumber


--Ali cloud authentication server
local SCK_IDX,PROT,ADDR,PORT = 3,"TCP","iot-auth.aliyun.com",80
-- Socket connection status with Aliyun authentication server
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
-- Product Identification, Product Key, Device Name, Device Key
local productkey,productsecret,devicename,devicesecret
-- Authentication information
local gauthinfo = 
{
	truststorepath = "/aliyuniot_publicKey.crt",
	otherinfopath = "/aliyuniot_otherInfo.info"
}
-- Get all, get the network parameters, get the certificate parameters
local ALL_SERVER_PARAM,NETWORK_SERVER_PARAM,CERT_SERVER_PARAM = 0,1,2
local gsvrpara
-- The complete packet received from the authentication server, valid data in the body of the message
local rcvbuf,rcvalidbody = "",""

--Function name: print
--Function: print interface, all print in this file will be added aliyuniotauth prefix
--Parameters: None
--Return Value: None

local function print(...)
	base.print("aliyuniotauth",...)
end

local function getdevice(s)
	if s=="name" then
		return devicename or misc.getimei()
	elseif s=="secret" then
		return devicesecret or misc.getsn()
	end
end

--Function name: filexist
--Function: to determine whether the file exists
--Parameters:
--path: file path
--Return Value: Returns true if exists, otherwise nil

local function filexist(path)
	local f = io.open(path,"rb")
	if f then
		f:close()
		return true
	end
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

--Function name: makesign
--Function: Generate signature information
--Parameters:
--typ: parameter type
--Return value: signature information

local function makesign(typ)
	local temp = ""
	if typ==NETWORK_SERVER_PARAM then
		temp = "resFlagip"
	elseif typ==CERT_SERVER_PARAM then
		temp = "resFlagcert"
	end
	local data = "deviceName"..getdevice("name").."productKey"..productkey.."protocolmqtt"..temp.."sdkVersion1.0.0signMethodHmacMD5"
	local signkey = productsecret..getdevice("secret")
	return crypto.hmac_md5(data,slen(data),signkey,slen(signkey))
end

--Function name: postsnd
--Function: Send POST message to the authentication server
--Parameters:
--typ: parameter type
--Return Value: None

local function postsnd(typ)
	local postbody = "/iot/auth?&sign="..makesign(typ).."&productKey="..productkey.."&deviceName="..getdevice("name").."&protocol=mqtt&sdkVersion=1.0.0&signMethod=HmacMD5"
	if typ==NETWORK_SERVER_PARAM then
		postbody = postbody.."&resFlag=ip"
	elseif typ==CERT_SERVER_PARAM then
		postbody = postbody.."&resFlag=cert"
	end
	local posthead = "POST "..postbody.." HTTP/1.1\r\n" .. "Host: "..ADDR.."\r\n\r\n"
	snd(posthead,"POSTSND")
	gsvrpara = typ
end

--Function name: readauthinfo
--Function: Read the authentication information from the file
--Parameters: None
--Return Value: Returns true if successful, nil otherwise

local function readauthinfo()
	local f = io.open(gauthinfo.truststorepath,"rb")
	if not f then print("readauthinfo open truststorepath error") return end
	gauthinfo.pubkey = f:read("*a")
	if not gauthinfo.pubkey then f:close() print("readauthinfo read truststorepath error") return end	
	f:close()
	
	f = io.open(gauthinfo.otherinfopath,"rb")
	if not f then print("readauthinfo open otherinfopath error") return end
	local alldata = f:read("*a")
	if not alldata then f:close() print("readauthinfo read otherinfopath error") return end
	
	gauthinfo.pkVersion,gauthinfo.sign,gauthinfo.deviceId = smatch(alldata,"(%w+)\n(%w+)\n(%w+)")
	f:close()
	if not gauthinfo.pkVersion or not gauthinfo.sign or not gauthinfo.deviceId then		
		print("readauthinfo read otherinfopath parse error")
		return
	end
	gauthinfo.pkVersion = tonumber(gauthinfo.pkVersion)
	
	return true
end

--Function name: writeauthinfo
--Function: Write the authentication information to the file
--Parameters: None
--Return Value: Returns true if the write succeeded, nil otherwise

local function writeauthinfo()
	os.remove(gauthinfo.truststorepath)
	os.remove(gauthinfo.otherinfopath)
	
	local f = io.open(gauthinfo.truststorepath,"wb")
	if not f then print("writeauthinfo open truststorepath error") return end
	if not f:write(gauthinfo.pubkey) then f:close() print("writeauthinfo write truststorepath error") return end
	f:close()
	
	f = io.open(gauthinfo.otherinfopath,"wb")
	if not f then print("writeauthinfo open otherinfopath error") return end
	if not f:write(gauthinfo.pkVersion.."\n") then f:close() print("writeauthinfo write otherinfopath pkVersion error") return end
	if not f:write(gauthinfo.certsign.."\n") then f:close() print("writeauthinfo write otherinfopath certsign error") return end	
	if not f:write(gauthinfo.deviceId) then f:close() print("writeauthinfo write otherinfopath deviceId error") return end
	f:close()
	
	return true
end

--Function name: verifycert
--Function: Verify the legitimacy of the certificate
--Parameters:
--typ: parameter type
--Return Value: True return true, otherwise return nil

local function verifycert(typ)
	local ptype = typ or gsvrpara
	local data,sign,signkey,pubkeyencode
	if ptype==ALL_SERVER_PARAM then
		pubkeyencode = crypto.base64_encode(gauthinfo.pubkey,slen(gauthinfo.pubkey))
		signkey = productsecret..getdevice("secret")
		data = "deviceId"..gauthinfo.deviceId.."pkVersion"..gauthinfo.pkVersion.."pubkey"..pubkeyencode.."servers"..gauthinfo.servers
		sign = crypto.hmac_md5(data,slen(data),signkey,slen(signkey))
		data = "deviceId"..gauthinfo.deviceId.."pkVersion"..gauthinfo.pkVersion.."pubkey"..pubkeyencode
		gauthinfo.certsign = crypto.hmac_md5(data,slen(data),signkey,slen(signkey))
	elseif ptype==CERT_SERVER_PARAM then
		pubkeyencode = crypto.base64_encode(gauthinfo.pubkey,slen(gauthinfo.pubkey))
		signkey = productsecret..getdevice("secret")
		data = "deviceId"..gauthinfo.deviceId.."pkVersion"..gauthinfo.pkVersion.."pubkey"..pubkeyencode
		sign = crypto.hmac_md5(data,slen(data),signkey,slen(signkey))
	elseif ptype==NETWORK_SERVER_PARAM then
		signkey = productsecret..getdevice("secret")
		data = "deviceId"..gauthinfo.deviceId.."servers"..gauthinfo.servers
		sign = crypto.hmac_md5(data,slen(data),signkey,slen(signkey))
	end
	
	if ptype==ALL_SERVER_PARAM and sign==gauthinfo.sign then
		if not writeauthinfo() then print("verifycert writeauthinfo error") return end
	end
	
	print("verifycert",ptype,sign==gauthinfo.sign,sign,gauthinfo.sign)
	return sign==gauthinfo.sign
end

--Function name: parsedatasvr
--Function: Parse data server parameters (host, port, clientid, username)
--Parameters:
--Returns: successful return true, otherwise return nil

local function parsedatasvr()
	local clientid = productkey..":"..gauthinfo.deviceId
	local temp = productkey..productsecret..gauthinfo.deviceId..getdevice("secret")
	local username = crypto.md5(temp,slen(temp))
	local host,port = smatch(gauthinfo.servers,"([%w%.]+):([%d|]+)")
	local ports = {}
	if port then
		local h,t,p = sfind(port,"(%d+)")
		while p do
			table.insert(ports,tonumber(p))
			port = ssub(port,t+1,-1)
			h,t,p = sfind(port,"(%d+)")
		end
	end
	
	print("parsedatasvr",host,#ports,clientid,username)
	if host and #ports>0 and clientid and username then
		sys.dispatch("ALIYUN_DATA_BGN",host,ports,clientid,username)
	end
	
	return host and #ports>0 and clientid and username
end

--Function name: preproc
--Function: Authentication preprocessing
--Parameters: None
--Return Value: None

function preproc()
	print("preproc",linksta)
	if linksta then
		if filexist(gauthinfo.truststorepath) and filexist(gauthinfo.otherinfopath) then
			if readauthinfo() then
				if verifycert(CERT_SERVER_PARAM) then
					postsnd(NETWORK_SERVER_PARAM)
					return
				end
			end
		end
		postsnd(ALL_SERVER_PARAM)
	end
end

--Function name: sndcb
--Function: Data transmission result processing
--Parameters:
--item: table type, {data =, para =}, parameters and data returned by the message, for example, when the second and third parameters passed in when socket.send is called are dat and par, then item = {data = dat, para = par}
--result: bool type, send the result, true is successful, the other is failed
--Return Value: None

local function sndcb(item,result)
	print("sndcb",item.para,result)
	if not item.para then return end
	if item.para=="POSTSND" then
		sys.timer_start(reconn,RECONN_PERIOD*1000)
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
	print("ntfy",evt,result,item)
	-- connection result (asynchronous event after socket.connect call)
	if evt == "CONNECT" then
		conning = false
		--connection succeeded
		if result then
			reconncnt,reconncyclecnt,linksta,rcvbuf,rcvbody = 0,0,true,"",""
			-- Stop the reconnection timer
			sys.timer_stop(reconn)
			preproc()
		--Connection failed
		else
			-- RECONN_PERIOD seconds later reconnect
			sys.timer_start(reconn,RECONN_PERIOD*1000)
		end	
	-- Data transmission result (asynchronous event after socket.send is called)
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
		socket.close(SCK_IDX)
		--reconn()
	-- Active disconnect (asynchronous after calling link.shut)
	elseif evt == "STATE" and result == "SHUTED" then
		linksta = false
		reconn()
	-- Active disconnect (asynchronous after calling socket.disconnect)
	elseif evt == "DISCONNECT" then
		linksta = false
		--reconn()
	end
	-- Other error handling, disconnect the data link, reconnect
	if smatch((base.type(result)=="string") and result or "","ERROR") then
		-- RECONN_PERIOD seconds after reconnection, do not call reconn, socket state is still CONNECTED, will result in the server has been unable to even
		--sys.timer_start(reconn,RECONN_PERIOD*1000)
		link.shut()
	end
end

--Function name: parsevalidbody
--Function: Parse the valid message body returned by the authentication server
--Parameters: None
--Return Value: None

local function parsevalidbody()
	print("parsevalidbody")
	local tjsondata = json.decode(rcvalidbody)
	print("deviceId",tjsondata["deviceId"])
	print("pkVersion",tjsondata["pkVersion"])
	print("pubkey",tjsondata["pubkey"])
	print("servers",tjsondata["servers"])
	print("sign",tjsondata["sign"])
	print("success",tjsondata["success"])
	if tjsondata["success"]~="true" and tjsondata["success"]~=true then print("parsevalidbody success err",tjsondata["success"]) return end
	if tjsondata["deviceId"] then gauthinfo.deviceId = tjsondata["deviceId"] end
	if tjsondata["pkVersion"] then gauthinfo.pkVersion = tonumber(tjsondata["pkVersion"]) end
	if tjsondata["pubkey"] then gauthinfo.pubkey = crypto.base64_decode(tjsondata["pubkey"],slen(tjsondata["pubkey"])) end
	if tjsondata["servers"] then gauthinfo.servers = tjsondata["servers"] end
	if tjsondata["sign"] then gauthinfo.sign = tjsondata["sign"] end
	-- If the parsing is successful
	if verifycert() and parsedatasvr() then
		sys.timer_stop(reconn)
	end
end

--Function name: parse
--Function: Resolve the data returned by the authentication server
--Parameters: None
--Return Value: None

local function parse()
	local headend = sfind(rcvbuf,"\r\n\r\n")
	if not headend then print("parse wait head end") return end
	
	local headstr = ssub(rcvbuf,1,headend+3)
	if not smatch(headstr,"200 OK") then print("parse no 200 OK") return end
	
	local contentflg
	if smatch(headstr,"Transfer%-Encoding: chunked") or smatch(headstr,"Transfer%-Encoding: Chunked") then
		contentflg = "chunk"
	elseif smatch(headstr,"Content%-Length: %d+") then
		contentflg = tonumber(smatch(headstr,"Content%-Length: (%d+)"))
	end
	if not contentflg then print("parse contentflg error") return end
	
	local rcvbody = ssub(rcvbuf,headend+4,-1)
	if contentflg=="chunk" then	
		rcvalidbody = ""
		if not smatch(rcvbody,"0\r\n\r\n") then print("parse wait chunk end") return end
		local h,t,len
		while true do
			h,t,len = sfind(rcvbody,"(%w+)\r\n")
			if len then
				len = tonumber(len,16)
				if len==0 then break end
				rcvalidbody = rcvalidbody..ssub(rcvbody,t+1,t+len)
				rcvbody = ssub(rcvbody,t+len+1,-1)
			else
				print("parse chunk len err ")
				return
			end
		end
	else
		if slen(rcvbody)~=contentflg then print("parse wait content len end") return end
		rcvalidbody = rcvbody
	end
	
	rcvbuf = ""
	parsevalidbody()
	socket.close(SCK_IDX)
end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? idx: socket idx maintained in socket.lua, the same as the first parameter passed in when socket.connect is invoked, and the program can ignore the non-processing
--???????? data: received data
--Return Value: None

function rcv(idx,data)
	print("rcv",data)
	rcvbuf = rcvbuf..data
	parse()
end

--Function name: connect
--Function: to create a connection to the Ali cloud authentication server;
--???????? If the data network is ready, it will immediately connect to the background; otherwise, the connection request will be suspended, and when the data network is ready, it automatically connects to the background
--ntfy: socket state handler
--rcv: socket receive data processing functions
--Parameters: None
--Return Value: None

function connect()
	socket.connect(SCK_IDX,PROT,ADDR,PORT,ntfy,rcv)
	conning = true
end

--Function name: authbgn
--Function: Initiate authentication
--Parameters: None
--Return Value: None

local function authbgn(pkey,psecret,dname,dsecret)
	productkey,productsecret,devicename,devicesecret = pkey,psecret,dname,dsecret
	connect()
end

local procer =
{
	ALIYUN_AUTH_BGN = authbgn,
}

sys.regapp(procer)

