require"link"
module(...,package.seeall)

local lstate,scks = link.getstate,{}
SCK_MAX_CNT = 5
NORMAL,SVR_CHANGE,DISCTHENTRY = 0,1,2

local function print(...)
	_G.print("socket",...)
end

local function checkidx(cause,idx,fnm)
	if (cause == 0 and idx <= SCK_MAX_CNT) or (cause == 1 and scks[idx]) then
		return true
	else
		print("checkidx "..fnm.." err",idx)
	end
end

local function checkidx1(idx,fnm)
	return checkidx(0,idx,fnm) and checkidx(1,idx,fnm)
end

local function getidxbyid(id)
	local i
	for i=1,SCK_MAX_CNT do
		if scks[i] and scks[i].id == id then return i end
	end
end

local function conrstpara(idx,suc)
	if not checkidx(1,idx,"conrstpara") then return end
	scks[idx].conretry,scks[idx].concause = 0
	if not suc then	scks[idx].sndpending,scks[idx].sndingitem = {},{} end
	scks[idx].waitingrspitem = {}
end

local function sndrstpara(idx)
	if not checkidx(1,idx,"sndrstpara") then return end
	scks[idx].sndretry,scks[idx].sndingitem = 0,{}
end

local function discrstpara(idx)
	if not checkidx(1,idx,"discrstpara") then return end
	scks[idx].discause = nil
end

local function rsumscksnd(idx)
	if not checkidx(1,idx,"rsumscksnd") then return end
	if lstate(scks[idx].id) ~= "CONNECTED" then
		return link.connect(scks[idx].id,scks[idx].prot,scks[idx].addr,scks[idx].port)
	else
		if #scks[idx].sndpending ~= 0 and not scks[idx].sndingitem.data and not scks[idx].waitingrspitem.data then
			local item = table.remove(scks[idx].sndpending,1)
			if link.send(scks[idx].id,item.data) then
				scks[idx].sndingitem = item
			else
				table.insert(scks[idx].sndpending,1,item)
			end
		end
	end
	return true
end

function setwaitingrspitem(idx,item)
	if not checkidx(1,idx,"setwaitingrspitem") then return end
	scks[idx].waitingrspitem = item
	if not item.data then
		rsumscksnd(idx)
	end
end

local function conack(idx,cause,suc)	
	if #scks[idx].sndpending ~= 0 and not suc then
		while #scks[idx].sndpending ~= 0 do
			scks[idx].rsp(idx,"SEND",suc,table.remove(scks[idx].sndpending,1))
		end
	end
	scks[idx].rsp(idx,"CONNECT",suc,cause)
	conrstpara(idx,suc)
end

local function sndnxt(id,idx)
	local item = table.remove(scks[idx].sndpending,1)
	if link.send(id,item.data) then
		scks[idx].sndingitem = item
	else
		table.insert(scks[idx].sndpending,1,item)
	end
end

local function sndack(idx,suc,item)
	sndrstpara(idx)
	scks[idx].rsp(idx,"SEND",suc,item)	
	if #scks[idx].sndpending ~= 0 and not suc then
		while #scks[idx].sndpending ~= 0 do
			scks[idx].rsp(idx,"SEND",suc,table.remove(scks[idx].sndpending,1))
		end
	end
end

