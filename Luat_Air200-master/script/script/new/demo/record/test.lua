
--Module Name: Recording Test
--Module functions: test recording function, read the recording data and play the recording
--Module last modified: 2017.04.05


module(...,package.seeall)
require"record"

-- The length of the recording file to be read each time
local RCD_READ_UNIT = 1024
--rcdoffset: the starting position of the content of the currently read recording file
--rcdsize: The total length of the recording file
--rcdcnt: How many times to read the current recording file, can all be read
local rcdoffset,rcdsize,rcdcnt



--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

--Function name: playcb
--Function: Playback callback function after recording
--Parameters: None
--Return Value: None

local function playcb(r)
	print("playcb",r)
	-- Delete the recording file
	record.delete()
end

--Function name: readrcd
--Function: read the contents of the recording file
---Parameters: None
--Return Value: None

local function readrcd()	
	local s = record.getdata(rcdoffset,RCD_READ_UNIT)
	print("readrcd",rcdoffset,rcdcnt,string.len(s))
	rcdcnt = rcdcnt-1
	-- The contents of the recording file have all been read out
	if rcdcnt<=0 then
		sys.timer_stop(readrcd)
		-- play recording content
		audio.play(0,"RECORD",record.getfilepath(),audiocore.VOL7,playcb)
	-- Not yet read all
	else
		rcdoffset = rcdoffset+RCD_READ_UNIT
	end
end

--Function name: rcdcb
--Function: Callback function after recording
--Parameters:
--result: recording result, true means success, false or nil means failure
--size: number type, the size of the recording file, the unit is bytes, the result is true only meaningful
--Return Value: None

local function rcdcb(result,size)
	print("rcdcb",result,size)
	if result then
		rcdoffset,rcdsize,rcdcnt = 0,size,(size-1)/RCD_READ_UNIT+1
		sys.timer_loop_start(readrcd,1000)
	end	
end

-- After 5 seconds, start recording
sys.timer_start(record.start,5000,5,rcdcb)
