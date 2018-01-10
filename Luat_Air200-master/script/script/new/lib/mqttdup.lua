
--Module Name: publish packet retransmission management
--Module Function: publish messages for QoS retransmission processing
--?????????? After sending the publish message, if puback is not received within DUP_TIME seconds, it will be retransmitted automatically. Up to DUP_CNT times will be retransmitted. If no puback is received, no retransmission will be made, an MQTT_DUP_FAIL message will be thrown, and then discarded
--Last modified: 2017.02.24

module(...,package.seeall)

--DUP_TIME: send publish message, DUP_TIME seconds to determine whether you have received puback
--DUP_CNT: The maximum number of publish messages that do not receive puback packets
--tlist: publish message storage table
local DUP_TIME,DUP_CNT,tlist = 10,3,{}
local slen = string.len

--Function name: print
--Function: Print Interface, all print in this file will be added mqttdup prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("mqttdup",...)
end

--Function name: timerfnc
--Function: 1 second timer handler, query whether the publish message in tlist needs to be retransmitted by the time
--Parameters: None
--Return Value: None

local function timerfnc()
	print("timerfnc")
	for i=1,#tlist do
		print(i,tlist[i].tm)
		if tlist[i].tm > 0 then
			tlist[i].tm = tlist[i].tm-1
			if tlist[i].tm == 0 then
				sys.dispatch("MQTT_DUP_IND",tlist[i].sckidx,tlist[i].dat)
			end
		end
	end
end

--Function name: timer
--Function: Turn on or off the timer for 1 second
--Parameters:
--start: on or off, true on, false or nil off
--Return Value: None

local function timer(start)
	print("timer",start,#tlist)
	if start then
		if not sys.timer_is_active(timerfnc) then
			sys.timer_loop_start(timerfnc,1000)
		end
	else
		if #tlist == 0 then sys.timer_stop(timerfnc) end
	end
end

--Function name: ins
--Function: Insert a publish message into the storage table
--Parameters:
--sckidx: socket idx
--typ: for a custom type
--dat: publish message data
--seq: publish message serial number
--cb: user callback function
--cbtag: The first parameter of the user callback function
--Return Value: None

function ins(sckidx,typ,dat,seq,cb,cbtag)
	print("ins",typ,(slen(dat or "") > 200) and "" or common.binstohexs(dat),seq or "nil" or common.binstohex(seq))
	table.insert(tlist,{sckidx=sckidx,typ=typ,dat=dat,seq=seq,cb=cb,cbtag=cbtag,cnt=DUP_CNT,tm=DUP_TIME})
	timer(true)
end

--Function name: rmv
--Function: delete a publish message from the storage table
--Parameters:
--sckidx: socket idx
--typ: for a custom type
--dat: publish message data
--seq: publish message serial number
--Return Value: None

function rmv(sckidx,typ,dat,seq)
	print("rmv",typ or getyp(seq),(slen(dat or "") > 200) and "" or common.binstohexs(dat),seq or "nil" or common.binstohex(seq))
	for i=1,#tlist do
		if (sckidx == tlist[i].sckidx) and (not typ or typ == tlist[i].typ) and (not dat or dat == tlist[i].dat) and (not seq or seq == tlist[i].seq) then
			table.remove(tlist,i)
			break
		end
	end
	timer()
end

--Function name: rmvall
--Function: Delete all publish messages from storage table
--Parameters:
--sckidx: socket idx
--Return Value: None

function rmvall(sckidx)
	tlist = {}
	for i=#tlist,1,-1 do
		if sckidx == tlist[i].sckidx then
			table.remove(tlist,i)
		end
	end
	timer()
end

--Function name: rsm
--Function: Callback processing after resending a publish message
--Parameters:
--sckidx: socket idx
--s: publish message data
--Return Value: None

function rsm(sckidx,s)
	for i=1,#tlist do
		if sckidx==tlist[i].sckidx and tlist[i].dat==s then
			tlist[i].cnt = tlist[i].cnt - 1
			if tlist[i].cnt == 0 then
				sys.dispatch("MQTT_DUP_FAIL",tlist[i].sckidx,tlist[i].typ,tlist[i].seq,tlist[i].cb,tlist[i].cbtag)
				rmv(tlist[i].sckidx,nil,s) 
				return 
			end
			tlist[i].tm = DUP_TIME			
			break
		end
	end
end

--Function name: getyp
--Function: According to the serial number to find publish message user-defined type
--Parameters:
--sckidx: socket idx
--seq: publish message serial number
--Return Value: The user-defined type, the user callback function, the first parameter of the user callback function

function getyp(sckidx,seq)
	for i=1,#tlist do
		if seq and seq == tlist[i].seq and sckidx==tlist[i].sckidx then
			return tlist[i].typ,tlist[i].cb,tlist[i].cbtag
		end
	end
end
