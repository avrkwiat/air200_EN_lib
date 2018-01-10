
--Module Name: mqtt protocol management
--Module function: to achieve the agreement of the package package solution package, please first read http://public.dhe.ibm.com/software/dw/webservices/ws-mqtt/mqtt-v3r1.html Understand the mqtt agreement
--Last modified: 2017.02.24

--[[
Currently, only QoS = 0 and QoS = 1 are supported, and QoS = 2 is not supported
]]

module(...,package.seeall)

local lpack = require"pack"
require"common"
require"socket"
require"mqttdup"

local slen,sbyte,ssub,sgsub,schar,srep,smatch,sgmatch = string.len,string.byte,string.sub,string.gsub,string.char,string.rep,string.match,string.gmatch
-- Message type
CONNECT,CONNACK,PUBLISH,PUBACK,PUBREC,PUBREL,PUBCOMP,SUBSCRIBE,SUBACK,UNSUBSCRIBE,UNSUBACK,PINGREQ,PINGRSP,DISCONNECT = 1,2,3,4,5,6,7,8,9,10,11,12,13,14
-- Message sequence number

local seq = 1

local function print(...)
	_G.print("mqtt",...)
end

local function encutf8(s)
	if not s then return "" end
	local utf8s = common.gb2312toutf8(s)
	return lpack.pack(">HA",slen(utf8s),utf8s)
end

local function enclen(s)
	if not s or slen(s) == 0 then return schar(0) end
	local ret,len,digit = "",slen(s)
	repeat
		digit = len % 128
		len = len / 128
		if len > 0 then
			digit = bit.bor(digit,0x80)
		end
		ret = ret..schar(digit)
	until (len <= 0)
	return ret
end

local function declen(s)
	local i,value,multiplier,digit = 1,0,1 
	repeat
		if i > slen(s) then return end
		digit = sbyte(s,i) 
		value = value + bit.band(digit,127)*multiplier
		multiplier = multiplier * 128
		i = i + 1
	until (bit.band(digit,128) == 0)
	return true,value,i-1
end

local function getseq()
	local s = seq
	seq = (seq+1)%0xFFFF
	if seq == 0 then seq = 1 end
	return lpack.pack(">H",s)
end

local function iscomplete(s)
	local i,typ,flg,len,cnt
	for i=1,slen(s) do
		typ = bit.band(bit.rshift(sbyte(s,i),4),0x0f)
		--print("typ",typ)
		if typ >= CONNECT and typ <= DISCONNECT then
			flg,len,cnt = declen(ssub(s,i+1,-1))
			--print("f",flg,len,cnt,(slen(ssub(s,i+1,-1))-cnt))
			if flg and cnt <= 4 and len <= (slen(ssub(s,i+1,-1))-cnt) then
				return true,i,i+cnt+len,typ,len
			else
				return
			end
		end		
	end
end

--Function name: pack
--Function: MQTT group package
--Parameters:
--mqttver: mqtt protocol version number
--typ: message type
--...:variable parameter
--Return Value: The first return value is the message data, and the second return value is the custom parameter of each message

local function pack(mqttver,typ,...)
	local para = {}
	local function connect(alive,id,twill,user,pwd,cleansess)
		local ret = lpack.pack(">bAbbHA",
						CONNECT*16,
						encutf8(mqttver=="3.1.1" and "MQTT" or "MQIsdp"),
						mqttver=="3.1.1" and 4 or 3,
						(user and 1 or 0)*128+(pwd and 1 or 0)*64+twill.retain*32+twill.qos*8+twill.flg*4+(cleansess or 1)*2,
						alive,
						encutf8(id))
		if twill.flg==1 then
			ret = ret..encutf8(twill.topic)..encutf8(twill.payload)
		end
		ret = ret..encutf8(user)..encutf8(pwd)
		return ret
	end
	
	local function subscribe(p)
		para.dup,para.topic = true,p.topic
		para.seq = p.seq or getseq()
		print("subscribe",p.dup,para.dup,common.binstohexs(para.seq))
		
		local s = lpack.pack("bA",SUBSCRIBE*16+(p.dup and 1 or 0)*8+2,para.seq)
		for i=1,#p.topic do
			s = s..encutf8(p.topic[i].topic)..schar(p.topic[i].qos or 0)
		end
		return s
	end
	
	local function publish(p)
		para.dup,para.topic,para.payload,para.qos,para.retain = true,p.topic,p.payload,p.qos,p.retain
		para.seq = p.seq or getseq()
		--print("publish",p.dup,para.dup,common.binstohexs(para.seq))
		local s1 = lpack.pack("bAA",PUBLISH*16+(p.dup and 1 or 0)*8+(p.qos or 0)*2+p.retain or 0,encutf8(p.topic),((p.qos or 0)>0 and para.seq or ""))
		local s2 = s1..p.payload
		return s2
	end
	
	local function puback(seq)
		return schar(PUBACK*16)..seq
	end
	
	local function pingreq()
		return schar(PINGREQ*16)
	end
	
	local function disconnect()
		return schar(DISCONNECT*16)
	end
	
	local function unsubscribe(p)
		para.dup,para.topic = true,p.topic
		para.seq = p.seq or getseq()
		print("unsubscribe",p.dup,para.dup,common.binstohexs(para.seq))
		
		local s = lpack.pack("bA",UNSUBSCRIBE*16+(p.dup and 1 or 0)*8+2,para.seq)
		for i=1,#p.topic do
			s = s..encutf8(p.topic[i])
		end
		return s
	end

	local procer =
	{
		[CONNECT] = connect,
		[SUBSCRIBE] = subscribe,
		[PUBLISH] = publish,
		[PUBACK] = puback,
		[PINGREQ] = pingreq,
		[DISCONNECT] = disconnect,
		[UNSUBSCRIBE] = unsubscribe,
	}

	local s = procer[typ](...)
	local s1,s2,s3 = ssub(s,1,1),enclen(ssub(s,2,-1)),ssub(s,2,-1)
	s = s1..s2..s3
	print("pack",typ,(slen(s) > 200) and "" or common.binstohexs(s))
	return s,para
