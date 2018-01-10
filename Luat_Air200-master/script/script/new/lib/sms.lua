
--Module Name: SMS function
--Module functions: SMS send, receive, read, delete
--Last modified: 2017.02.13

-- Define module, import dependent libraries
local base = _G
local string = require "string"
local table = require "table"
local sys = require "sys"
local ril = require "ril"
local common = require "common"
local bit = require"bit"
module("sms")

-- Load common global functions to local

local print = base.print
local tonumber = base.tonumber
local dispatch = sys.dispatch
local req = ril.request

--ready: whether the underlying SMS function is ready

local ready,isn,tlongsms = false,255,{}
local ssub,slen,sformat,smatch = string.sub,string.len,string.format,string.match
local tsend={}

--Function name: _send
--Function: send sms (internal interface)
--Parameters: num, number
--???????? data: sms content
--Return Value: true: sending successful, false sending failed

local function _send(num,data)
	local numlen,datalen,pducnt,pdu,pdulen,udhi = sformat("%02X",slen(num)),slen(data)/2,1,"","",""
	if not ready then return false end
	
    -- If the data sent is greater than 140 bytes, then the length of the message

	if datalen > 140 then
        -- calculate the length of the total number of messages split, the length of the message per packet of data actually only 134 actually want to send the contents of the message, the first 6 bytes of data protocol header

		pducnt = sformat("%d",(datalen+133)/134)
		pducnt = tonumber(pducnt)
        -- Assign a serial number in the range 0-255

		isn = isn==255 and 0 or isn+1
	end

    table.insert(tsend,{sval=pducnt,rval=0,flg=true})--sval Number of packets sent, rval Number of packets received

	
	if ssub(num,1,1) == "+" then
		numlen = sformat("%02X",slen(num)-1)
	end
	
	for i=1, pducnt do
        -- If it is a long message

		if pducnt > 1 then
			local len_mul
			len_mul = (i==pducnt and sformat("%02X",datalen-(pducnt-1)*134+6) or "8C")
            --udhi: 6-bit protocol header format

			udhi = "050003" .. sformat("%02X",isn) .. sformat("%02X",pducnt) .. sformat("%02X",i)
			print(datalen, udhi)
			pdu = "005110" .. numlen .. common.numtobcdnum(num) .. "000800" .. len_mul .. udhi .. ssub(data, (i-1)*134*2+1,i*134*2)
        -- send short message
  
        else
			datalen = sformat("%02X",datalen)
			pdu = "001110" .. numlen .. common.numtobcdnum(num) .. "000800" .. datalen .. data
		end
		pdulen = slen(pdu)/2-1
		req(sformat("%s%s","AT+CMGS=",pdulen),pdu)
	end
	return true
end

--Function name: read
--Function: read sms
--Parameters: pos SMS location
--Return Value: true: read successfully, false read failed

function read(pos)
	if not ready or pos==ni or pos==0 then return false end
	
	req("AT+CMGR="..pos)
	return true
end

--Function name: delete
--Function: delete SMS
--Parameters: pos SMS location
--Return Value: true: delete successful, false delete failed

function delete(pos)
	if not ready or pos==ni or pos==0 then return false end
	req("AT+CMGD="..pos)
	return true
end

Charmap = {[0]=0x40,0xa3,0x24,0xa5,0xe8,0xE9,0xF9,0xEC,0xF2,0xC7,0x0A,0xD8,0xF8,0x0D,0xC5,0xE5
		  ,0x0394,0x5F,0x03A6,0x0393,0x039B,0x03A9,0x03A0,0x03A8,0x03A3,0x0398,0x039E,0x1B,0xC6,0xE5,0xDF,0xA9
		  ,0x20,0x21,0x22,0x23,0xA4,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F
		  ,0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F
		  ,0xA1,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F
		  ,0X50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0xC4,0xD6,0xD1,0xDC,0xA7
		  ,0xBF,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6D,0x6E,0x6F
		  ,0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0xE4,0xF6,0xF1,0xFC,0xE0}

Charmapctl = {[10]=0x0C,[20]=0x5E,[40]=0x7B,[41]=0x7D,[47]=0x5C,[60]=0x5B,[61]=0x7E
			 ,[62]=0x5D,[64]=0x7C,[101]=0xA4}

--Function name: gsm7bitdecode
--Function: 7-digit encoding, in PDU mode, up to 160 characters when using 7-digit encoding
--Parameters: data
--???????? longsms
--return value:

