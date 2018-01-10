
--Module name: base station information latitude and longitude
--Module function: connect the base station to locate the background, report multi-base station to the background, back to latitude and longitude
--Last modified: 2017.05.05

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local table = require"table"
local lpack = require"pack"
local bit = require"bit"
local sys  = require"sys"
local link = require"link"
local misc = require"misc"
local common = require"common"
local net = require"net"
module(...)

-- Load common global functions to local

local print,tonumber,pairs = base.print,base.tonumber,base.pairs
local slen,sbyte,ssub,srep = string.len,string.byte,string.sub,string.rep

local PROTOCOL,SERVER,PORT = "UDP","bs.openluat.com","12411"

--GET command waiting time

local CMD_GET_TIMEOUT = 5000
-- Incorrect package (wrong format) Re-acquire after some time

local ERROR_PACK_TIMEOUT = 5000
-- The number of GET command retries per GET

local CMD_GET_RETRY_TIMES = 3
--socket id
local lid
-- connection status, the connection has been destroyed as false or nil, the rest is true

local linksta,usercb,userlocstr
--getretries: Get the number of times each package has been retry
local getretries = 0

--Function name: print
--Function: The print interface, all printouts in this file will be prefixed with lbsloc
--Parameters: None
--Return Value: None

local function print(...)
	base.print("lbsloc",...)
end


--Function name: retry
--Function: Retry action during request
--Parameters:
--Return Value: None

local function retry()
	print("retry",getretries)
	-- Retry times plus 1

	getretries = getretries + 1
	if getretries < CMD_GET_RETRY_TIMES then
		-- The number of retries has not been reached, continue to retry

		reqget()
	else
		-- Retries exceeded, upgrade failed

		reqend(false)
	end
end