end

local rcvpacket = {}

--Function name: unpack
--Function: MQTT unpack
--Parameters:
--mqttver: mqtt protocol version number
--s: a complete message
--Return Value: If unpacking succeeds, returns a table type data, the data element is determined by the message type; if the unpacking fails, return nil

local function unpack(mqttver,s)
	rcvpacket = {}

	local function connack(d)
		print("connack",common.binstohexs(d))
		rcvpacket.suc = (sbyte(d,2)==0)
		rcvpacket.reason = sbyte(d,2)
		return true
	end
	
	local function suback(d)
		print("suback or unsuback",common.binstohexs(d))
		if slen(d) < 2 then return end
		rcvpacket.seq = ssub(d,1,2)
		return true
	end
	
	local function puback(d)
		print("puback",common.binstohexs(d))
		if slen(d) < 2 then return end
		rcvpacket.seq = ssub(d,1,2)
		return true
	end
	
	local function publish(d)
		print("publish",common.binstohexs(d)) -- When the amount of data is too large can not be opened, out of memory

		if slen(d) < 4 then return end
		local _,tplen = lpack.unpack(ssub(d,1,2),">H")		
		local pay = (rcvpacket.qos > 0 and 5 or 3)
		if slen(d) < tplen+pay-1 then return end
		rcvpacket.topic = ssub(d,3,2+tplen)
		
		if rcvpacket.qos > 0 then
			rcvpacket.seq = ssub(d,tplen+3,tplen+4)
			pay = 5
		end
		rcvpacket.payload = ssub(d,tplen+pay,-1)
		return true
	end
	
	local function empty()
		return true
	end

	local procer =
	{
		[CONNACK] = connack,
		[SUBACK] = suback,
		[PUBACK] = puback,
		[PUBLISH] = publish,
		[PINGRSP] = empty,
		[UNSUBACK] = suback,
	}
	local d1,d2,d3,typ,len = iscomplete(s)	
	if not procer[typ] then print("unpack unknwon typ",typ) return end
	rcvpacket.typ = typ
	rcvpacket.qos = bit.rshift(bit.band(sbyte(s,1),0x06),1)
	rcvpacket.dup = bit.rshift(bit.band(sbyte(s,1),0x08),3)==1
	print("unpack",typ,rcvpacket.qos,(slen(s) > 200) and "" or common.binstohexs(s))
	return procer[typ](ssub(s,slen(s)-len+1,-1)) and rcvpacket or nil
end


-- Actions in a connection cycle: If the connection to the background fails, a reconnection will be attempted with a reconnection interval of RECONN_PERIOD seconds and a maximum of RECONN_MAX_CNT times
-- If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
-- If no consecutive RECONN_CYCLE_MAX_CNT connection cycles are successful, restart the software
local RECONN_MAX_CNT,RECONN_PERIOD,RECONN_CYCLE_MAX_CNT,RECONN_CYCLE_PERIOD = 3,5,3,20

--mqtt clients storage table

local tclients = {}

--Function name: getclient
--Function: Returns an index of mqtt client in tclients
--Parameters:
--sckidx: mqtt client corresponding socket index
--Return values: Index of mqtt client corresponding to sckidx in tclients

local function getclient(sckidx)
	for k,v in pairs(tclients) do
		if v.sckidx==sckidx then return k end
	end
end

--Function name: mqttconncb
--Function: Asynchronous callback function after sending MQTT CONNECT message
--Parameters:
--sckidx: socket idx
--result: bool type, send the result, true is successful, the other is failed
--tpara: table type, {key = "MQTTCONN", val = CONNECT message data}
--Return Value: None

function mqttconncb(sckidx,result,tpara)
	-- MQTT CONNECT packet data saved up, if the timeout DUP_TIME seconds did not receive CONNACK or CONNACK failed to return, it will automatically retransmit the CONNECT message
	-- The retransmit trigger is in mqttdup.lua
	mqttdup.ins(sckidx,tmqttpack["MQTTCONN"].mqttduptyp,tpara.val)