function gsm7bitdecode(data,longsms)
	local ucsdata,lpcnt,tmpdata,resdata,nbyte,nleft,ucslen,olddat = "",slen(data)/2,0,0,0,0,0
  
	if longsms then
		tmpdata = tonumber("0x" .. ssub(data,1,2))   
		resdata = bit.rshift(tmpdata,1)
		if olddat==27 then
			if Charmapctl[resdata] then--Special characters

				olddat,resdata = resdata,Charmapctl[resdata]
				ucsdata = ssub(ucsdata,1,-5)
			else
				olddat,resdata = resdata,Charmap[resdata]
			end
		else
			olddat,resdata = resdata,Charmap[resdata]
		end
		ucsdata = ucsdata .. sformat("%04X",resdata)
	else
		tmpdata = tonumber("0x" .. ssub(data,1,2))    
		resdata = bit.band(bit.bor(bit.lshift(tmpdata,nbyte),nleft),0x7f)
		if olddat==27 then
			if Charmapctl[resdata] then--Special characters

				olddat,resdata = resdata,Charmapctl[resdata]
				ucsdata = ssub(ucsdata,1,-5)
			else
				olddat,resdata = resdata,Charmap[resdata]
			end
		else
			olddat,resdata = resdata,Charmap[resdata]
		end
		ucsdata = ucsdata .. sformat("%04X",resdata)
   
		nleft = bit.rshift(tmpdata, 7-nbyte)
		nbyte = nbyte+1
		ucslen = ucslen+1
	end
  
	for i=2, lpcnt do
		tmpdata = tonumber("0x" .. ssub(data,(i-1)*2+1,i*2))   
		if tmpdata == nil then break end 
		resdata = bit.band(bit.bor(bit.lshift(tmpdata,nbyte),nleft),0x7f)
		if olddat==27 then
			if Charmapctl[resdata] then--Special characters

				olddat,resdata = resdata,Charmapctl[resdata]
				ucsdata = ssub(ucsdata,1,-5)
			else
				olddat,resdata = resdata,Charmap[resdata]
			end
		else
			olddat,resdata = resdata,Charmap[resdata]
		end
		ucsdata = ucsdata .. sformat("%04X",resdata)
   
		nleft = bit.rshift(tmpdata, 7-nbyte)
		nbyte = nbyte+1
		ucslen = ucslen+1
	
		if nbyte == 7 then
			if olddat==27 then
				if Charmapctl[nleft] then--Special characters

					olddat,nleft = nleft,Charmapctl[nleft]
					ucsdata = ssub(ucsdata,1,-5)
				else
					olddat,nleft = nleft,Charmap[nleft]
				end
			else
				olddat,nleft = nleft,Charmap[nleft]
			end
			ucsdata = ucsdata .. sformat("%04X",nleft)
			nbyte,nleft = 0,0
			ucslen = ucslen+1
		end
	end
  
	return ucsdata,ucslen
end

--Function name: gsm8bitdecode
--Function: 8-digit encoding
--Parameters: data
--???????? longsms
--return value:

function gsm8bitdecode(data)
	local ucsdata,lpcnt = "",slen(data)/2
   
	for i=1, lpcnt do
		ucsdata = ucsdata .. "00" .. ssub(data,(i-1)*2+1,i*2)
	end
   
	return ucsdata,lpcnt
end

--Function name: rsp
--Function: AT answer
--Parameters: cmd, success, response, intermediate
--Return Value: None

