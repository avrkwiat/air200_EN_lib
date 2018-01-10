
--Module Name: Charge Control
--Module function: charging parameter configuration, battery voltage detection, charging status detection, external electrical connection detection
--Last modified: 2017.02.16
--Note: The charging scheme in this module adopts the RDA internal charging scheme and does not apply to the Air200 module
--When using the Air200 module to develop the product, the user uses an external charging scheme. The voltage of the vbat battery can only be read by using the misc.getvbatvolt () interface, and the remaining functions can not be used


require"sys"
module(...,package.seeall)

local inf = {}
local tcap =
{
	[1] = {cap=100,volt=4200},
	[2] = {cap=90,volt=4060},
	[3] = {cap=80,volt=3980},
	[4] = {cap=70,volt=3920},
	[5] = {cap=60,volt=3870},
	[6] = {cap=50,volt=3820},
	[7] = {cap=40,volt=3790},
	[8] = {cap=30,volt=3770},
	[9] = {cap=20,volt=3740},
	[10] = {cap=10,volt=3680},
	[11] = {cap=5,volt=3500},
	[12] = {cap=0,volt=3400},
}


local function getcap(volt)
	if not volt then return 50 end
	if volt >= tcap[1].volt then return 100 end
	if volt <= tcap[#tcap].volt then return 0 end
	local idx,val,highidx,lowidx,highval,lowval = 0
	for idx=1,#tcap do
		if volt == tcap[idx].volt then
			return tcap[idx].cap
		elseif volt < tcap[idx].volt then
			highidx = idx
		else
			lowidx = idx
		end
		if highidx and lowidx then
			return (volt-tcap[lowidx].volt)*(tcap[highidx].cap-tcap[lowidx].cap)/(tcap[highidx].volt-tcap[lowidx].volt) + tcap[lowidx].cap
		end
	end
end

local function proc(msg)
	if msg then	
		if msg.level == 255 then return end
		inf.chg = msg.charger
		if inf.state ~= msg.state then
			inf.state = msg.state
			sys.dispatch("DEV_CHG_IND","CHG_STATUS",getstate())
		end
		
		inf.lev = getcap(msg.voltage)
		local flag = (inf.lev <= inf.lowlev and not getstate())
		if inf.low ~= flag then
			inf.low = flag
			sys.dispatch("DEV_CHG_IND","BAT_LOW",flag)
		end
		
		inf.vol = msg.voltage
		--[[if inf.lev == 0 and not inf.chg then
			if not inf.poweroffing then
				inf.poweroffing = true
				sys.timer_start(rtos.poweroff,30000,"chg")
			end
		elseif inf.poweroffing then
			sys.timer_stop(rtos.poweroff,"chg")
			inf.poweroffing = false
		end]]
		print("chg proc",inf.chg,inf.lev,inf.vol,inf.state)
	end
end

local function init()
	inf.vol = 0
	inf.lev = 0
	inf.chg = false
	inf.state = false
	inf.poweroffing = false
	inf.lowlev = 10
	inf.low = false
	
	local para = {}
	para.batdetectEnable = 0
	para.currentFirst = 200
	para.currentSecond = 100
	para.currentThird = 50
	para.intervaltimeFirst = 180
	para.intervaltimeSecond = 60
	para.intervaltimeThird = 30
	para.battlevelFirst = 4100
	para.battlevelSecond = 4150
	para.pluschgctlEnable = 1
	para.pluschgonTime = 5
	para.pluschgoffTime = 1
	pmd.init(para)
end

function getcharger()
	return inf.chg
end

function getvolt()
	return inf.vol
end

function getlev()
	return inf.lev
end

function getstate()
	return (inf.state == 1)
end

function islow()
	return inf.low
end

sys.regmsg(rtos.MSG_PMD,proc)
init()
