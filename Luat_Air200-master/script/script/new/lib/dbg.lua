
--Module Name: Error Management
--Module Function: Report syntax errors at run time, script control restart reason
--Module last modified: 2017.02.20

-- Define module, import dependent libraries
module(...,package.seeall)
local link = require"link"
local misc = require"misc"

--FREQ: Report interval in milliseconds. If no response is received after the error message is reported, it will be reported every time this interval
--prot, addr, port: transport layer protocol (TCP or UDP), background address and port
--lid: socket id
--linksta: connection status, true connection is successful, false is failed
local FREQ,prot,addr,port,lid,linksta = 1800000
--DBG_FILE: Wrong file path
--inf: Error in DBG_FILE and error message in LIB_ERR_FILE in sys.lua
--luaerr: "/ luaerrinfo.txt" error message
local DBG_FILE,inf,luaerr,d1,d2 = "/dbg.txt",""

--Function name: readtxt
--Function: read the entire contents of the text file
--Parameters:
--f: file path
--Return Value: The entire contents of the text file, read failed to empty string or nil

local function readtxt(f)
	local file,rt = io.open(f,"r")
	if file == nil then
		print("dbg can not open file",f)
		return ""
	end
	rt = file:read("*a")
	file:close()
	return rt or ""
end

--Function name: writetxt
--Function: Write a text file
--Parameters:
--f: file path
--v: text content to be written
--Return Value: None

local function writetxt(f,v)
	local file = io.open(f,"w")
	if file == nil then
		print("dbg open file to write err",f)
		return
	end
	file:write(v)
	file:close()
end

--Function name: writerr
--Function: Write information to the wrong file
--Parameters:
--append: Append to the end
--s: error message
--Return Value: None
--Explanation: Up to 900 bytes of data are saved in the error file

local function writerr(append,s)	
	print("dbg_w",append,s)
	if s then
		local str = (append and (readtxt(DBG_FILE)..s) or s)
		if string.len(str)>900 then
			str = string.sub(str,-900,-1)
		end
		writetxt(DBG_FILE,str)
	end
end

--Function name: initerr
--Function: read the error message from the error file
--Parameters: None
--Return Value: None

local function initerr()
	inf = (sys.getextliberr() or "")..(readtxt(DBG_FILE) or "")
	print("dbg inf",inf)
end

--Function name: getlasterr
--Function: Get syntax error of lua runtime
--Parameters: None
--Return Value: None

local function getlasterr()
	luaerr = readtxt("/luaerrinfo.txt") or ""
end

--Function name: valid
--Function: Is there any wrong information to report?
--Parameters: None
--Return Value: true need to report, false do not need to report

local function valid()
	return ((string.len(luaerr) > 0) or (string.len(inf) > 0)) and _G.PROJECT
end

--Function name: rcvtimeout
--Function: Send error message to the background, the timeout did not receive OK reply, overtime processing function
--Parameters: None
--Return Value: None

local function rcvtimeout()
	endntfy()
	link.close(lid)
end


--Function name: snd
--Function: Send error message to the background
--Parameters: None
--Return Value: None

local function snd()
	local data = (luaerr or "") .. (inf or "")
	if string.len(data) > 0 then
		link.send(lid,_G.PROJECT .."_"..sys.getcorever() .. "," .. (_G.VERSION and (_G.VERSION .. ",") or "") .. misc.getimei() .. "," .. data)
		sys.timer_start(snd,FREQ)
		sys.timer_start(rcvtimeout,20000)
	end
end

-- The number of reconnections after the connection failed

local reconntimes = 0

--Function name: reconn
--Function: connect the background after the failure, re-processing
--Parameters: None
--Return Value: None

local function reconn()
	if reconntimes < 3 then
		reconntimes = reconntimes+1
		link.connect(lid,prot,addr,port)
	else
		endntfy()
	end
end

--Function name: endntfy
--Function: A dbg function cycle is over
--Parameters: None
--Return Value: None

function endntfy()
	sys.setrestart(true,2)
	sys.timer_stop(sys.setrestart,true,2)
	sys.dispatch("DBG_END_IND")
	sys.timer_stop(sys.dispatch,"DBG_END_IND")
end

--Function name: nofity
--Function: Socket state processing function
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? evt: message event type
--val: message event parameter
--Return Value: None

local function notify(id,evt,val)
	print("dbg notify",id,evt,val)
	if id ~= lid then return end
	if evt == "CONNECT" then
		if val == "CONNECT OK" then
			linksta = true
			sys.timer_stop(reconn)
			reconntimes = 0
			snd()
		else
			sys.timer_start(reconn,5000)
		end
	elseif evt=="DISCONNECT" or evt=="CLOSE" then
		linksta = false
	elseif evt == "STATE" and val == "CLOSED" then
		link.close(lid)
	end
end

--Function name: recv
--Function: socket to receive data processing functions
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
--???????? data: received data
--Return Value: None

local function recv(id,data)
	if string.upper(data) == "OK" then
		sys.timer_stop(snd)
		link.close(lid)
		inf = ""
		writerr(false,"")
		luaerr = ""
		os.remove("/luaerrinfo.txt")
		endntfy()
		sys.timer_stop(rcvtimeout)
	end
end

--Function name: init
--Function: Initialize
--Parameters:
--???????? id: socket id, the program can ignore does not deal with
-???????? data: received data
--Return Value: None

local function init()
	-- Error reading wrong file

	initerr()
	-- Get lua runtime syntax error

	getlasterr()
	if valid() then
		if linksta then
			snd()
		else
			lid = link.open(notify,recv,"dbg")
			link.connect(lid,prot,addr,port)
		end
		sys.dispatch("DBG_BEGIN_IND")
		sys.timer_start(sys.dispatch,120000,"DBG_END_IND")
	else
		sys.setrestart(true,2)
		sys.timer_stop(sys.setrestart,true,2)
	end
end

--Function name: restart
--Function: Restart
--Parameters:
--???????? r: Reboot reason
--Return Value: None

function restart(r)
	writerr(true,"dbg.restart:" .. (r or "") .. ";")
	rtos.restart()
end

--Function name: saverr
--Function: Save the error message
--Parameters:
--???????? s: error message
--Return Value: None

function saverr(s)
	writerr(true,s)
	init()
end

--Function name: setup
--Function: Configure transfer protocol, background address and port
--Parameters:
--???????? inProt: transport layer protocol that supports only TCP and UDP
--inAddr: background address
--inPort: background port
--Return Value: None

function setup(inProt,inAddr,inPort)
	if inProt and inAddr and inPort then
		prot,addr,port = inProt,inAddr,inPort
		init()
	end
end

sys.setrestart(false,2)
sys.timer_start(sys.setrestart,120000,true,2)