local function sckrsp(id,evt,val)-- The status of this connection notification and processing procedures

	local idx = getidxbyid(id)
	if not idx then print("sckrsp err idx",id,evt,val) return end
	print("sckrsp",id,evt,val)

	if evt == "CONNECT" then
		local cause = scks[idx].concause
		if val ~= "CONNECT OK" then
			scks[idx].conretry = scks[idx].conretry + 1
			if scks[idx].conretry >= 1 then
				conack(idx,cause,false)
			else
				if not link.connect(id,scks[idx].prot,scks[idx].addr,scks[idx].port) then
					conack(idx,cause,false)
				end
			end
		else
			conack(idx,cause,true)
			if #scks[idx].sndpending ~= 0 and not scks[idx].sndingitem.data then
				sndnxt(id,idx)
			end
		end
	elseif evt == "SEND" then
		local item = scks[idx].sndingitem
		if val ~= "SEND OK" then
			scks[idx].sndretry = scks[idx].sndretry + 1
			if scks[idx].sndretry >= 1 then
				sndack(idx,false,item)
			else
				if not link.send(id,item.data) then--- Send data to the server

					sndack(idx,false,item)
				end
			end
		else
			sndack(idx,true,item)
			if #scks[idx].sndpending ~= 0 and not scks[idx].sndingitem.data and not scks[idx].waitingrspitem.data then
				sndnxt(id,idx)
			end
		end
	elseif evt == "DISCONNECT" then
		local cause = scks[idx].discause
		discrstpara(idx)
		if cause == SVR_CHANGE or #scks[idx].sndpending ~= 0 then
			--link.connect(id,scks[idx].prot,scks[idx].addr,scks[idx].port)
			scks[idx].concause = cause
		end
		scks[idx].rsp(idx,"DISCONNECT",true,cause)
	elseif evt == "CLOSE" then
		scks[idx].rsp(idx,"CLOSE",true)
		scks[idx] = nil
	elseif evt == "STATE" and val == "CLOSED" then
		if #scks[idx].sndpending ~= 0 then
			--link.connect(id,scks[idx].prot,scks[idx].addr,scks[idx].port)
			while #scks[idx].sndpending ~= 0 do
				scks[idx].rsp(idx,"SEND",false,table.remove(scks[idx].sndpending,1))
			end
		end
		scks[idx].rsp(idx,evt,val,nil)
	else
		scks[idx].rsp(idx,evt,val,nil)
	end
end

local function sckrcv(id,data)-- This connection received data processing procedures

	scks[getidxbyid(id)].rcv(getidxbyid(id),data)
end

function clrsnding(idx)
	if not checkidx1(idx,"clrsnding") then return end
	iscks[idx].sndpending = {}
end

local function init(idx,id,cause,prot,addr,port,rsp,rcv,discause)
	scks[idx] =
	{
		id = id,
		addr = addr,
		port = port,
		prot = prot,
		conretry = 0,
		sndretry = 0,
		sndpending = {},
		sndingitem = {},
		waitingrspitem = {},
		rsp = rsp,
		rcv = rcv,
		concause = cause,
		discause = discause,
	}
end


--Function name: create
--Function: Create socket (if socket does not exist)
--Parameters:
--idx: number type, socket id. If the mqtt module is used, the value range is 1, 2, and 3. If you do not use the mqtt module, the value range is 1, 2, 3, [required]
--prot: string type, transport layer protocol, currently only supports "TCP" and "UDP"
--addr: string type, server address, support IP address and domain name
--port: number type, server port
--rsp: function type, socket state processing function
--rcv: function type, socket data reception and processing functions
--cause: temporary useless, follow-up expansion use
--Return Value: true means that socket was successfully created, false means that it was not created successfully

function create(idx,prot,addr,port,rsp,rcv,cause)
	if not checkidx(0,idx,"create") or checkidx(1,idx,"create") then return end
	init(idx,link.open(sckrsp,sckrcv),cause,prot,addr,port,rsp,rcv)
	return true
end

--Function name: connect
--Function: Create a socket (if the socket does not exist), and connect to the server
--Parameters:
--idx: number type, socket id. If the mqtt module is used, the value range is 1, 2, and 3. If you do not use the mqtt module, the value range is 1, 2, 3, [required]
--prot: string type, transport layer protocol, currently only supports "TCP" and "UDP"
--addr: string type, server address, support IP address and domain name
--port: number type, server port
--rsp: function type, socket state processing function
--rcv: function type, socket data reception and processing functions
--cause: temporary useless, follow-up expansion use
--Return Value: true means that the connection interface is successfully called (the connection result will be notified asynchronously to the socket status handler), false means that the connection interface is not successfully invoked

