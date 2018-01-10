
--Module Name: GPS Management
--Module features: GPS open and close, GPS NEMA data analysis, GPS latitude and longitude speed and other functional interfaces
--Last modified: 2017.02.21

-- Define module, import dependent libraries
local base = _G
local table = require"table"
local uart = require"uart"
local rtos = require"rtos"
local sys = require"sys"
local pio = require"pio"
local pm = require"pm"
local pmd = require"pmd"
local string = require"string"
local common = require"common"
local misc = require"misc"
local os = require"os"
local pack = require"pack"
module(...,package.seeall)

-- Load common global functions to local

local print = base.print
local tonumber = base.tonumber
local tostring = base.tostring
local pairs = base.pairs
local smatch = string.match
local sfind = string.find
local slen = string.len
local ssub = string.sub
local smatch = string.match
local sbyte = string.byte
local sformat = string.format
local srep = string.rep

--gps global information table

local gps = {}
-- Control Function Global Information Table

local c = {}
-- Whether to throw NEMA data for external application processing

local nmea_route
-- Serial read NEMA data buffer

local strgps = ""

-- The following messages and events are parameters used by the function module to generate internal messages. The function modules of the external application can register message processing functions to identify messages and events
-- GPS internal message ID
GPS_STATE_IND = "GPS_STATE_IND"
-- GPS shutdown event

GPS_CLOSE_EVT = 0
--GPS open event

GPS_OPEN_EVT = 1
-- GPS positioning success event (filtering data of the previous period)

GPS_LOCATION_SUC_EVT = 2
-- GPS positioning failure event

GPS_LOCATION_FAIL_EVT = 3
-- No GPS chip event

GPS_NO_CHIP_EVT = 4
--There are GPS chip events

GPS_HAS_CHIP_EVT = 5
-- GPS positioning success event (have not filtered the data of the previous period)

GPS_LOCATION_UNFILTER_SUC_EVT = 6

-- Power saving mode

GPS_POWER_SAVE_MODE = 0
-- Continuous positioning mode

GPS_CONTINUOUS_MODE = 1
-- Only support Beidou positioning

GPS_SINGLE_BEIDOU_GNSS = 2
-- GPS positioning only

GPS_SINGLE_GPS_GNSS = 3
-- GPS and Beidou hybrid positioning

GPS_MIX_GNSS = 4
-- NEMA protocol version

GPS_NMEA_VERSION = 5
-- Query PACC

QRY_PACC = 6

-- Latitude and longitude for the degree of format

GPS_DEGREES = 0
-- Latitude and longitude for the format of the degree

GPS_DEGREES_MINUTES = 1

--Greenwich Mean Time

GPS_GREENWICH_TIME = 0
--Beijing time

GPS_BEIJING_TIME = 1
-- Vietnam time

GPS_VIETNAM_TIME = 2

-- The speed unit is nautical miles per hour

GPS_KNOT_SPD = 0
-- The speed unit is kilometers per hour

GPS_KILOMETER_SPD = 1

--nogpschipcnt: gps open, if you read nogpschipcnt secondary serial port, did not receive the data, then that there is no GPS chip
--hdop, paccflg, paccqry, pacc: 4 parameters to determine gps positioning accuracy
local nogpschipcnt,hdop,paccflg,paccqry,pacc = 5

--Function name: abs
--Function: Find the absolute value of the difference between two numbers
--Parameters:
--v1: the first number
--v2: the second number
--Return Value: The absolute value of the difference

local function abs(v1,v2)
	return ((v1>v2) and (v1-v2) or (v2-v1))
end

--[[
local function emptyque()
	gps.dataN,gps.A,gps.L = 0,{},{}
end
]]

local function getmilli(v,vr)
	local L,ov1,v1,v2,R,T,OT = slen(v)
	if (L ~= 4 and L ~= 5) or slen(vr) ~= 5 then
		print("gps data not right", v, vr)
		return
	end
	v2 = ssub(v,1,L-2)
	v1 = tostring(tonumber(ssub(v,L-1,L) .. vr)*10/6)
	ov1 = ssub(v,L-1,L) .. vr
	L = slen(v1)
	if L > 7 then
		v1 = ssub(v1,1,7)
	elseif L < 7 then
		v1 = srep("0", 7-L) .. v1
	end
	L = slen(ov1)
	if L > 7 then
		ov1 = ssub(ov1,1,7)
	elseif L < 7 then
		ov1 = ov1 .. string.rep("0", 7-L)
	end

	T = v2 .. "." .. v1
	OT = v2 .. "." .. ov1
	R = tonumber(v2..ssub(v1,1,5)) * 36 + tonumber(ssub(v1,6,7))*36/100
	return OT,T,R
end

--Function name: getstrength
--Function: Analyze GSV data
--Parameters:
--sg: One line of GSV data in NEMA
--Return Value: None

local function getstrength(sg)
	local d1,d2,curnum,lineno,total,sgv_str = sfind(sg,gps.gsvprefix.."GSV,(%d),(%d),(%d+),(.*)%*.*")
	if not curnum or not lineno or not total or not sgv_str then
		return
	end
	if tonumber(lineno)== 1  then
		gps.sates = ""
		gps.sn = 0
		--gps.gsv = ""
	end

	local tmpstr,i = sgv_str
	for i=1,4 do
		local d1,d2,id,elevation,azimuth,strength = sfind(tmpstr,"(%d+),(%d*),(%d*),(%d*)")
		if id == nil then
			return
		end
		if strength == "" or not strength then
			strength = "00"
		end
		strength = tonumber(strength)
		if strength and strength < 60 then
			gps.sates = gps.sates .. id .. string.format("%02d",strength) .. " "
			if strength > gps.sn then
				gps.sn = strength
			end
		end
		local idx,cur,fnd,tmpid = 0,id..","..elevation..","..azimuth..","..strength..",",false
		for tmpid in string.gmatch(gps.gsv,"(%d+),%d*,%d*,%d*,") do
			idx = idx + 1
			if tmpid == id then fnd = true break end
		end
		if fnd then
			local pattern,i = ""
			for i=1,idx do
				pattern = pattern.."%d+,%d*,%d*,%d*,"
			end
			local m1,m2 = sfind(gps.gsv,"^"..pattern)
			if m1 and m2 then
				local front = ssub(gps.gsv,1,m2)
				local n1,n2 = sfind(front,"%d+,%d*,%d*,%d*,$")
				if n1 and n2 then
					if (gps.gsvprefix == "GP" and tonumber(id) <= 32) or gps.gsvprefix == "" then
						gps.gsv = ssub(gps.gsv,1,n1-1)..cur..ssub(gps.gsv,n2+1,-1)
					end
				end
			end
		else
			if (gps.gsvprefix == "GP" and tonumber(id) <= 32) or gps.gsvprefix == "" then
				gps.gsv = gps.gsv..cur
			end
		end
		
		tmpstr = ssub(tmpstr,d2+1,-1)
	end
