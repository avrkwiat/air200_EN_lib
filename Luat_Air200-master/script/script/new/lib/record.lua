
--Module Name: Recording Control
--Module Function: Record and read the recorded content
--Module last modified: 2017.04.05

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local io = require"io"
local os = require"os"
local rtos = require"rtos"
local audio = require"audio"
local sys = require"sys"
local ril = require"ril"
module(...)

-- Load common global functions to local

local smatch = string.match
local print = base.print
local dispatch = sys.dispatch
local tonumber = base.tonumber
local assert = base.assert

--RCD_ID Recording file number
--RCD_FILE Recording file name
local RCD_ID,RCD_FILE = 1,"/RecDir/rec001"
--rcding: is recording
--rcdcb: recording callback function
--reading: Whether recording is being read or not
--duration: recording duration (ms)
local rcding,rcdcb,reading,duration

--Function name: print
--Function: Print interface, all print in this file will be added record prefix
--Parameters: None
--Return Value: None

local function print(...)
	base.print("record",...)
end

--Function name: getdata
--Function: Get the specified length of data from the specified location of the recording file
--Parameters:
--offset: number type, specified location, ranging from 0 to file length -1
--???????? len: number type, specify the length, if the length is set longer than the remaining length of the file, you can only read the remaining length of the content
--Return Value: The specified recording data, if the reading fails, returns an empty string ""

function getdata(offset,len)
	local f,rt = io.open(RCD_FILE,"rb")
    -- If the file fails to open, the returned content is empty. ""

	if not f then print("getdata err£ºopen") return "" end
	if not f:seek("set",offset) then print("getdata err£ºseek") return "" end
    -- Read the data of the specified length

	rt = f:read(len)
	f:close()
	print("getdata",string.len(rt or ""))
	return rt or ""
end

--Function name: getsize
--Function: Get the total length of the current recording file
--Parameters: None
--Return Value: The total length of the current recording file, in bytes

local function getsize()
	local f = io.open(RCD_FILE,"rb")
	if not f then print("getsize err£ºopen") return 0 end
	local size = f:seek("end")
	if not size or size == 0 then print("getsize err£ºseek") return 0 end
	f:close()
    return size
end


--Function name: rcdcnf
--Function: AUDIO_RECORD_CNF message processing function
--Parameters: suc, suc true to start recording or recording failed
--Return Value: None

local function rcdcnf(suc)
	print("rcdcnf",suc)
	if suc then
		rcding = true
	else
		if rcdcb then rcdcb() end
	end
end


--Function name: rcdind
--Function: Recording end processing function
--Parameters: suc: true recording success; false recording failed
--Return value: true

local function rcdind(suc,dur)
	print("rcdind",suc,dur,rcding)	
    -- Recording failed or should not result in recording end message

	if not suc or not rcding then	
        -- Delete the recording file

		delete()
	end
	duration = dur
	if rcdcb then rcdcb(suc and rcding,getsize()) end
	rcding=false
end


--Function name: start
--Function: Start recording
--Parameters: seconds: number type, recording duration (in seconds)
--???????? cb: function type, recording callback function, recording after the success or failure, will call the cb function
--Call the way cb (result, size), result is true success, false or nil for the failure, size said recording file size (in bytes)
--Return Value: None

function start(seconds,cb)
	print("start",seconds,cb,rcding,reading)
	if seconds<=0 or seconds>50 then
		print("start err£ºseconds")
		if cb then cb() end
		return
	end
    -- If you are recording or reading a recording, the direct return fails

	if rcding or reading then
		print("start err£ºing")
		if cb then cb() end
		return
	end
	
	-- Set the recording mark

	rcding = true
	rcdcb = cb
    -- Delete the previous recording file

	delete()
    --start recording

	audio.beginrecord(RCD_ID,seconds*1000)
end

--Function name: delete
--Function: delete the recording file
--Parameters: None
--Return Value: None

function delete()
	os.remove(RCD_FILE)
end

--Function name: getfilepath
--Function: Get the path of the recording file
--Parameters: None
--Return Value: The path of the recording file

function getfilepath()
	return RCD_ID.."&"..(duration or "0")
end

local procer = {
	AUDIO_RECORD_CNF = rcdcnf,
	AUDIO_RECORD_IND = rcdind,
}
-- Register the message processing function that this function module pays attention to

sys.regapp(procer)