function connect(idx,prot,addr,port,rsp,rcv,cause)
	if not checkidx(0,idx,"connect") then return end
	local discause,sckid
	if scks[idx] then
		sckid = scks[idx].id
		if link.getstate(sckid) == "CONNECTED" then
			if scks[idx].addr == addr and scks[idx].port == port and scks[idx].prot == prot then
				return true
			else
				if link.disconnect(sckid) then discause = cause	end
			end
		else
			if not link.connect(sckid,prot,addr,port) then
				print("connect fail1")
				return false
			end
		end
	else
		sckid = link.open(sckrsp,sckrcv)
		if not link.connect(sckid,prot,addr,port) then
			print("connect fail2")
			return false
		end
	end
	init(idx,sckid,cause,prot,addr,port,rsp,rcv,discause)

	return true
end

--Function name: send
--Function: send data
--Parameters:
--idx: number type, socket id. If the mqtt module is used, the value range is 1, 2, and 3. If you do not use the mqtt module, the value range is 1, 2, 3, [required]
--data: data to send
--para: the parameters sent
--pos: temporary useless, follow-up expansion
--ins: temporary useless, follow-up expansion
--Return Value: true means that the sending interface was successfully invoked (the sending result will be notified asynchronously to the socket status handler), false means that the sending interface has not been successfully invoked

function send(idx,data,para,pos,ins)
	if not checkidx1(idx,"send") then return end
	if not data or string.len(data) == 0 then print("send data empty") return end

	local sckid = scks[idx].id
	local item,tail = {data = data, para = para},#scks[idx].sndpending+1

	if lstate(sckid) ~= "CONNECTED" then
		local res = link.connect(sckid,scks[idx].prot,scks[idx].addr,scks[idx].port)
		if res or (not res and ins) then
			table.insert(scks[idx].sndpending,pos or tail,item)
		else
			return
		end
	else
		if scks[idx].sndingitem.data or scks[idx].waitingrspitem.data then
			table.insert(scks[idx].sndpending,pos or tail,item)
		else
			if link.send(sckid,data) then  --send data

				scks[idx].sndingitem = item
			else
				return
			end
		end
	end
	return true
end

--Function name: disconnect
--Function: disconnect a socket connection
--Parameters:
--idx: number type, socket id. If the mqtt module is used, the value range is 1, 2, and 3. If you do not use the mqtt module, the value range is 1, 2, 3, [required]
--cause: currently useless, follow-up expansion use [optional]
--Return Value: true means that the interface was successfully called (the result of the disconnection will be notified asynchronously to the socket's state handler), and false means that the interface has not been successfully disconnected

function disconnect(idx,cause)
	if not checkidx1(idx,"disconnect") then return end
	scks[idx].discause = cause
	return link.disconnect(scks[idx].id) --πÿ±’¡¨Ω”
end

--Function name: close
--Function: disconnect a socket connection, and destroyed
--Parameters:
--idx: number type, socket id. If the mqtt module is used, the value range is 1, 2, and 3. If you do not use the mqtt module, the value range is 1, 2, 3, [required]
--Return Value: true means that the interface was successfully called (the result of the disconnection will be notified asynchronously to the socket's state handler), and false means that the interface has not been successfully disconnected

function close(idx)
	if not checkidx1(idx,"close") then return end
	return link.close(scks[idx].id) -- Destroy the connection

end

function isactive(idx)
	if not checkidx1(idx,"isactive") then return end	
	return link.getstate(scks[idx].id) == "CONNECTED"
end

-- Very long ago core internal bug, connect the background, for a long time did not get the feedback of the connection results, then take the way to avoid dealing with lua, if no feedback for 90 seconds, to restart the software
-- The latest core has solved this problem, lua this circumvention measures have not been removed, retain just one more layer of insurance
link.setconnectnoretrestart(true,90000)