end

--Function name: mqttconndata
--Function: Grouping MQTT CONNECT message data
--Parameters:
--sckidx: socket idx
--Return Value: CONNECT message data and message parameters

function mqttconndata(sckidx)
	local mqttclientidx = getclient(sckidx)
	return pack(tclients[mqttclientidx].mqttver,
				CONNECT,
				tclients[mqttclientidx].keepalive,
				tclients[mqttclientidx].clientid,
				{
					flg=tclients[mqttclientidx].willflg or 0,
					qos=tclients[mqttclientidx].willqos or 0,
					retain=tclients[mqttclientidx].willretain or 0,
					topic=tclients[mqttclientidx].willtopic or "",
					payload=tclients[mqttclientidx].willpayload or "",
				},
				tclients[mqttclientidx].user,
				tclients[mqttclientidx].password,
				tclients[mqttclientidx].cleansession or 1)
end

--Function name: mqttsubcb
--Function: Asynchronous callback function after sending SUBSCRIBE message
--Parameters:
--sckidx: socket idx
--result: bool type, send the result, true is successful, the other is failed
--tpara: table type, {key = "MQTTSUB", val = para, usertag = usertag, ackcb = ackcb}
--Return Value: None

local function mqttsubcb(sckidx,result,tpara)	
	-- Re-encapsulate the MQTT SUBSCRIBE packet, set the repeat flag to true, save the sequence number and topic with the original value, and save the data. If no SUBACK is received within the timeout of DUP_TIME seconds, the SUBSCRIBE packet is automatically resent
	-- The retransmit trigger is in mqttdup.lua
	mqttdup.ins(sckidx,tpara.key,pack(tclients[getclient(sckidx)].mqttver,SUBSCRIBE,tpara.val),tpara.val.seq,tpara.ackcb,tpara.usertag)
end

--Function name: mqttpubcb
--Function: Asynchronous callback function after sending PUBLISH message
--Parameters:
--sckidx: socket idx
--result: bool type, send the result, true is successful, the other is failed
--tpara: table type, {key = "MQTTPUB", val = para, qos = qos, usertag = usertag, ackcb = ackcb}
--Return Value: None

local function mqttpubcb(sckidx,result,tpara)	
	if tpara.qos==0 then
		if tpara.ackcb then tpara.ackcb(tpara.usertag,result) end
	elseif tpara.qos==1 then
		-- Re-encapsulate the MQTT PUBLISH message, the repeat flag is set to true, the sequence number, topic, and payload are stored in the original value and the data is saved. If no PUBACK is received in the timeout DUP_TIME seconds, the PUBLISH message is retransmitted automatically
		-- The retransmit trigger is in mqttdup.lua
		mqttdup.ins(sckidx,tpara.key,pack(tclients[getclient(sckidx)].mqttver,PUBLISH,tpara.val),tpara.val.seq,tpara.ackcb,tpara.usertag)
	end	
end

--Function name: mqttdiscb
--Function: Asynchronous callback function after sending MQTT DICONNECT message
--Parameters:
--sckidx: socket idx
--result: bool type, send the result, true is successful, the other is failed
--tpara: table type, {key = "MQTTDISC", val = data, usertag = usrtag}
--Return Value: None

function mqttdiscb(sckidx,result,tpara)
	-- close the socket connection

	tclients[getclient(sckidx)].discing = true
	socket.disconnect(sckidx,tpara.usertag)
end

--Function name: mqttdiscdata
--Function: Grouping MQTT DISCONNECT packet data
--Parameters:
--sckidx: socket idx
--Return Value: DISCONNECT packet data and packet parameters

function mqttdiscdata(sckidx)
	return pack(tclients[getclient(sckidx)].mqttver,DISCONNECT)
end

--Function name: disconnect
--Function: Send MQTT DISCONNECT packet
--Parameters:
--sckidx: socket idx
--usrtag: user-defined tag
--Return value: true means that the action was initiated, nil said it did not initiate

local function disconnect(sckidx,usrtag)
	return mqttsnd(sckidx,"MQTTDISC",usrtag)
end

--Function name: mqttpingreqdata
--Function: Packets MQTT PINGREQ message data
--Parameters:
--sckidx: socket idx
--Return Value: PINGREQ message data and message parameters

function mqttpingreqdata(sckidx)
	return pack(tclients[getclient(sckidx)].mqttver,PINGREQ)
end

--Function name: pingreq
--Function: Send MQTT PINGREQ message
--Parameters:
--sckidx: socket idx
--Return Value: None

local function pingreq(sckidx)
	local mqttclientidx = getclient(sckidx)
	mqttsnd(sckidx,"MQTTPINGREQ")
	if not sys.timer_is_active(disconnect,sckidx) then
		-- Start timer: MQTT DISCONNECT message is sent if pingrsp is not received within hold time of +30 seconds

		sys.timer_start(disconnect,(tclients[mqttclientidx].keepalive+30)*1000,sckidx)
	end
end