end

local function getvg(A,L)
	local A1,A2,L1,L2,t1
	t1 = slen(L)
	A1 = ssub(A,1,4)
	A2 = ssub(A,5,8).."0"
	L1 = ssub(L,1,t1-4)
	L2 = ssub(L,t1-3,t1).."0"
	return A1,A2,L1,L2
end

--[[
local function getd(I)
	return abs(gps.A[I],gps.A[I-1]) + abs(gps.L[I],gps.L[I-1])
end
]]

local function push(A,L)
	--print("push", A, L)
	--table.insert(gps.A, A)
	--table.insert(gps.L, L)
--	gps.dataN = gps.dataN + 1
--	if gps.dataN > gps.QueL then
--		table.remove(gps.A, 1)
	--	table.remove(gps.L, 1)
		--local a1,a2,I
		--I = (gps.QueL+1)/2
		--a1 = getd(I) + getd(I+1)
		--a2 = 0
		--for i = 2, gps.QueL do
	--		if i ~= I and i ~= (I+1) then
	--			a2 = a2 + getd(i)
	--		end
	--	end
	--	if a2 < gps.errL*(gps.QueL-2) and a1 > gps.errD then
	--		print("gps run", gps.A[I], gps.L[I])
	--		gps.A[I] = gps.A[I+1]
	--		gps.L[I] = gps.L[I+1]
	--	end
	--	return getvg(gps.A[I], gps.L[I])
--	end
	return getvg(A,L)
end

local function filter(LA,RA,LL,RL)
	--print("gps data", LA,RA,LL,RL,gps.dataN,gps.cgen)

	--[[if (c.gps - gps.cgen) > 10 then
		print("longtime no gps",c.gps,gps.cgen)
		emptyque()
	end]]

	if slen(LA) ~= 4 or (slen(LL) ~= 5 and slen(LL) ~= 4) then
		print("err LA or LL", LA, LL)
		return
	end

	if slen(RA) < 4 then
		RA = RA .. srep("0", 4 - slen(RA))
	end
	if slen(RL) < 4 then
		RL = RL .. srep("0", 4 - slen(RL))
	end
	local A = LA .. ssub(RA,1,4)
	local L = LL .. ssub(RL,1,4)
	A = tonumber(A) or 0
	L = tonumber(L) or 0

	gps.cgen = c.gps
	return push(A, L)
end

--Function name: rtctolocal
--Function: GPS time is converted to the time zone set in this module
--Parameters:
--y, m, d, hh, mm, ss: Year, month, day, day, minute, and second in GPS time
--Return Value: The time zone time set in this module (table type, t.year, t.month, t.day, t.hour, t.min, t.sec)

local function rtctolocal(y,m,d,hh,mm,ss)
	--print("rtctolocal",y,m,d,hh,mm,ss)
	local flg
	if not y or not m or not d or not hh or not mm or not ss then
		return
	end
	if gps.timezone == GPS_BEIJING_TIME then
		hh = hh + 8
		flg = true
	elseif gps.timezone == GPS_VIETNAM_TIME then
		hh = hh + 7
		flg = true
	end
	if flg then
		if hh >= 24 then
			hh = hh - 24
			d = d + 1
			if m == 4 or m == 6 or m == 9 or m == 11 then
				if d > 30 then
					d = 1
					m = m + 1
				end
			elseif m == 1 or m == 3 or m == 5 or m == 7 or m == 8 or m == 10 then
				if d > 31 then
					d = 1
					m = m + 1
				end
			elseif m == 12 then
				if d > 31 then
					d = 1
					m = 1
					y = y + 1
				end
			elseif m == 2 then
				if (((y+2000)%400) == 0) or (((y+2000)%4 == 0) and ((y+2000)%100 ~=0)) then
					if d > 29 then
						d = 1
						m = 3
					end
				else
					if d > 28 then
						d = 1
						m = 3
					end
				end
			end
		end
	end
	local t = {}
	t.year,t.month,t.day,t.hour,t.min,t.sec = 2000 + y,m,d,hh,mm,ss
	return t
end

--Function name: needupdatetime
--Function: Whether to update the system time to new time
--Parameters:
--newtime: new time
--Return Value: true needs to be updated, false does not need to be updated

function needupdatetime(newtime)
	if newtime and os.time(newtime) and os.date("*t") and os.time(os.date("*t")) then
		local secdif = os.difftime(os.time(os.date("*t")),os.time(newtime))
		if secdif and secdif >= 60 or secdif <= -60 then
			print("needupdatetime",secdif)
			return true
		end
	end
	return false
end

--Function name: proc
--Function: Processing each NEMA data
--Parameters:
--s: a piece of NEMA data
--Return Value: None