local function rsp(cmd,success,response,intermediate)
	local prefix = smatch(cmd,"AT(%+%u+)")
	print("lib_sms rsp",prefix,cmd,success,response,intermediate)

    -- read sms success

	if prefix == "+CMGR" and success then
		local convnum,t,stat,alpha,len,pdu,data,longsms,total,isn,idx = "",""
		if intermediate then
			stat,alpha,len,pdu = smatch(intermediate,"+CMGR:%s*(%d),(.*),%s*(%d+)\r\n(%x+)")
			len = tonumber(len)-- PDU data length, excluding short message center number

		end
	
        -- The received PDU is not empty, the PDU is parsed

		if pdu and pdu ~= "" then
			local offset,addlen,addnum,flag,dcs,tz,txtlen,fo=5     
			pdu = ssub(pdu,(slen(pdu)/2-len)*2+1,-1)-- PDU data, excluding short message center number

			fo = tonumber("0x" .. ssub(pdu,1,1))-- The first 4 bytes of the PDU message, and the 6th bit is the data header flag

			if bit.band(fo, 0x4) ~= 0 then
				longsms = true
			end
			addlen = tonumber(sformat("%d","0x"..ssub(pdu,3,4)))-- Reply address number of numbers

	  
			addlen = addlen%2 == 0 and addlen+2 or addlen+3 -- Plus number type 2 digits (5, 6) or Plus number type 2 digits (5, 6) and 1 digit F

	  
			offset = offset+addlen
	  
			addnum = ssub(pdu,5,5+addlen-1)
			convnum = common.bcdnumtonum(addnum)
	  
			flag = tonumber(sformat("%d","0x"..ssub(pdu,offset,offset+1)))-- Protocol Identification (TP-PID)

			offset = offset+2
			dcs = tonumber(sformat("%d","0x"..ssub(pdu,offset,offset+1)))-- User information encoding Dcs = 8, indicating the format of message storage UCS2 encoding

			offset = offset+2
			tz = ssub(pdu,offset,offset+13)-- Time zone 7 bytes

			offset = offset+14
			txtlen = tonumber(sformat("%d","0x"..ssub(pdu,offset,offset+1)))--SMS text length

			offset = offset+2
			data = ssub(pdu,offset,offset+txtlen*2-1)-- SMS text

			if longsms then
				isn,total,idx = tonumber("0x" .. ssub(data, 7,8)),tonumber("0x" .. ssub(data, 9,10)),tonumber("0x" .. ssub(data, 11,12))
				data = ssub(data, 13,-1)-- Remove header 6 bytes

			end
	  
			print("TP-PID : ",flag, "dcs: ", dcs, "tz: ",tz, "data: ",data,"txtlen",txtlen)
	  
			if dcs == 0x00 then--7bit encode
				local newlen
				data,newlen = gsm7bitdecode(data, longsms)
				if newlen > txtlen then
					data = ssub(data,1,txtlen*4)
				end
				print("7bit to ucs2 data: ",data,"txtlen",txtlen,"newlen",newlen)
			elseif dcs == 0x04 then--8bit encode
				data,txtlen = gsm8bitdecode(data)
				print("8bit to ucs2 data: ",data,"txtlen",txtlen)
			end
  
			for i=1, 7  do
				t = t .. ssub(tz, i*2,i*2) .. ssub(tz, i*2-1,i*2-1)
	  
				if i<=3 then
					t = i<3 and (t .. "/") or (t .. ",")
				elseif i <= 6 then
					t = i<6 and (t .. ":") or (t .. "+")
				end
			end
		end
	
		local pos = smatch(cmd,"AT%+CMGR=(%d+)")
		data = data or ""
		alpha = alpha or ""
		dispatch("SMS_READ_CNF",success,convnum,data,pos,t,alpha,total,idx,isn)
	elseif prefix == "+CMGD" then
		dispatch("SMS_DELETE_CNF",success)
	elseif prefix == "+CMGS" then
        -- If it is short message, send SMS confirmation message directly

        if tsend[1].sval == 1 then--{sval=pducnt,rval=0,flg=true}
            table.remove(tsend,1)
            dispatch("SMS_SEND_CNF",success)
        -- If it is a long message, after all cmgs, SMS_SEND_CNF is thrown, all cmgs are successful, true, the rest are false

        else
            tsend[1].rval=tsend[1].rval+1
            -- As long as there is a short message that has failed to be sent, the entire short message will be marked as failed to be sent

            if not success then tsend[1].flg=false end
            if tsend[1].sval == tsend[1].rval then
                dispatch("SMS_SEND_CNF",tsend[1].flg)
                table.remove(tsend,1)
            end
        end
	end
end

--Function name: urc
--Function: take the initiative to report the message processing function
--Parameters: data, prefix
--Return Value: None

local function urc(data,prefix)
    -- SMS ready

	if data == "SMS READY" then
		ready = true
		--req ("AT + CSMP = 17,167,0,8") -- Set the texting TEXT mode parameters
		--????????-- Use PDU mode to send
		req("AT+CMGF=0")
        -- Set the AT command character encoding is UCS2

		req("AT+CSCS=\"UCS2\"")
        -- Distribute sms ready for the message

		dispatch("SMS_READY")
	elseif prefix == "+CMTI" then
        -- Extract SMS location

		local pos = smatch(data,"(%d+)",slen(prefix)+1)
        -- Distribute new message received

		dispatch("SMS_NEW_MSG_IND",pos)
	end
end

--Function name: getsmsstate
--Function: Get the status of the short message is ready
--Parameters: None
--Return Value: true ready, other values: not ready

function getsmsstate()
	return ready