--Function name: snd
--Function: Call the sending interface to send data
--Parameters:
--sckidx: socket idx
--???????? data: The data sent, in the send result event handler ntfy, will be assigned to item.data
--para: send the parameters, in the send result event handler ntfy, will be assigned to the item.para
--Return Value: The result of invoking the sending interface (not the result of data sending success or not, the result of data sending success is notified in the SEND event in ntfy), true is success and the others are failed

function snd(sckidx,data,para)
	return socket.send(sckidx,data,para)
end

--mqtt application packet table

tmqttpack =
{
	MQTTCONN = {sndpara="MQTTCONN",mqttyp=CONNECT,mqttduptyp="CONN",mqttdatafnc=mqttconndata,sndcb=mqttconncb},
	MQTTPINGREQ = {sndpara="MQTTPINGREQ",mqttyp=PINGREQ,mqttdatafnc=mqttpingreqdata},
	MQTTDISC = {sndpara="MQTTDISC",mqttyp=DISCONNECT,mqttdatafnc=mqttdiscdata,sndcb=mqttdiscb},
}

local function getidbysndpara(para)
	for k,v in pairs(tmqttpack) do
		if v.sndpara==para then return k end
	end
end

--Function name: mqttsnd
--Function: The total interface for sending MQTT packets. According to the packet type, find the packet function in the mqtt application packet table, and then send the data
--Parameters:
--sckidx: socket idx
--???????? typ: message type
--usrtag: user-defined tag
--Return value: true means that the action was initiated, nil said it did not initiate

function mqttsnd(sckidx,typ,usrtag)
	if not tmqttpack[typ] then print("mqttsnd typ error",typ) return end
	local mqttyp = tmqttpack[typ].mqttyp
	local dat,para = tmqttpack[typ].mqttdatafnc(sckidx)
	
	if mqttyp==CONNECT then
		if tmqttpack[typ].mqttduptyp then mqttdup.rmv(sckidx,tmqttpack[typ].mqttduptyp) end
		if not snd(sckidx,dat,{key=tmqttpack[typ].sndpara,val=dat}) and tmqttpack[typ].sndcb then
			tmqttpack[typ].sndcb(sckidx,false,{key=tmqttpack[typ].sndpara,val=dat})
		end
	elseif mqttyp==PINGREQ then
		snd(sckidx,dat,{key=tmqttpack[typ].sndpara})
	elseif mqttyp==DISCONNECT then
		if not snd(sckidx,dat,{key=tmqttpack[typ].sndpara,usertag=usrtag}) and tmqttpack[typ].sndcb then
			tmqttpack[typ].sndcb(sckidx,false,{key=tmqttpack[typ].sndpara,usertag=usrtag})
		end		
	end	
	
	return true
end

--Function name: reconn
--Function: socket reconnect background processing
--???????? A connection cycle of action: If the connection fails the background, will try to reconnect, reconnect interval RECONN_PERIOD seconds, up to reconnect RECONN_MAX_CNT times
--???????? If no connection is successful within one connection cycle, wait for RECONN_CYCLE_PERIOD seconds to re-initiate a connection cycle
--???????? If consecutive RECONN_CYCLE_MAX_CNT secondary connection cycles are not connected successfully, then restart the software
--Parameters:
--sckidx: socket idx
--Return Value: None

local function reconn(sckidx)
	local mqttclientidx = getclient(sckidx)
	print("reconn",mqttclientidx,tclients[mqttclientidx].sckreconncnt,tclients[mqttclientidx].sckconning,tclients[mqttclientidx].sckreconncyclecnt)
	--sckconning Indicates that you are trying to connect to the background, be sure to judge this variable, otherwise it may initiate unnecessary reconnection, resulting in increased sckreconncnt, reduce the actual number of reconnections
	if tclients[mqttclientidx].sckconning then return end
	-- Reconnect within a connection cycle

	if tclients[mqttclientidx].sckreconncnt < RECONN_MAX_CNT then		
		tclients[mqttclientidx].sckreconncnt = tclients[mqttclientidx].sckreconncnt+1
		link.shut()
		for k,v in pairs(tclients) do
			connect(v.sckidx,v.prot,v.host,v.port)
		end
		
	-- Reconnection of one connection cycle failed

	else
		tclients[mqttclientidx].sckreconncnt,tclients[mqttclientidx].sckreconncyclecnt = 0,tclients[mqttclientidx].sckreconncyclecnt+1
		if tclients[mqttclientidx].sckreconncyclecnt >= RECONN_CYCLE_MAX_CNT then
			if tclients[mqttclientidx].sckerrcb then
				tclients[mqttclientidx].sckreconncnt=0
				tclients[mqttclientidx].sckreconncyclecnt=0
				tclients[mqttclientidx].sckerrcb("CONNECT")
			else
				sys.restart("connect fail")
			end
		else
			sys.timer_start(reconn,RECONN_CYCLE_PERIOD*1000,sckidx)
		end		
	end
end