local function proc(s)
	local latti,lattir,longti,longtir,spd1,cog1,gpsfind,gpstime,gpsdate,numofsate,numoflocationsate,hdp

	if s == "" or s == nil then
		return
	end

	gps.find = ""

	--GGA data

	if smatch(s, "GGA") then
		local hh,sep
		latti,lattir,gps.latyp,longti,longtir,gps.longtyp,gpsfind,numoflocationsate,hdp,hh,sep = smatch(s,"GGA,%d+%.%d+,(%d+)%.(%d+),([NS]),(%d+)%.(%d+),([EW]),(%d),(%d+),([%d%.]*),(.*),M,(.*),M")
		if (gpsfind == "1" or gpsfind == "2" or gpsfind == "4") and longti ~= nil and longtir ~= nil and latti ~= nil and lattir ~= nil then
			gps.find = "S"
			if hh ~= nil then
				gps.haiba = hh
			end
			if sep then gps.sep = sep end
			gps.ggalng,gps.ggalat = longti.."."..longtir,latti.."."..lattir
		end
		if hdp then hdop = hdp end
	-- RMC data

	elseif smatch(s, "RMC") then
		gpstime,gpsfind,latti,lattir,gps.latyp,longti,longtir,gps.longtyp,spd1,cog1,gpsdate = smatch(s,"RMC,(%d%d%d%d%d%d)%.%d+,(%w),(%d+)%.(%d+),([NS]),(%d+)%.(%d+),([EW]),(.-),(.-),(%d%d%d%d%d%d),")
		if gpsfind == "A" and longti ~= nil and longtir ~= nil and latti ~= nil and lattir ~= nil  then
			gps.find = "S"
		end
		if gpsfind == "A" and gpstime and gpsdate and gpstime ~= "" and gpsdate ~= "" then
			local yy,mm,dd,h,m,s = tonumber(ssub(gpsdate,5,6)),tonumber(ssub(gpsdate,3,4)),tonumber(ssub(gpsdate,1,2)),tonumber(ssub(gpstime,1,2)),tonumber(ssub(gpstime,3,4)),tonumber(ssub(gpstime,5,6))
			gps.utctime = {year=2000+yy,month=mm,day=dd,hour=h,min=m,sec=s}
			if gps.timezone then
				local newtime = rtctolocal(yy,mm,dd,h,m,s)
				if needupdatetime(newtime) then
					misc.setclock(newtime)
				end
			end
		end
	-- GSV data

	elseif smatch(s,"GSV") then
		numofsate = smatch(s,"GSV,%d+,%d+,(%d+),%d+,%d+,%d+,%d+")
		getstrength(s)
	-- GSA data

	elseif smatch(s,"GSA") then
		local satesn = smatch(s,"GSA,%w*,%d*,(%d*,%d*,%d*,%d*,%d*,%d*,%d*,%d*,%d*,%d*,%d*,%d*,)") or ""
		local mtch,num = true
		if gps.gsaprefix == "GP" then			
			for num in string.gmatch(satesn,"(%d*),") do
				if slen(num) > 0 and tonumber(num) > 32 then
					mtch = false
					break
				end
			end			
		end
		if mtch and slen(satesn) > 0 and smatch(satesn,"%d+,") then
			gps.satesn = satesn
		end
	end

	-- Positioning is successful

	if gps.find == "S" then
		if gps.filterbgn == nil and gps.filtertime > 0 then
			gps.filterbgn = c.gps
			gps.find = ""
			print("filter gps " .. gps.filtertime .. " secs begin")
			sys.dispatch(GPS_STATE_IND,GPS_LOCATION_UNFILTER_SUC_EVT)
			return
		elseif gps.filterbgn and c.gps - gps.filterbgn < gps.filtertime then
			gps.find = ""
			return
		end
	end

	-- The number of visible satellites

	numofsate = tonumber(numofsate or "0")
	if numofsate > 9 then
		numofsate = 9
	end
	if numofsate > 0 then
		gps.satenum = numofsate
	end

	-- Positioning the number of satellites used

	numoflocationsate = tonumber(numoflocationsate or "0")
	if numoflocationsate > 9 then
		numoflocationsate = 9
	end
	if numoflocationsate > 0 then
		gps.locationsatenum = numoflocationsate
	end

	--speed

	if spd1 and spd1 ~= "" then
		local r1,r2 = smatch(spd1, "(%d+)%.*(%d*)")
		if r1 then
			if gps.spdtyp == GPS_KILOMETER_SPD then
				gps.spd = (tonumber(r1)*1852/1000)
			else
				gps.spd = tonumber(r1)
			end
		end
	end
	
	-- Directional angle

	if cog1 and cog1 ~= "" then
		local r1,r2 = smatch(cog1, "(%d+)%.*(%d*)")
		if r1 then
			gps.cog = tonumber(r1)
			local r3 = abs(gps.cog, gps.lastcog)
			if r3 > 45 and r3 < 135 then
				gps.lastcog = gps.cog
				gps.cogchange = true
			else
				gps.cogchange = false
			end
		end
	end

	if gps.find ~= "S" then
		return
	end

	-- Latitude and longitude

	local LA, RA, LL, RL = filter(latti,lattir,longti,longtir)
	--print("filterg", LA, RA, LL, RL)
	if not LA or not RA or not LL or not RL then
		return
	end

	gps.olati, gps.lati, gps.latt_m  = getmilli(LA, RA)
	gps.olong, gps.long, gps.longt_m = getmilli(LL, RL)
	gps.long = gps.long or 0
	gps.lati = gps.lati or 0
	gps.olong = gps.olong or 0
	gps.olati = gps.olati or 0
end

--Function name: diffofloc
--Function: Calculate the straight line distance between two pairs of latitude and longitude (approximate)
--Parameters:
--latti1: latitude 1 (degrees format, for example 31.12345 degrees)
--longti1: longitude 1 (degree format)
--latti2: latitude 2 (degrees format)
--longti2: longitude 2 (degrees format)
--typ: distance type
--Returns: typ If true, returns the square sum of the straight line distance (in meters); otherwise returns the straight line distance (in meters)

function diffofloc(latti1, longti1, latti2, longti2,typ) --typ = true: Returns a + b; otherwise, it is a square sum

	local I1,I2,R1,R2,diff,d
	I1,R1=smatch(latti1,"(%d+)%.(%d+)")
	I2,R2=smatch(latti2,"(%d+)%.(%d+)")
	if not I1 or not I2 or not R1 or not R2 then
		return 0
	end

	R1 = I1 .. ssub(R1,1,5)
	R2 = I2 .. ssub(R2,1,5)
	d = tonumber(R1)-tonumber(R2)
	d = d*111/100
	if typ == true then
		diff =  (d>0 and d or (-d))
	else
		diff = d * d
	end
		
	I1,R1=smatch(longti1,"(%d+)%.(%d+)")
	I2,R2=smatch(longti2,"(%d+)%.(%d+)")
	if not I1 or not I2 or not R1 or not R2 then
		return 0
	end

	R1 = I1 .. ssub(R1,1,5)
	R2 = I2 .. ssub(R2,1,5)
	d = tonumber(R1)-tonumber(R2)
	if typ == true then
		diff =  diff + (d>0 and d or (-d))
	else
		diff =  diff + d*d
	end
	--diff =  diff + d*d
	print("all diff:", diff)
	return diff