end

--Function name: mergelongsms
--Function: Consolidate long message
--Parameters: None
--Return Value: None

local function mergelongsms()
	local data,num,t,alpha=""
    -- According to the order of the table, a mosaic of short message content

	for i=1, #tlongsms do
		if tlongsms[i] and tlongsms[i].dat and tlongsms[i].dat~="" then
			data,num,t,alpha = data .. tlongsms[i].dat,tlongsms[i].num,tlongsms[i].t,tlongsms[i].nam 
		end
	end
    -- Delete the SMS entry in the table to ensure the correct combination of the next SMS

	for i=1, #tlongsms do
		table.remove(tlongsms)
	end
    -- Dispatch short message merge confirmation message

	sys.dispatch("LONG_SMS_MERGR_CNF",true,num,data,t,alpha)
	print("mergelongsms", "num:",num, "data", data)
end

--Function name: longsmsind
--Function: SMS messages are disassembled reported
--Parameters: id, num, data, datetime, name, total, idx, isn
--Return Value: None

local function longsmsind(id,num, data,datetime,name,total,idx,isn)
	print("longsmsind", "total:",total, "idx:",idx,"data", data)
    -- If the first packet of the long message, directly into the tlongsms table

	if #tlongsms==0 then
		tlongsms[idx] = {dat=data,udhi=total .. isn,num=num,t=datetime,nam=name}
	else
		local oldudhi = ""
        -- Get udhi value received before the package, used to identify whether the message received this table with the message received from the same SMS

		for i=1,#tlongsms do
			if tlongsms[i] and tlongsms[i].udhi and tlongsms[i].udhi~="" then
				oldudhi = tlongsms[i].udhi
				break
			end
		end
        -- The message received this time with the message received in the table is from the same long message, the package into the table
		-- Otherwise, merge the long message in the table first, then insert the package message into tlongsms table
		if oldudhi==total .. isn then
			tlongsms[idx] = {dat=data,udhi=total .. isn,num=num,t=datetime,nam=name}
		else
			sys.timer_stop(mergelongsms)
			mergelongsms()
			tlongsms[idx] = {dat=data,udhi=total .. isn,num=num,t=datetime,nam=name}
		end
	end
  
    -- The total number of SMS has been received, begin to merge SMS

	if total==#tlongsms then
		sys.timer_stop(mergelongsms)
		mergelongsms()
	else
        -- If the short message after 2 minutes has not yet been confiscated, the received short message will be automatically merged after 2 minutes

		sys.timer_start(mergelongsms,120000)
	end
end

--Register SMS aggregate function

sys.regapp(longsmsind,"LONG_SMS_MERGE")

ril.regurc("SMS READY",urc)
ril.regurc("+CMT",urc)
ril.regurc("+CMTI",urc)

ril.regrsp("+CMGR",rsp)
ril.regrsp("+CMGD",rsp)
ril.regrsp("+CMGS",rsp)

-- By default, new SMS storage location is reported

--req("AT+CNMI=2,1")
-- Use PDU mode to send

req("AT+CMGF=0")
req("AT+CSMP=17,167,0,8")
-- Set the AT command character encoding is UCS2

req("AT+CSCS=\"UCS2\"")
-- Set the memory area to SIM

req("AT+CPMS=\"SM\"")
req('AT+CNMI=2,1')




-- SMS send buffer table the maximum number

local SMS_SEND_BUF_MAX_CNT = 10
-- SMS send interval, in milliseconds

local SMS_SEND_INTERVAL = 3000
-- SMS send buffer table

local tsmsnd = {}

--Function name: sndnxt
--Function: Send the first message sent in the SMS buffer table
--Parameters: None
--Return Value: None

local function sndnxt()
	if #tsmsnd>0 then
		_send(tsmsnd[1].num,tsmsnd[1].data)
	end
end

--Function name: sendcnf
--Function: Processing function of SMS_SEND_CNF message, asynchronous notification message sending result
--Parameters:
--???????? result: the message sent, true is successful, false or nil is failed
--Return Value: None

local function sendcnf(result)
	print("sendcnf",result)
	local num,data,cb = tsmsnd[1].num,tsmsnd[1].data,tsmsnd[1].cb
	-- Remove the current message from the message sending buffer

	table.remove(tsmsnd,1)
	-- If you have sent the callback function, execute the callback

	if cb then cb(result,num,data) end
	-- SMS_SEND_INTERVAL If there are any more text messages in the SMS send buffer, continue to send SMS

	if #tsmsnd>0 then sys.timer_start(sndnxt,SMS_SEND_INTERVAL) end
