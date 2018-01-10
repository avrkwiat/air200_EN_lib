
--Module Name: "GPS Application" test
--Module Function: Test the gpsapp.lua interface
--Last modified: 2017.02.16

require"gps"
require"agps"
module(...,package.seeall)

--Function name: print
--Function: Print interface, all print in this file will be added gpsapp prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("testgps",...)
end

local function test1cb(cause)
	--gps.isfix (): Location is successful
	--gps.getgpslocation (): latitude and longitude information
	print("test1cb",cause,gps.isfix(),gps.getgpslocation())
end

local function test2cb(cause)
	--gps.isfix (): Location is successful
	--gps.getgpslocation (): latitude and longitude information
	print("test2cb",cause,gps.isfix(),gps.getgpslocation())
end

local function test3cb(cause)
	--gps.isfix (): Location is successful
	--gps.getgpslocation (): latitude and longitude information
	print("test3cb",cause,gps.isfix(),gps.getgpslocation())
end

-- UART2 external UBLOX GPS module
gps.init(nil,nil,true,1000,2,9600,8,uart.PAR_NONE,uart.STOP_1)

--sys.timer_start(gps.writegpscmd,1000,true,"B56206010600F00000000000FD15",true) --Turn off GGA
--sys.timer_start(gps.writegpscmd,1000,true,"B56206010600F00100000000FE1A",true) --Turn off GLL
--sys.timer_start(gps.writegpscmd,1000,true,"B56206010600F00200000000FF1F",true) --Turn off GSA
--sys.timer_start(gps.writegpscmd,1000,true,"B56206010600F003000000000024",true) --Turn off GSV
--sys.timer_start(gps.writegpscmd,1000,true,"B56206010600F00500000000022E",true) --Turn off VTG

--sys.timer_start(gps.writegpscmd,1000,true,"B562060806006400010001007A12",true) --100ms

-- Test code switch, the value of 1,2
local testidx = 1

-- The first test code
if testidx==1 then
	-- After executing the following three lines of code, the GPS will always be on and will never be off
	-- because gps.open (gps.DEFAULT, {cause = "TEST1", cb = test1cb}), this is on, there is no call to gps.close off
	gps.open(gps.DEFAULT,{cause="TEST1",cb=test1cb})
	
	-- 10 seconds, if GPS positioning success, will immediately call test2cb, and then automatically turn off the "GPS application"
	-- 10 seconds to go, no location is successful, will immediately call test2cb, and then automatically turn off the "GPS application"
	gps.open(gps.TIMERORSUC,{cause="TEST2",val=10,cb=test2cb})
	
	-- 300 seconds to, will immediately call test3cb, and then automatically turn off the "GPS application"
	gps.open(gps.TIMER,{cause="TEST3",val=300,cb=test3cb})
-- the second test code
elseif testidx==2 then
	gps.open(gps.DEFAULT,{cause="TEST1",cb=test1cb})
	sys.timer_start(gps.close,30000,gps.DEFAULT,{cause="TEST1"})
	gps.open(gps.TIMERORSUC,{cause="TEST2",val=10,cb=test2cb})
	gps.open(gps.TIMER,{cause="TEST3",val=60,cb=test3cb})	
end