end

local function startpaccqry(flg)
	if paccflg then
		if not flg and not paccqry then return end
		paccqry = true
		writegps(QRY_PACC)
	end
end

local function stoppaccqry()
	paccqry = nil
end

--Function name: setmnea
--Function: Set "whether to throw NEMA data and provide external application processing" flag
--Parameters:
--flg: true to throw NEMA data, false or nil not to be thrown; if thrown, the external application can register NEMA data by registering the handler for the internal message "GPS_NMEA_DATA"
--Return Value: None

function setmnea(flg)
	nmea_route = flg
end

--Function name: read
--Function: Serial data reception processing function
--Parameters: None
--Return Value: None

local function read()
	local gpsreadloop = true
	if gps.open then
		-- Start the timer for 1 second and read the serial data every second

		sys.timer_start(read,gps.period)
	end

	c.gps = c.gps + 1
	while gpsreadloop do
		strgps = strgps..writeack(uart.read(gps.uartid, "*l", 0))
		if slen(strgps) == 0 then
			-- Continuous read nogpschipcnt secondary serial port, no data, then there is no gps chip

			if not c.nogps and c.hasgps == 0 and c.gps >= nogpschipcnt then
				sys.dispatch(GPS_STATE_IND,GPS_NO_CHIP_EVT)
				c.nogps = true
				return
			end
			gpsreadloop = false
		else
			-- Serial data, then that gps chip

			if c.hasgps == 0 then
				c.hasgps = c.gps
				sys.dispatch(GPS_STATE_IND,GPS_HAS_CHIP_EVT)
			end
		end
		-- Read a row of NEMA data

		local d1,d2,itemstr = sfind(strgps,"\r\n")
		while d1 do
			itemstr = ssub(strgps,1,d1+1)
			strgps = ssub(strgps,d2+1,-1)
			-- Analyze a row of NEMA data

			proc(itemstr)
			-- If you need to throw NEMA data for external use

			if nmea_route then
				sys.dispatch('GPS_NMEA_DATA',itemstr)
			end
			if c.gpsprt ~= c.gps then
				c.gpsprt = c.gps
				print("gps rlt", gps.longtyp,gps.olong,gps.long,gps.latyp,gps.olati,gps.lati,gps.locationsatenum,gps.sn,gps.satenum)
			end
			-- Positioning is successful

			if gps.find == "S" then
				gps.findall = true
				c.gpsfind = c.gps
				local oldstat = gps.state
				gps.state = 1
				if oldstat ~= 1 or gps.gnsschange then
					gps.gnsschange = false
					sys.dispatch(GPS_STATE_IND,GPS_LOCATION_SUC_EVT)
					print("dispatch GPS_LOCATION_SUC_EVT")
					lastesttimerfunc()
					startlastesttimer()
					startpaccqry(true)
					c.fixitv = c.gps-c.fixbgn
				end
			-- Positioning failed

			elseif ((c.gps - c.gpsfind) > 20 or gps.gnsschange) and gps.state == 1 then
				print("location fail")
				if not gps.gnsschange then
					c.fixbgn = c.gps
					sys.dispatch(GPS_STATE_IND,GPS_LOCATION_FAIL_EVT)
					print("dispatch GPS_LOCATION_FAIL_EVT")				
					stoppaccqry()
				end
				lastesttimerfunc()
				gps.findall = false
				gps.state = 2
				gps.satenum = 0
				gps.locationsatenum = 0
				gps.filterbgn = nil
				gps.spd = 0			
			end
			d1,d2 = sfind(strgps,"\r\n")
		end

		
	end
end

function writeack(dat)
	if not dat or slen(dat) == 0 or not gps.curwritem or not gps.curwritem.ack then return dat end

	local hexdat = common.binstohexs(dat)
	local cmd = common.binstohexs(gps.curwritem.cmd)
	
	local d1,d2 = sfind(hexdat,"B56205")	
	if d1 and d2 and cmd then
		local ret,id = ssub(hexdat,d2+1,d2+2),ssub(hexdat,d2+7,d2+10)
		print("writeack",ret,id)
		if ret == "01" and id == ssub(cmd,5,8) then
			if id == "063E" then
				gps.gnsschange = true
			end
			resetwrite()
			write()
		elseif ret == "00" then
			sys.timer_stop(writetimeout)
			writetimeout()
		end
		return common.hexstobins(ssub(hexdat,1,d1-1) .. ssub(hexdat,d2+15,-1))
	end
	
	d1,d2 = sfind(hexdat,"B5620101")
	if d1 and d2 and cmd and paccflg then		
		resetwrite()
		write()
		local _,pac = pack.unpack(common.hexstobins(ssub(hexdat,d2+37,d2+44) or "00000000"),"<l")
		if pac then pacc = pac end
		startpaccqry()
	end
	return dat
end

local function writedata()
	gps.curwritem = table.remove(gps.wrquene,1)
	gps.retrywrcnt = 0
	uart.write(gps.uartid,gps.curwritem.cmd)
	print("gps write",common.binstohexs(gps.curwritem.cmd))
	if gps.curwritem.ack then
		sys.timer_start(writetimeout,1500)
	else
		gps.curwritem = nil
	end
end

function write()
	if gps.curwritem then return end

	if #gps.wrquene == 0 then
		closegps("WRGPS")
		return
	end

	if not gps.open then
		opengps("WRGPS")
		uart.write(gps.uartid,"\255")
		sys.timer_start(writedata,600)
		gps.curwritem = {}
	else
		writedata()
	end
end