--Function name: ntfy
--Function: Socket state processing function
--Parameters:
--???????? idx: number type socket socket ID maintained socket the same as the first argument passed socket.connect, the program can ignore the non-processing
--???????? evt: string type, the message event type
--result: bool type, the result of the message event, true is successful, others are failed
--The item: table type, {data =, para =}, parameters and data returned by the message, is currently only used in SEND type events such as the second and third passed in when socket.send is called The parameters are dat and par, then item = {data = dat, para = par}
--Return Value: None

function ntfy(idx,evt,result,item)
	local mqttclientidx = getclient(idx)
	print("ntfy",evt,result,item)
	-- connection result (asynchronous event after socket.connect call)

	if evt == "CONNECT" then
		tclients[mqttclientidx].sckconning = false
		--connection succeeded

		if result then
			tclients[mqttclientidx].sckconnected=true
			tclients[mqttclientidx].sckreconncnt=0
			tclients[mqttclientidx].sckreconncyclecnt=0
			tclients[mqttclientidx].sckrcvs=""
			-- Stop the reconnection timer

			sys.timer_stop(reconn,idx)
			-- Send mqtt connect request

			mqttsnd(idx,"MQTTCONN")
		--Connection failed

		else
			-- RECONN_PERIOD seconds later reconnect

			sys.timer_start(reconn,RECONN_PERIOD*1000,idx)
		end	
	-- Data transmission result (asynchronous event after socket.send is called)

	elseif evt == "SEND" then
		if not result then
			link.shut()
		else
			if item.para then
				if item.para.key=="MQTTPUB" then
					mqttpubcb(idx,result,item.para)
				elseif item.para.key=="MQTTSUB" then
					mqttsubcb(idx,result,item.para)
				elseif item.para.key=="MQTTDUP" then
					mqttdupcb(idx,result,item.data)
				else
					local id = getidbysndpara(item.para.key)
					print("item.para",type(item.para) == "table",type(item.para) == "table" and item.para.typ or item.para,id)
					if id and tmqttpack[id].sndcb then tmqttpack[id].sndcb(idx,result,item.para) end
				end
			end
		end
	-- The connection is disconnected passively

	elseif evt == "STATE" and result == "CLOSED" then
		sys.timer_stop(pingreq,idx)
		mqttdup.rmvall(idx)
		tclients[mqttclientidx].sckconnected=false
		tclients[mqttclientidx].mqttconnected=false
		tclients[mqttclientidx].sckrcvs=""
		if tclients[mqttclientidx].discing then
			if tclients[mqttclientidx].discb then tclients[mqttclientidx].discb() end
			tclients[mqttclientidx].discing = false
		else
			reconn(idx)
		end
	-- Active disconnect (asynchronous after calling link.shut)

	elseif evt == "STATE" and result == "SHUTED" then
		sys.timer_stop(pingreq,idx)
		mqttdup.rmvall(idx)
		tclients[mqttclientidx].sckconnected=false
		tclients[mqttclientidx].mqttconnected=false
		tclients[mqttclientidx].sckrcvs=""
		reconn(idx)
	-- Active disconnect (asynchronous after calling socket.disconnect)

	elseif evt == "DISCONNECT" then
		sys.timer_stop(pingreq,idx)
		mqttdup.rmvall(idx)
		tclients[mqttclientidx].sckconnected=false
		tclients[mqttclientidx].mqttconnected=false
		tclients[mqttclientidx].sckrcvs=""
		if item=="USER" then
			if tclients[mqttclientidx].discb then tclients[mqttclientidx].discb() end
			tclients[mqttclientidx].discing = false
		else
			reconn(idx)
		end
	-- The connection is actively disconnected and destroyed (an asynchronous event after socket.close is called)

	elseif evt == "CLOSE" then
		sys.timer_stop(pingreq,idx)
		mqttdup.rmvall(idx)
		local cb = tclients[mqttclientidx].destroycb
		table.remove(tclients,mqttclientidx)
		if cb then cb() end
	end
	-- Other error handling, disconnect the data link, reconnect

	if smatch((type(result)=="string") and result or "","ERROR") then
		link.shut()
	end
end

--Function name: connack
--Function: Process the MQTT CONNACK packet sent by the server
--Parameters:
--???????? sckidx: socket idx
--packet: parsed message format, table type {suc = whether the connection is successful}
--Return Value: None

local function connack(sckidx,packet)
	local mqttclientidx = getclient(sckidx)
	print("connack",packet.suc)
	if packet.suc then
		tclients[mqttclientidx].mqttconnected = true
		mqttdup.rmv(sckidx,tmqttpack["MQTTCONN"].mqttduptyp)
		if tclients[mqttclientidx].connectedcb then tclients[mqttclientidx].connectedcb() end
	else
		if tclients[mqttclientidx].connecterrcb then tclients[mqttclientidx].connecterrcb(packet.reason) end
	end
end

--Function name: suback
--Function: The server processes MQTT SUBACK packets
--Parameters:
--???????? sckidx: socket idx
--packet: parsed packet format, table type {seq = corresponding SUBSCRIBE packet sequence number}
--Return Value: None

