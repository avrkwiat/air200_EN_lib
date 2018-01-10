
--Module Name: Call Test
--Module function: test incoming call exhaled
--Last modified: 2017.02.23


module(...,package.seeall)
require"cc"
require"audio"
require"common"

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--Function name: connected
--Function: "Call established" message handler
--Parameters: None
--Return Value: None

local function connected()
	print("connected")	
	-- Play TTS to the peer after 5 seconds, the underlying software must support TTS function
	sys.timer_start(audio.play,5000,0,"TTSCC",common.binstohexs(common.gb2312toucs2("通话中播放TTS测试")),audiocore.VOL7)	
	-- 50 seconds after the active end of the call
	sys.timer_start(cc.hangup,50000,"AUTO_DISCONNECT")
end


--Function name: disconnected
--Function: "Call ended" message handler
--Parameters:
--para: call termination reason value
--"LOCAL_HANG_UP": The user calls the cc.hangup interface to hang up the call
--"CALL_FAILED": The user calls out of the cc.dial interface and the at command fails
--"NO CARRIER": Call No Answer
--"BUSY": Busy
--"NO ANSWER": No answer for call
--Return Value: None

local function disconnected(para)
	print("disconnected:"..(para or "nil"))
	sys.timer_stop(cc.hangup,"AUTO_DISCONNECT")
end


--Function name: incoming
--Function: "Incoming" message handler
--Parameters:
--num: string type, caller ID
--Return Value: None

local function incoming(num)
	print("incoming:"..num)	
	-- answer the call
	cc.accept()
end


--Function name: ready
--Function: "Call function module ready" message processing function
--Parameters: None
--Return Value: None

local function ready()
	print("ready")
	-- Call 10086
	cc.dial("10086")
end


--Function name: dtmfdetected
--Function: "Call each other's DTMF" message processing function
--Parameters:
--dtmf: string type, DTMF characters received
--Return Value: None

local function dtmfdetected(dtmf)
	print("dtmfdetected",dtmf)
end


--Function name: alerting
--Function: "Ringing message has been received during call" message processing function
--Parameters: None
--Return Value: None

local function alerting()
	print("alerting")
end

-- User callback function to register messages
cc.regcb("READY",ready,"INCOMING",incoming,"CONNECTED",connected,"DISCONNECTED",disconnected,"DTMF",dtmfdetected,"ALERTING",alerting)