function resetwrite()
	gps.curwritem = nil
	gps.retrywrcnt = 0
	sys.timer_stop(writetimeout)
end

function writetimeout()
	print("gps writetimeout",gps.retrywrcnt)
	if gps.retrywrcnt < gps.retrywrmaxcnt then
		uart.write(gps.uartid,gps.curwritem.cmd)
		sys.timer_start(writetimeout,1500)
		gps.retrywrcnt = gps.retrywrcnt + 1
	else
		resetwrite()
		write()
	end
end

function writegpscmd(ishexstr,dat,ack)
	local cmd = ((ishexstr == true) and common.hexstobins(dat) or dat)
	if cmd == nil or string.len(cmd) == 0 then print("writegpscmd err") return end
	local item = {cmd=cmd,ack=ack}

	table.insert(gps.wrquene,item)

	if not gps.curwritem then
		write()
	end
end

--Function name: writegps
--Function: Write command data to GPS chip (UBLOX GPS module only)
--Parameters:
--typ: command type
--Return Value: None

function writegps(typ)
	print("gps writegps",typ)
	-- Power saving mode

	if typ == GPS_POWER_SAVE_MODE then
		--cyclic  update period(10)  search period(60)  acquisition timeout(5)  on time(3)
		writegpscmd(true,"B562063B2C0001060000009002001027000060EA00000000000003000A002C0100004FC1030086020000FE00000064400100FFE2",true)
		writegpscmd(true,"B5620611020008012292",true)
		writegpscmd(true,"B56206090D0000000000FFFF0000000000000721AF",true)
	-- Continuous positioning mode

	elseif typ == GPS_CONTINUOUS_MODE then
		writegpscmd(true,"B5620611020008002191",true)
		writegpscmd(true,"B56206090D0000000000FFFF0000000000000721AF",true)
	-- Only support Beidou positioning

	elseif typ == GPS_SINGLE_BEIDOU_GNSS then
		--gps.gnsschange = true
		writegpscmd(true,"B562063E2C0000002005000810000000010101010300010001010308100001000101050003000100010106080E0000000101FE29",true)
	-- GPS positioning only

	elseif typ == GPS_SINGLE_GPS_GNSS then
		--gps.gnsschange = true
		writegpscmd(true,"B562063E2C0000002005000810000100010101010300010001010308100000000101050003000100010106080E0001000101FF3D",true)
	-- GPS and Beidou hybrid positioning

	elseif typ == GPS_MIX_GNSS then
		--gps.gnsschange = true
		writegpscmd(true,"B562063E2C0000002005000810000100010101010300010001010308100001000101050003000100010106080E0000000101FF4D",true)
	-- NEMA protocol version

	elseif typ == GPS_NMEA_VERSION then
		writegpscmd(true,"B5620617140000410002000000000000000000E0000000000000546E",true)
	-- Query PACC

	elseif typ == QRY_PACC then
		writegpscmd(true,"B562010100000207",true)
	else
		print("writegps err",typ)
	end
end

--Function name: opengps
--Function: Turn on the GPS
--Parameters:
--tag: Opens the tag to indicate which application opened the GPS
--Return Value: None

function opengps(tag)
	print("opengps",tag)
	gps.opentags[tag] = 1
	if gps.open then
		print("gps has open")
		return
	end
	pm.wake("gps")
	gps.open = true
	openuart()
	gps.filterbgn = nil
	if gps.io then
		if gps.edge then
			pio.pin.sethigh(gps.io)
		else
			pio.pin.setlow(gps.io)
		end
	end
	pmd.ldoset(7,pmd.LDO_VASW)
	gps.gnsschange = false
	--writegps(GPS_NMEA_VERSION)
	print("gps open")
	c.fixbgn = c.gps
	sys.dispatch(GPS_STATE_IND,GPS_OPEN_EVT)
end

--Function name: closegps
--Function: turn off GPS
--Parameters:
--tag: turn off the mark, used to indicate which application closed GPS
--Return Value: None

function closegps(tag)
	print("closegps",tag)
	gps.opentags[tag] = 0
	for k,v in pairs(gps.opentags) do
		if v > 0 then
			print("gps close using",k)
			return
		end
	end

	if not gps.open then
		print("gps has close")
		return
	end
	lastesttimerfunc()
	if gps.io then
		if gps.edge then
			pio.pin.setlow(gps.io)
		else
			pio.pin.sethigh(gps.io)
		end
	end
	pmd.ldoset(0,pmd.LDO_VASW)
	closeuart()
	pm.sleep("gps")	
	gps.open = false
	if gps.state == 1 then
		gps.state = 2
	end	
	gps.latt_m = 0
	gps.longt_m = 0
	--gps.lati = 0
	--gps.long = 0
	gps.spd = 0
	gps.cog = 0
	gps.haiba = 0
	gps.sep = ""
	gps.ggalng,gps.ggalat = "",""
	gps.satesn = ""
	gps.lastcog = 0
	gps.cogchange = false
	gps.find = ""
	gps.findall = false
	gps.satenum = 0
	gps.locationsatenum = 0
	gps.sn = 0
	gps.sates = ""
	gps.gsv = ""
	gps.gnsschange = false
	print("gps close")
	sys.dispatch(GPS_STATE_IND,GPS_CLOSE_EVT)
	stoppaccqry()
end

--Function name: getgpslocation
--Function: Get GPS latitude and longitude information
--Parameters:
--format: latitude and longitude format, the default format Degrees GPS_DEGREES, support GPS_DEGREES and GPS_DEGREES_MINUTES
--Return Value: Latitude and longitude information string, for example, the format is "E, 121.12345, N, 31.23456". If there is no latitude and longitude format "E ,, N,

function getgpslocation(format)
	local rstr = (gps.longtyp and gps.longtyp or "E") .. ","
	local lo,la
	if format == nil or format == GPS_DEGREES then
		lo,la = gps.long,gps.lati
	elseif format == GPS_DEGREES_MINUTES then
		lo,la = gps.olong,gps.olati
	end
	if lo and lo ~= 0 and lo ~= "0" and lo ~= "" then
		rstr = rstr .. lo
	end
	rstr = rstr .. "," .. (gps.latyp and gps.latyp or "N") .. ","
	if la and la ~= 0 and la ~= "0" and la ~= "" then
		rstr = rstr .. la
	end
	return rstr