local function suback(sckidx,packet)
	local mqttclientidx = getclient(sckidx)
	local typ,cb,cbtag = mqttdup.getyp(sckidx,packet.seq)
	print("suback",common.binstohexs(packet.seq))
	mqttdup.rmv(sckidx,nil,nil,packet.seq)
	if cb then cb(cbtag,true) end
end

--Function name: puback
--Function: The server processes MQTT PUBACK packets
--Parameters:
--???????? sckidx: socket idx
--packet: parsed message format, table type {seq = corresponding PUBLISH message sequence number}
--Return Value: None

local function puback(sckidx,packet)
	local mqttclientidx = getclient(sckidx)
	local typ,cb,cbtag = mqttdup.getyp(sckidx,packet.seq)
	print("puback",common.binstohexs(packet.seq),typ)
	mqttdup.rmv(sckidx,nil,nil,packet.seq)
	if cb then cb(cbtag,true) end
end

--Function name: svrpublish
--Function: Process MQTT PUBLISH messages sent by the server
--Parameters:
--???????? sckidx: socket idx
--mqttpacket: parsed message format, table type {qos =, topic, seq, payload}
--Return Value: None

local function svrpublish(sckidx,mqttpacket)
	local mqttclientidx = getclient(sckidx)
	print("svrpublish",mqttpacket.topic,mqttpacket.seq,mqttpacket.payload)	
	if mqttpacket.qos == 1 then snd(sckidx,pack(tclients[mqttclientidx].mqttver,PUBACK,mqttpacket.seq)) end
	if tclients[mqttclientidx].evtcbs then
		if tclients[mqttclientidx].evtcbs["MESSAGE"] then tclients[mqttclientidx].evtcbs["MESSAGE"](common.utf8togb2312(mqttpacket.topic),mqttpacket.payload,mqttpacket.qos) end
	end
end

--Function name: pingrsp
--Function: Process the MQTT PINGRSP packet delivered by the server
--Parameters:
--sckidx: socket idx
--Return Value: None

local function pingrsp(sckidx)
	sys.timer_stop(disconnect,sckidx)
end

-- The server sends a message processing table

mqttcmds = {
	[CONNACK] = connack,
	[SUBACK] = suback,
	[PUBACK] = puback,
	[PUBLISH] = svrpublish,
	[PINGRSP] = pingrsp,
}

--Function name: datinactive
--Function: Data communication exception handling
--Parameters:
--sckidx: socket idx
--Return Value: None

local function datinactive(sckidx)
	local mqttclientidx = getclient(sckidx)
	if tclients[mqttclientidx].sckerrcb then
		link.shut()
		tclients[mqttclientidx].sckreconncnt=0
		tclients[mqttclientidx].sckreconncyclecnt=0
		tclients[mqttclientidx].sckerrcb("SVRNODATA")
	else
		sys.restart("SVRNODATA")
	end
end

--Function name: checkdatactive
--Function: Start again to check whether "data communication is abnormal"
--Parameters:
--sckidx: socket idx
--Return Value: None

local function checkdatactive(sckidx)
	local mqttclientidx = getclient(sckidx)
	sys.timer_start(datinactive,tclients[mqttclientidx].keepalive*1000*3+30000,sckidx) -- 3 times keeping time + half a minute

end

--Function name: rcv
--Function: socket to receive data processing functions
--Parameters:
--???????? idx: Socket socket idx maintained socket, the same as the first argument passed socket.connect, the program can ignore the non-processing
--???????? data: received data
--Return Value: None

function rcv(idx,data)
	local mqttclientidx = getclient(idx)
	print("rcv",slen(data)>200 and slen(data) or common.binstohexs(data))
	sys.timer_start(pingreq,tclients[mqttclientidx].keepalive*1000/2,idx)	
	tclients[mqttclientidx].sckrcvs = tclients[mqttclientidx].sckrcvs..data

	local f,h,t = iscomplete(tclients[mqttclientidx].sckrcvs)

	while f do
		data = ssub(tclients[mqttclientidx].sckrcvs,h,t)
		tclients[mqttclientidx].sckrcvs = ssub(tclients[mqttclientidx].sckrcvs,t+1,-1)
		local packet = unpack(tclients[mqttclientidx].mqttver,data)
		if packet and packet.typ and mqttcmds[packet.typ] then
			mqttcmds[packet.typ](idx,packet)
			if packet.typ ~= CONNACK and packet.typ ~= SUBACK then
				checkdatactive(idx)
			end
		end
		f,h,t = iscomplete(tclients[mqttclientidx].sckrcvs)
	end
end


--Function name: connect
--Function: create a socket connection to the background server;
--???????? If the data network is ready, it will understand the background connection; otherwise, the connection request will be suspended, and so the data network is ready, automatically connect to the background
--ntfy: socket state handler
--rcv: socket receive data processing functions
--Parameters:
--sckidx: socket idx
--prot: string type, transport protocol, only "TCP" and "UDP" [Required]
--host: string type, server address, supporting domain name and IP address [Required]
--port: number type, server port [Required]
--Return Value: None

function connect(sckidx,prot,host,port)
	socket.connect(sckidx,prot,host,port,ntfy,rcv)
	tclients[getclient(sckidx)].sckconning=true