local function encellinfo(s)
	local ret,t,mcc,mnc,lac,ci,rssi,k,v,m,n,cntrssi = "",{}
	print("encellinfo",s)
	for mcc,mnc,lac,ci,rssi in string.gmatch(s,"(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+);") do
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

	return string.char(#t)..ret
end

local function bcd(d,n)
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

	local s = string.char(base.unpack(t))

	l = slen(s)

	if l < n then
		s = s .. string.rep("\255",n-l)
	elseif l > n then
		s = ssub(s,1,n)
	end

	return s
end

--460.01.6311.49234.30;460.01.6311.49233.23;460.02.6322.49232.18;
local function getcellcb(s)
	print("getcellcb")
	local status = (misc.isnvalid() and 1 or 0) + (userlocstr and 1 or 0)*2
	local dsecret = ""
	if misc.isnvalid() then
		dsecret = lpack.pack("bA",slen(misc.getsn()),misc.getsn())
	end
	base.assert(base.PRODUCT_KEY,"undefine PRODUCT_KEY in main.lua")
	link.send(lid,lpack.pack("bAbAAA",slen(base.PRODUCT_KEY),base.PRODUCT_KEY,status,dsecret,bcd(misc.getimei(),8),encellinfo(s)))
	-- Start the "CMD_GET_TIMEOUT Milliseconds Retry" timer

	sys.timer_start(retry,CMD_GET_TIMEOUT)
end

--Function name: reqget
--Function: send base station information to the server
--Parameters: None
--Return Value: None

function reqget()
	print("reqget")
	net.getmulticell(getcellcb)
end

--Function name: reqend
--Function: Get the end
--Parameters:
--suc: As a result, true is successful and the rest is failed
--Return Value: None

function reqend(suc)
	print("reqend",suc)
	-- stop retry timer

	sys.timer_stop(retry)
	-- Disconnect

	link.close(lid)
	linksta = false
	if not suc then
		local tmpcb=usercb
		usercb=nil
		sys.timer_stop(tmoutfnc)
		if tmpcb then tmpcb(4) end
	end	
end

--Function name: nofity
--Function: Socket state processing function
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? evt: message event type
--val: message event parameter
--Return Value: None

local function nofity(id,evt,val)
	--connection result

	if evt == "CONNECT" then
		--connection succeeded

		if val == "CONNECT OK" then
			getretries = 0
			reqget()
		--Connection failed

		else
			reqend(false)
		end
	-- The connection is disconnected passively

	elseif evt == "STATE" and (val=="CLOSED" or val=="SHUTED") then
		reqend(false)
	end
end

local function unbcd(d)
	local byte,v1,v2
	local t = {}

	for i=1,slen(d) do
		byte = sbyte(d,i)
		v1,v2 = bit.band(byte,0x0f),bit.band(bit.rshift(byte,4),0x0f)

		if v1 == 0x0f then break end
		table.insert(t,v1)

		if v2 == 0x0f then break end
		table.insert(t,v2)
	end

	return table.concat(t)
end

local function trans(lat,lng)
	local la,ln = lat,lng
	if slen(lat)>10 then
		la = ssub(lat,1,10)
	elseif slen(lat)<10 then
		la = lat..srep("0",10-slen(lat))
	end
	if slen(lng)>10 then
		ln = ssub(lng,1,10)
	elseif slen(lng)<10 then
		ln = lng..srep("0",10-slen(lng))
	end

--0.XXXXXXX degrees multiplied by 60 is the point, our Luat does not support decimals, according to the following format:
--0.XXXXXXX * 60 = XXXXXXX * 60/10000000 = XXXXXXX * 6/1000000

--For example, 0.9999999 degrees = 9999999 * 6/1000000 = 59.999994 points


--The final test in accordance with the following points:
--(XXXXXXX * 6/1000000) .. ".." .. (XXXXXXX * 6% 1000000) Get the string type of points,
--For example, the final result of 0.9999999 degrees is 59.999994 points for the string type

	local lam1,lam2 = tonumber(ssub(la,4,-1))*6/1000000,tonumber(ssub(la,4,-1))*6%1000000
	if slen(lam1)<2 then lam1 = srep("0",2-slen(lam1))..lam1 end
	if slen(lam2)<6 then lam2 = srep("0",6-slen(lam2))..lam2 end
	
	local lnm1,lnm2 = tonumber(ssub(ln,4,-1))*6/1000000,tonumber(ssub(ln,4,-1))*6%1000000
	if slen(lnm1)<2 then lnm1 = srep("0",2-slen(lnm1))..lnm1 end
	if slen(lnm2)<6 then lnm2 = srep("0",6-slen(lnm2))..lnm2 end
	
	return ssub(la,1,3).."."..ssub(la,4,-1),ssub(ln,1,3).."."..ssub(ln,4,-1),ssub(la,1,3)..lam1.."."..lam2,ssub(ln,1,3)..lnm1.."."..lnm2
end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? data: received data
--Return Value: None

local function rcv(id,s)
	print("rcv",slen(s),(slen(s)<270) and common.binstohexs(s) or "")
	if slen(s)<11 then return end
	reqend(true)
	local tmpcb=usercb
	usercb=nil
	sys.timer_stop(tmoutfnc)
	if sbyte(s,1)~=0 then
		if tmpcb then tmpcb(3) end
	else
		local lat,lng,latdm,lngdm = trans(unbcd(ssub(s,2,6)),unbcd(ssub(s,7,11)))
		if tmpcb then tmpcb(0,lat,lng,common.ucs2betogb2312(ssub(s,13,-1)),latdm,lngdm) end
	end	
end

function tmoutfnc()
	print("tmoutfnc")
	local tmpcb=usercb
	usercb=nil
	if tmpcb then tmpcb(2) end
end

--Function name: request
--Function: Initiated Get latitude and longitude request
--Parameters:
--???????? cb: get the latitude and longitude or timeout after the callback function, the call form: cb (result, lat, lng, location)
--locstr: whether to support the position string return, true support, false or nil not supported, the default is not supported
--tmout: Get latitude and longitude timeout, in seconds, the default 25 seconds
--Return Value: None

function request(cb,locstr,tmout)
	print("request",cb,tmout,locstr,usercb,linksta)
	if usercb then print("request usercb err") cb(1) end
	if not linksta then
		lid = link.open(nofity,rcv,"lbsloc")
		link.connect(lid,PROTOCOL,SERVER,PORT)
		linksta = true
	end
	sys.timer_start(tmoutfnc,(tmout and tmout*1000 or ((CMD_GET_RETRY_TIMES+2)*CMD_GET_TIMEOUT)))
	usercb,userlocstr = cb,locstr
end