end

--Function name: getgpssatenum
--Function: Get the number of visible GPS satellites
--Parameters: None
--Return value: GPS can see the number of satellites

function getgpssatenum()
	return gps.satenum or 0
end

--Function name: getgpslocationsatenum
--Function: Get the number of satellites used by GPS positioning
--Parameters: None
--Return Value: The number of satellites used by GPS positioning

function getgpslocationsatenum()
	return gps.locationsatenum or 0
end

--Function name: getgpsspd
--Function: Get speed
--Parameters: None
--Return Value: Speed

function getgpsspd()
	return gps.spd or 0
end

--Function name: getgpscog
--Function: Get the direction angle
--Parameters: None
--Return value: Direction angle

function getgpscog()
	return gps.cog or 0
end

--Function name: getgpssn
--Function: Obtain the S / N ratio of the strongest satellite
--Parameters: None
--Return value: The signal to noise ratio of the strongest satellite

function getgpssn()
	return gps.sn or 0
end

function getpara()
	local t = {hdop=0,gsasatecnt=0,gsasateavgsn=0,pacc=0}
	--if isfix() then
		t.hdop = tonumber(smatch(hdop or "","(%d+)%.(%d*)") or "65535");
		
		local gsasate,gsasatesn,id = getsatesn(),{}
		for id in string.gmatch(gsasate,"(%d*),") do
			if id ~= "" then
				t.gsasatecnt = t.gsasatecnt + 1
				gsasatesn[id] = 0
			end
		end
		
		local satecnt,k,v,sn = 0
		for k,v in pairs(gsasatesn) do
			for id,sn in string.gmatch(gps.gsv,"(%d+),%d*,%d*,(%d+),") do
				if k == id then
					satecnt = satecnt + 1
					gsasatesn[id] = tonumber(sn or "0")
				end
			end
		end
		local cnt = isfix() and getgpslocationsatenum() or 3
		if cnt > satecnt then cnt = satecnt end
		if cnt > 3 then cnt = 3 end
		if cnt > 0 then
			for sn=1,cnt do
				local maxv,maxk = -1
				for k,v in pairs(gsasatesn) do
					if v > maxv then
						maxk,maxv = k,v
					end
				end
				if maxk then
					t.gsasateavgsn = t.gsasateavgsn + maxv
					gsasatesn[maxk] = -1
				end
			end
			t.gsasateavgsn = t.gsasateavgsn / cnt
		end
		
		t.pacc = (pacc or 0)/100
	--end
	
	print("gps.getpara",t.hdop,t.gsasatecnt,cnt,t.gsasateavgsn,t.pacc)
	return t
end


--Function name: isfix
--Function: Check GPS is located successfully
--Parameters: None
--Return Value: true for successful positioning, false for failure

function isfix()
	return gps.state == 1
end

--Function name: isopen
--Function: Check GPS is turned on
--Parameters: None
--Return Value: true is open, false is closed

function isopen()
	return gps.open
end

--Function name: getaltitude
--Function: Get the height
--Parameters: None
--Return Value: Height

function getaltitude()
	return gps.haiba or 0
end

function getsep()
	return gps.sep or 0
end

function getggaloc()
	return gps.ggalng or "",gps.ggalat or ""
end

function getsatesn()
	return gps.satesn or ""
end

function getgsv()
	return gps.gsv or ""
end

function setgsv(prefix)
	gps.gsvprefix = prefix or ""
end

function setgsa(prefix)
	gps.gsaprefix = prefix or ""
end

function getsatesinfo()
	local tmp = gps.sates
	print("getsatesinfo",tmp)
	local ret = ""
	if string.len(tmp) > 0 then
		tmp = string.sub(tmp,1,-2)
	end
	local sate = ""
	for sate in string.gmatch(tmp, "(%d+)") do
		local id,strength = string.sub(sate,1,2),string.sub(sate,3,4)
		if id and strength and id <= "32" and strength > "00" then
			if ret == "" then
				ret = sate .. " "
			else
				local d1,d2,sn = string.find(ret,id .. "(%d+)")
				if d1 and d2 and sn then
					if strength > sn then
						ret = string.sub(ret,1,d1+1) .. strength .. string.sub(ret,d2+1,-1)
					end
				else
					ret = ret .. sate .. " "
				end
			end
		end
	end
	if string.len(ret) > 0 then
		return string.sub(ret,1,-2)
	else
		return ret
	end
end

--Function name: init
--Function: Configure GPS
--Parameters:
--ionum: GPS powered GPIO
--dir: This parameter is useless (in order to be compatible with the previous code, can not be removed), casually pass,
--edge: true means GPIO output is high level, false or nil means GPIO output is low level
--period: Serial port read NEMA data interval in milliseconds, it is recommended to read once in 1000 milliseconds
--id: Serial port ID, 1 indicates serial port 1, 2 indicates serial port 2
--baud: Serial baud rate, for example 9600
--databits: Data bits, such as 8
--parity: Check digit, such as uart.PAR_NONE
--stopbits: stop bit, for example, uart.STOP_1
--apgspwronupd: whether to allow the implementation of AGPS boot function
--Return Value: None