end

--Function name: mqttdupcb
--Function: The asynchronous callback after the retry message triggered in mqttdup is sent
--Parameters:
--sckidx: socket idx
--result: bool type, send the result, true is successful, the other is failed
--v: message data
--Return Value: None

function mqttdupcb(sckidx,result,v)
	mqttdup.rsm(sckidx,v)
end

--Function name: mqttdupind
--Function: Retransmitted message processing triggered in mqttdup
--Parameters:
--sckidx: socket idx
--s: message data
--Return Value: None

local function mqttdupind(sckidx,s)
	if not snd(sckidx,s,{key="MQTTDUP"}) then mqttdupcb(sckidx,false,s) end
end

--Function name: mqttdupfail
--Function: The retransmission packet triggered in mqttdup will send a failed notification message in the maximum number of retransmissions
--Parameters:
--sckidx: socket idx
--t: User-defined type of the packet
--s: message data
--cb: user callback function
--cbtag: The first parameter of the user callback function
--Return Value: None

local function mqttdupfail(sckidx,t,s,cb,cbtag)
    print("mqttdupfail",t)
	if cb then cb(cbtag,false) end
end

-- mqttdup resend message handler function table

local procer =
{
	MQTT_DUP_IND = mqttdupind,
	MQTT_DUP_FAIL = mqttdupfail,
}
-- Registered message processing functions

sys.regapp(procer)


local tmqtt = {}
tmqtt.__index = tmqtt


--Function name: create
--Function: Create a mqtt client
--Parameters:
--prot: string type, transport protocol, only "TCP" and "UDP" [Required]
--host: string type, server address, supporting domain name and IP address [Required]
--port: number type, server port [Required]
--ver: string type, MQTT protocol version number, only supports "3.1" and "3.1.1", the default "3.1"
--Return Value: None

function create(prot,host,port,ver)
	if #tclients>=2 then assert(false,"tclients maxcnt error") return end
	local mqtt_client =
	{
		prot=prot,
		host=host,
		port=port,		
		sckidx=socket.SCK_MAX_CNT-#tclients,
		sckconning=false,
		sckconnected=false,
		sckreconncnt=0,
		sckreconncyclecnt=0,
		sckrcvs="",
		mqttconnected=false,
		mqttver = ver or "3.1",
	}
	setmetatable(mqtt_client,tmqtt)
	table.insert(tclients,mqtt_client)
	return(mqtt_client)
end

--Function name: change
--Function: Change a mqtt client socket parameters
--Parameters:
--prot: string type, transport protocol, only "TCP" and "UDP" [Required]
--host: string type, server address, supporting domain name and IP address [Required]
--port: number type, server port [Required]
--Return Value: None

function tmqtt:change(prot,host,port)
	self.prot,self.host,self.port=prot or self.prot,host or self.host,port or self.port
end

--Function name: destroy
--Function: Destroy an mqtt client
--Parameters:
--destroycb: function type, mqtt client callback function after destruction [optional]
--Return Value: None

function tmqtt:destroy(destroycb)
	local k,v
	self.destroycb = destroycb
	for k,v in pairs(tclients) do
		if v.sckidx==self.sckidx then
			socket.close(v.sckidx)
		end
	end
end

--Function name: disconnect
--Function: Disconnect an mqtt client, and disconnect the socket
--Parameters:
--discb: function type, callback function after disconnection [optional]
--Return Value: None

function tmqtt:disconnect(discb)
	print("tmqtt:disconnect",self.discing,self.mqttconnected,self.sckconnected)
	sys.timer_stop(datinactive,self.sckidx)
	if self.discing or not self.mqttconnected or not self.sckconnected then
		if discb then discb() end
		return
	end
	self.discb = discb
	if not disconnect(self.sckidx,"USER") and discb then discb() end
end

--Function name: configwill
--Function: Configure testament parameters
--Parameters:
--flg: number type, testament flag, only 0 and 1 are supported
--qos: number type, server-side testament message quality of service level, only supports 0,1,2
--retain: number type, testament retention mark, only supports 0 and 1
--topic: string type, server-side issue of the theme of the will message, gb2312 encoding
--payload: string type, server-side testament message load, gb2312 encoding
--Return Value: None

function tmqtt:configwill(flg,qos,retain,topic,payload)
	self.willflg=flg or 0
	self.willqos=qos or 0
	self.willretain=retain or 0
	self.willtopic=topic or ""
	self.willpayload=payload or ""
end

--Function name: setcleansession
--Function: Configure the clean session flag
--Parameters:
--flg: number type, clean session flag, only supports 0 and 1, the default is 1
--Return Value: None

function tmqtt:setcleansession(flg)
	self.cleansession=flg or 1
end

--Function name: connect
--Function: connect mqtt server
--Parameters:
--clientid: string type, client identifier, gb2312 encoding [Required]
--keepalive: number type, keepalive time, in seconds [optional, default 600]
--user: string type, username, gb2312 encoding [optional, default ""]
--password: string type, password, gb2312 encoding [optional, default ""]
--connectedcb: function type, mqtt connection successful callback function [optional]
--connecterrcb: function type, mqtt connection failed callback function [optional]
--sckerrcb: function type, socket connection failed callback function [optional]
--Return Value: None