end

--Function name: send
--Function: send sms
--Parameters:
--???????? num: SMS recipient number, ASCII string format
--data: SMS content, GB2312 encoded string
--cb: Callback function used when sending SMS asynchronously, optional
--idx: insert the location of the message sent buffer table, optional, the default is inserted at the end
--Return Value: return true, said the success of the call interface (not a successful message sent, SMS send results, returned by sendcnf, if cb, cb function will be notified); return false, said the interface failed to call

function send(num,data,cb,idx)
	-- The number or content is illegal

	if not num or num=="" or not data or data=="" then return end
	-- SMS sending buffer table is full

	if #tsmsnd>=SMS_SEND_BUF_MAX_CNT then return end
	local dat = common.binstohexs(common.gb2312toucs2be(data))
	-- If specified, insert location

	if idx then
		table.insert(tsmsnd,idx,{num=num,data=dat,cb=cb})
	-- No insertion position specified, inserted at end

	else
		table.insert(tsmsnd,{num=num,data=dat,cb=cb})
	end
	-- If there is only one SMS in the message sending buffer table, the SMS sending action will be triggered immediately

	if #tsmsnd==1 then _send(num,dat) return true end
end


--SMS reception location table

local tnewsms = {}

--Function name: readsms
--Function: Read the first SMS message in the location table
--Parameters: None
--Return Value: None

local function readsms()
	if #tnewsms ~= 0 then
		read(tnewsms[1])
	end
end

--Function name: newsms
--Function: SMS_NEW_MSG_IND (unread messages or new messages actively reported message) processing function of the message
--Parameters:
--???????? pos: SMS storage location
--Return Value: None

local function newsms(pos)
	-- The storage location is inserted into the SMS reception location list

	table.insert(tnewsms,pos)
	-- If there is only one message, read it immediately

	if #tnewsms == 1 then
		readsms()
	end
end

-- New SMS user processing functions

local newsmscb
--Function name: regnewsmscb
--Function: register new message user processing function
--Parameters:
--???????? cb: user handle function name
--Return Value: None

function regnewsmscb(cb)
	newsmscb = cb
end

--Function name: readcnf
--Function: SMS_READ_CNF message processing function, asynchronous read the contents of the message returned
--Parameters:
--???????? result: SMS reads the result, true is successful, false or nil is failed
--num: SMS number, ASCII string format
--data: Short message content, hexadecimal string in UCS2 big endian format
--pos: SMS storage location, temporarily useless
--datetime: SMS date and time, ASCII string format
--name: the name of the contact corresponding to the SMS number, temporarily useless
--Return Value: None

local function readcnf(result,num,data,pos,datetime,name,total,idx,isn)
	-- Filter numbers 86 and +86

	local d1,d2 = string.find(num,"^([%+]*86)")
	if d1 and d2 then
		num = string.sub(num,d2+1,-1)
	end
	--delete sms

	delete(tnewsms[1])
	-- Remove the location of this message from the SMS Receive Location Table

	table.remove(tnewsms,1)
	if total and total >1 then
		sys.dispatch("LONG_SMS_MERGE",num,data,datetime,name,total,idx,isn)  
		readsms()-- read the next new message

		return
	end
	if data then
		-- SMS content is converted to GB2312 string format

		data = common.ucs2betogb2312(common.hexstobins(data))
		-- User application processes sms

		if newsmscb then newsmscb(num,data,datetime) end
	end
	-- continue to read the next message

	readsms()
end

local function longsmsmergecnf(res,num,data,datetime)
	--print("longsmsmergecnf",num,data,datetime)
	if data then
		-- SMS content is converted to GB2312 string format

		data = common.ucs2betogb2312(common.hexstobins(data))
		-- User application processes sms

		if newsmscb then newsmscb(num,data,datetime) end
	end
end

-- Message module internal message processing table

local smsapp =
{
	SMS_NEW_MSG_IND = newsms, -- When you receive a new message, sms.lua will throw an SMS_NEW_MSG_IND message

	SMS_READ_CNF = readcnf, -- After calling sms.read to read sms, sms.lua will throw SMS_READ_CNF

	SMS_SEND_CNF = sendcnf, -- sms.lua throws SMS_SEND_CNF message after sms.send is called to send SMS

	SMS_READY = sndnxt, -- The underlying sms module is ready

	LONG_SMS_MERGR_CNF = longsmsmergecnf,
}

-- Register message handling functions

sys.regapp(smsapp)