function init(ionum,dir,edge,period,id,baud,databits,parity,stopbits,apgspwronupd)
	gps.open = false
	gps.wrquene = {}
	gps.curwritem = nil
	gps.retrywrcnt = 0
	gps.retrywrmaxcnt = 3
	gps.latt_m = 0
	gps.longt_m = 0
	gps.lati = 0
	gps.long = 0
	gps.olati = 0
	gps.olong = 0
	gps.latyp = "N"
	gps.longtyp = "E"
	gps.spd = 0
	gps.cog = 0
	gps.haiba = 0
	gps.satesn = ""
	gps.sep = ""
	gps.ggalng,gps.ggalat = "",""
	gps.gsv,gps.gsvprefix = "",""
	gps.gsaprefix = ""
	gps.lastcog = 0
	gps.cogchange = false
	gps.state = 0
	gps.find = ""
	gps.findall = false
	gps.satenum = 0
	gps.locationsatenum = 0
	gps.sn = 0
	gps.sates = ""
	gps.gnsschange = false
	gps.filterbgn = nil
	gps.filtertime = 5
	gps.timezone = nil
	gps.spdtyp = GPS_KILOMETER_SPD	
	gps.opentags = {}
	gps.isagpspwronupd = (apgspwronupd == nil) and true or apgspwronupd

	c.gps = 0
	c.hasgps = 0
	c.gpsfind = 0
	c.GpsPrtMod = 180
	c.gpsprint = 0
	c.fixbgn = 0
	c.fixitv = 0

	--emptyque()
	gps.cgen = 0
	gps.QueL = 7
	gps.errL = 100
	gps.errD = 600

	gps.io = ionum
	gps.edge = edge

	gps.period = period
	gps.uartid = id
	gps.baud = baud
	gps.databits = databits
	gps.parity = parity
	gps.stopbits = stopbits

	if ionum then
		pio.pin.setdir(pio.OUTPUT,ionum)
	end
end

--Function name: setgpsfilter
--Function: Set GPS positioning successfully filter time
--Parameters:
--secs: The number of seconds to filter, for example 5, indicates that the positioning information of the first 5 seconds is discarded after GPS positioning is successful
--Return Value: None

function setgpsfilter(secs)
	if secs >= 0 then
		gps.filtertime = secs
	end
end

--Function name: settimezone
--Function: Set the software system's time zone. After calling this interface, GPS will set the system time corresponding to the time zone after obtaining the time
--Parameters:
--zone: Currently supports GPS_GREENWICH_TIME, GPS_BEIJING_TIME, GPS_VIETNAM_TIME
--Return Value: None

function settimezone(zone)
	gps.timezone = zone
end

--Function name: setspdtyp
--Function: Set the speed type
--Parameters:
--typ: Currently supports GPS_KNOT_SPD, GPS_KILOMETER_SPD
--Return Value: None

function setspdtyp(typ)
	gps.spdtyp = typ
end

function closeuart()
	print("gps closeuart")
	uart.close(gps.uartid)
	--rtos.sleep(400)
	sys.timer_stop(read)
end

function openuart()
	print("gps openuart")
	--uart.sleep(200)
	uart.setup(gps.uartid,gps.baud,gps.databits,gps.parity,gps.stopbits)
	sys.timer_start(read,gps.period)
end

function getutctime()
	return gps.utctime
end

function getfixitv()
	return isfix() and c.fixitv or 0
end

function isagpspwronupd()
	return (gps.isagpspwronupd == nil) and true or gps.isagpspwronupd
end

function lastesttimerfunc()
	if gps.lastestflg and gps.lastestprd and gps.lastestcb then
		gps.lastestcb()
		if not isfix() then
			sys.timer_stop(lastesttimerfunc)
		end
	end
end

function startlastesttimer()
	if isfix() and gps.lastestflg and gps.lastestprd and gps.lastestcb then
		sys.timer_loop_start(lastesttimerfunc,gps.lastestprd)
	end
end

function setlastest(flg,prd,cb)
	gps.lastestflg = flg
	gps.lastestprd = prd or 5000
	gps.lastestcb = cb
	startlastesttimer()
end

function setflag(pacflg)
	paccflg = pacflg
end



-- "GPS application": refers to an application that uses the GPS function
-- For example, suppose you have the following three requirements, a total of 3 "GPS applications" to open the GPS:
-- "GPS App 1": Open GPS every 1 minute
-- "GPS Application 2": Turn on the GPS when the device vibrates
-- "GPS Application 3": Turn on GPS when receiving a special SMS
-- Only when all "GPS apps" are off will GPS turn off really

--There are up to 4 parameters for each GPS application to turn GPS on or off, and GPS operating mode and GPS application flags together define a unique GPS application:
--1, GPS working mode (required)
--2, "GPS application" mark (required)
--3, GPS open the maximum duration [optional]
--4, callback function [optional]
--For example gps.open (gpsapp.TIMERORSUC, {cause = "TEST", val = 120, cb = testgpscb})
--gps.TIMERORSUC for GPS mode of operation, "TEST" for the "GPS application" mark, 120 seconds for GPS to open the maximum duration, testgpscb callback function


--GPS work mode, a total of the following 3 kinds
--1, DEFAULT
--???(1), open, GPS positioning success, if there is a callback function, callback function will be called
--???(2), use this mode of operation call gps.open open "GPS application", you must call gps.close to close
--2, TIMERORSUC
--???(1), open, if the GPS reaches the maximum length of time is reached, there is no positioning success, if there is a callback function, call the callback function, and then automatically turn off the "GPS application"
--???(2), open, if the GPS is turned on the maximum length of time, the positioning is successful, if there is a callback function, call the callback function, and then automatically turn off the "GPS application"
--???(3), open, before automatically closing the "GPS application", you can call gps.close initiative to turn off this "GPS application", the initiative to shut down, even if there is a callback function, it will not call the callback function
--3, TIMER
--???(1), open, when the GPS is turned on for the maximum length of time to arrive, regardless of whether the positioning is successful, if there is a callback function, call the callback function, and then automatically turn off the "GPS application"
--???(2), open, before automatically closing the "GPS application", you can call gps.close initiative to turn off this "GPS application", the initiative to shut down, even if there is a callback function, it will not call the callback function

DEFAULT,TIMERORSUC,TIMER = 0,1,2

-- "GPS application" table

local tlist = {}

--Function name: print
--Function: Print interface, all print in this file will be added gpsapp prefix
--Parameters: None
--Return Value: None

local function print(...)
	base.print("gpsapp",...)
end

--Function name: delitem
--Function: Deleting a "GPS application" from the "GPS Application" table is not really deleting, but setting an invalid flag
--Parameters:
--mode: GPS working mode
--para:
--para.cause: "GPS application" tag
--para.val: GPS is turned on the maximum duration
--para.cb: callback function
--Return Value: None