function tmqtt:connect(clientid,keepalive,user,password,connectedcb,connecterrcb,sckerrcb)
	self.clientid=clientid
	self.keepalive=keepalive or 600
	self.user=user or ""
	self.password=password or ""
	--if autoreconnect==nil then autoreconnect=true end
	--self.autoreconnect=autoreconnect
	self.connectedcb=connectedcb
	self.connecterrcb=connecterrcb
	self.sckerrcb=sckerrcb
	
	tclients[getclient(self.sckidx)]=self
	
	if self.mqttconnected then print("tmqtt:connect already connected") return end
	if not self.sckconnected then
		connect(self.sckidx,self.prot,self.host,self.port)
		checkdatactive(self.sckidx)
	elseif not self.mqttconnected then
		mqttsnd(self.sckidx,"MQTTCONN")
	else
		if connectedcb then connectedcb() end
	end
end

--Function name: publish
--Function: Post a message
--Parameters:
--topic: string type, message subject, gb2312 encoding [Required]
--payload: Binary data, message payload, user-defined encoding, this file will not do any transcoding of the data [Required]
--flags: number type, qos and retain flags, only 0,1,4,5 [optional, default 0]
--0 means: qos = 0, retain = 0
--1 means: qos = 1, retain = 0
--4 means: qos = 0, retain = 1
--5 means: qos = 1, retain = 1
--ackcb: function type, when qos is 1, it means receiving PUBACK callback function, callback function of sending result when qos is 0 [optional]
--usertag: string type, the first parameter used by the user callback ackcb [optional]
--Return Value: None

function tmqtt:publish(topic,payload,flags,ackcb,usertag)
	-- Check mqtt connection status

	if not self.mqttconnected then
		print("tmqtt:publish not connected")
		if ackcb then ackcb(usertag,false) end
		return
	end
	
	if flags and flags~=0 and flags~=1 and flags~=4 and flags~=5 then assert(false,"tmqtt:publish not support flags "..flags) return end
	local qos,retain = flags and (bit.band(flags,0x03)) or 0,flags and (bit.isset(flags,2) and 1 or 0) or 0
	--print("tmqtt:publish",flags,qos,retain)
	-- Package publish messages

	local dat,para = pack(self.mqttver,PUBLISH,{qos=qos,retain=retain,topic=topic,payload=payload})
	
	--·¢ËÍ
	local tpara = {key="MQTTPUB",val=para,qos=qos,retain=retain,usertag=usertag,ackcb=ackcb}
	if not snd(self.sckidx,dat,tpara) then
		mqttpubcb(self.sckidx,false,tpara)
	end
end

--Function name: subscribe
--Features: Subscribe to the theme
--Parameters:
--topics: table type, one or more topics, the subject name gb2312 encoding, the quality level only supports 0 and 1, {{topic = "/ topic1", qos = quality level}, {topic = "/ topic2", qos = quality Level}, ...} [Required]
--ackcb: function type, that received SUBACK callback function [optional]
--usertag: string type, the first parameter used by the user callback ackcb [optional]
--Return Value: None

function tmqtt:subscribe(topics,ackcb,usertag)
	-- Check mqtt connection status

	if not self.mqttconnected then
		print("tmqtt:subscribe not connected")
		if ackcb then ackcb(usertag,false) end
		return
	end
	
	-- Only qos 0 and 1 are supported

	for k,v in pairs(topics) do
		if v.qos==2 then assert(false,"tmqtt:publish not support qos 2") return end
	end

	-- package subscribe message

	local dat,para = pack(self.mqttver,SUBSCRIBE,{topic=topics})
	
	--send

	local tpara = {key="MQTTSUB", val=para, usertag=usertag, ackcb=ackcb}
	if not snd(self.sckidx,dat,tpara) then
		mqttsubcb(self.sckidx,false,tpara)
	end
end

--Function name: regevtcb
--Function: Registration event callback function
--Parameters:
--evtcbs: One or more pairs of evt and cb in the format of {evt = cb, ...}}, the values of evt are as follows:
--"MESSAGE": said the message received from the server, call cb format cb (topic, payload, qos)
--Return Value: None

function tmqtt:regevtcb(evtcbs)
	self.evtcbs=evtcbs	
end

--Function name: getstatus
--Function: Get the status of MQTT CLIENT
--Parameters: None
--Return Value: MQTT CLIENT state, string type, a total of 4 states:
--DISCONNECTED: Not connected status
--CONNECTING: connection status
--CONNECTED: connection status
--DISCONNECTING: disconnected state

function tmqtt:getstatus()
	if self.mqttconnected then
		return self.discing and "DISCONNECTING" or "CONNECTED"
	elseif self.sckconnected or self.sckconning then
		return "CONNECTING"
	else
		return "DISCONNECTED"
	end
end