local function delitem(mode,para)
	local i
	for i=1,#tlist do
		-- The flag is valid and the GPS mode of operation is the same and the "GPS application" tag is the same
		if tlist[i].flag and tlist[i].mode == mode and tlist[i].para.cause == para.cause then
			-- set the invalid flag

			tlist[i].flag,tlist[i].delay = false
			break
		end
	end
end

--Function name: additem
--Function: Add a "GPS application" to "GPS application" table
--Parameters:
--mode: GPS working mode
--para:
--para.cause: "GPS application" tag
--para.val: GPS is turned on the maximum duration
--para.cb: callback function
--Return Value: None

local function additem(mode,para)
	-- Remove the same "GPS application"

	delitem(mode,para)
	local item,i,fnd = {flag = true, mode = mode, para = para}
	-- If TIMERORSUC or TIMER mode, initialize GPS work remaining time

	if mode == TIMERORSUC or mode == TIMER then item.para.remain = para.val end
	for i=1,#tlist do
		-- If there is an invalid "GPS application" item, use this position directly

		if not tlist[i].flag then
			tlist[i] = item
			fnd = true
			break
		end
	end
	-- add one

	if not fnd then table.insert(tlist,item) end
end

local function isexisttimeritem()
	local i
	for i=1,#tlist do
		if tlist[i].flag and (tlist[i].mode == TIMERORSUC or tlist[i].mode == TIMER or tlist[i].para.delay) then return true end
	end
end

local function timerfunc()
	local i
	for i=1,#tlist do
		print("timerfunc@"..i,tlist[i].flag,tlist[i].mode,tlist[i].para.cause,tlist[i].para.val,tlist[i].para.remain,tlist[i].para.delay)
		if tlist[i].flag then
			local rmn,dly,md,cb = tlist[i].para.remain,tlist[i].para.delay,tlist[i].mode,tlist[i].para.cb
			if rmn and rmn > 0 then
				tlist[i].para.remain = rmn - 1
			end
			if dly and dly > 0 then
				tlist[i].para.delay = dly - 1
			end
			
			rmn = tlist[i].para.remain
			if isfix() and md == TIMER and rmn == 0 and not tlist[i].para.delay then
				tlist[i].para.delay = 1
			end
			
			dly = tlist[i].para.delay
			if isfix() then
				if dly and dly == 0 then
					if cb then cb(tlist[i].para.cause) end
					if md == DEFAULT then
						tlist[i].para.delay = nil
					else
						close(md,tlist[i].para)
					end
				end
			else
				if rmn and rmn == 0 then
					if cb then cb(tlist[i].para.cause) end
					close(md,tlist[i].para)
				end
			end			
		end
	end
	if isexisttimeritem() then sys.timer_start(timerfunc,1000) end
end

--Function name: gpsstatind
--Function: Process GPS successful positioning message
--Parameters:
--id: GPS message id
--evt: GPS message type
--Return Value: None

local function gpsstatind(id,evt)
	-- Successful positioning of the message

	if evt == GPS_LOCATION_SUC_EVT then
		local i
		for i=1,#tlist do
			print("gpsstatind@"..i,tlist[i].flag,tlist[i].mode,tlist[i].para.cause,tlist[i].para.val,tlist[i].para.remain,tlist[i].para.delay,tlist[i].para.cb)
			if tlist[i].flag then
				if tlist[i].mode ~= TIMER then
					tlist[i].para.delay = 1
					if tlist[i].mode == DEFAULT then
						if isexisttimeritem() then sys.timer_start(timerfunc,1000) end
					end
				end				
			end			
		end
	end
	return true
end

--Function name: forceclose
--Function: Forcibly turn off all "GPS application"
--Parameters: None
--Return Value: None

function forceclose()
	local i
	for i=1,#tlist do
		if tlist[i].flag and tlist[i].para.cb then tlist[i].para.cb(tlist[i].para.cause) end
		close(tlist[i].mode,tlist[i].para)
	end
end

--Function name: close
--Function: turn off a "GPS application"
--Parameters:
--mode: GPS working mode
--para:
--para.cause: "GPS application" tag
--para.val: GPS is turned on the maximum duration
--para.cb: callback function
--Return Value: None

function close(mode,para)
	assert((para and type(para) == "table" and para.cause and type(para.cause) == "string"),"gpsapp.close para invalid")
	print("ctl close",mode,para.cause,para.val,para.cb)
	--Remove this "GPS application"

	delitem(mode,para)
	local valid,i
	for i=1,#tlist do
		if tlist[i].flag then
			valid = true
		end		
	end
	--If no GPS application is active, turn off GPS

	if not valid then closegps("gpsapp") end
end

--Function name: open
--Function: Open a "GPS application"
--Parameters:
--mode: GPS working mode
--para:
--para.cause: "GPS application" tag
--para.val: GPS is turned on the maximum duration
--para.cb: callback function
--Return Value: None

function open(mode,para)
	assert((para and type(para) == "table" and para.cause and type(para.cause) == "string"),"gpsapp.open para invalid")
	print("ctl open",mode,para.cause,para.val,para.cb)
	-- If GPS positioning is successful

	if isfix() then
		if mode ~= TIMER then
			-- Execute the callback function

			if para.cb then para.cb(para.cause) end
			if mode == TIMERORSUC then return end			
		end
	end
	additem(mode,para)
	-- really go to turn on the GPS

	opengps("gpsapp")
	-- Start the 1 second timer

	if isexisttimeritem() and not sys.timer_is_active(timerfunc) then
		sys.timer_start(timerfunc,1000)
	end
end

--Function name: isactive
--Function: to determine whether a "GPS application" is active or not
--Parameters:
--mode: GPS working mode
--para:
--para.cause: "GPS application" tag
--para.val: GPS is turned on the maximum duration
--para.cb: callback function
--Return Value: Activate returns true, otherwise returns nil

function isactive(mode,para)
	assert((para and type(para) == "table" and para.cause and type(para.cause) == "string"),"gpsapp.isactive para invalid")
	local i
	for i=1,#tlist do
		if tlist[i].flag and tlist[i].mode == mode and tlist[i].para.cause == para.cause then
			return true
		end
	end
end

sys.regapp(gpsstatind,GPS_STATE_IND)
