
--Module Name: Audio Control
--Module functions: dtmf codec, tts (requires underlying software support), audio file playback and stop, recording, mic and speaker control
--Module last modified: 2017.02.20

-- Define module, import dependent libraries
local base = _G
local string = require"string"
local io = require"io"
local rtos = require"rtos"
local audio = require"audiocore"
local sys = require"sys"
local ril = require"ril"
module(...)

-- Load common global functions to local
local smatch = string.match
local print = base.print
local dispatch = sys.dispatch
local req = ril.request
local tonumber = base.tonumber
local assert = base.assert

--speakervol: speaker volume level, ranging from audio.VOL0 to audio.VOL7, audio.VOL0 is muted
-- audiochannel: audio channel, with the hardware design, the user program needs to be based on the hardware configuration
--microphonevol: mic Volume level in the range of audio.MIC_VOL0 to audio.MIC_VOL15, audio.MIC_VOL0 mute
local speakervol,audiochannel,microphonevol = audio.VOL4,audio.HANDSET,audio.MIC_VOL15
local ttscause
-- audio file path
local playname

--Function name: print
--Function: Print interface, all print in this file will be added with audio prefix
--Parameters: None
--Return Value: None

local function print(...)
	base.print("audio",...)
end


--Function name: playtts
--Function: Play tts
--Parameters:
--text: string
--Path: "net" said the network play, the remaining value that local play
--Return value: true

local function playtts(text,path)
	local action = path == "net" and 4 or 2

	req("AT+QTTS=1")
	req(string.format("AT+QTTS=%d,\"%s\"",action,text))
	return true
end

--Function name: stoptts
--Function: Stop playing tts
--Parameters: None
--Return Value: None

local function stoptts()
	req("AT+QTTS=3")
end

--Function name: closetts
--Function: Turn off tts function
--Parameters:
--cause: Turn off the cause
--Return Value: None

local function closetts(cause)
	ttscause = cause
	req("AT+QTTS=0")
end

--Function name: beginrecord
--Function: Start recording
--Parameters:
--id: Recording id, will store the recording file according to this id, the value range is 0-4
--duration: recording duration in milliseconds
--Return value: true

function beginrecord(id,duration)
	req(string.format("AT+AUDREC=0,0,1," .. id .. "," .. duration))
	return true
end

--Function name: endrecord
--Function: End recording
--Parameters:
--id: Recording id, will store the recording file according to this id, the value range is 0-4
--duration: recording duration in milliseconds
--Return value: true

local function endrecord(id,duration)
	req(string.format("AT+AUDREC=0,0,0," .. id .. "," .. duration))
	return true
end

--Function name: delrecord
--Function: delete the recording file
--Parameters:
--id: Recording id, will store the recording file according to this id, the value range is 0-4
--duration: recording duration in milliseconds
--Return value: true

local function delrecord(id,duration)
	req(string.format("AT+AUDREC=0,0,4," .. id .. "," .. duration))
	return true
end

--Function name: playrecord
--Function: play recording files
--Parameters:
--dl: module downlink (headphone or handle or speaker) can hear the sound of recording playback, true can be heard, false or nil can not hear
--Loop: Whether to loop, true for loop, false or nil for non-looping
--id: Recording id, will store the recording file according to this id, the value range is 0-4
--duration: recording duration in milliseconds
--Return value: true

local function playrecord(dl,loop,id,duration)
	req(string.format("AT+AUDREC=" .. (dl and 1 or 0) .. "," .. (loop and 1 or 0) .. ",2," .. id .. "," .. duration))
	return true
end

--Function name: stoprecord
--Function: Stop playing the recording file
--Parameters:
--dl: module downlink (headphone or handle or speaker) can hear the sound of recording playback, true can be heard, false or nil can not hear
--Loop: Whether to loop, true for loop, false or nil for non-looping
--id: Recording id, will store the recording file according to this id, the value range is 0-4
--duration: recording duration in milliseconds
--Return value: true

local function stoprecord(dl,loop,id,duration)
	req(string.format("AT+AUDREC=" .. (dl and 1 or 0) .. "," .. (loop and 1 or 0) .. ",3," .. id .. "," .. duration))
	return true
end

--Function name: _play
--Function: play audio files
--Parameters:
--name: audio file path
--Loop: Whether to loop, true for loop, false or nil for non-looping
--Return Value: Call playback interface success, true is successful, false is failed

local function _play(name,loop)
	if loop then playname = name end
	return audio.play(name)
end

--Function name: _stop
--Function: Stop playing audio files
--Parameters: None
--Return Value: The call to stop playing the interface is successful, true is successful, false is failed

local function _stop()
	playname = nil
	return audio.stop()
end

--Function name: audiourc
--Function: The function of "registered core layer through the virtual serial port initiative to report the notification" of the processing
--Parameters:
--data: The complete string information for the notification
--prefix: The prefix of the notification
--Return Value: None

local function audiourc(data,prefix)	
	-- Recording or recording playback
	if prefix == "+AUDREC" then
		local action,duration = string.match(data,"(%d),(%d+)")
		if action and duration then
			duration = base.tonumber(duration)
			--start recording
			if action == "1" then
				dispatch("AUDIO_RECORD_IND",(duration > 0 and true or false),duration)
			-- play recordings
			elseif action == "2" then
				if duration > 0 then
					playend()
				else
					playerr()
				end
			-- delete the recording
			--[[elseif action == "4" then
				dispatch("AUDIO_RECORD_IND",true,duration)]]
			end
		end
	--tts function
	elseif prefix == "+QTTS" then
		local flag = string.match(data,": *(%d)",string.len(prefix)+1)
		-- stop playing tts
		if flag == "0" or flag == "1" then
			playend()
		end	
	end
end

--Function name: audiorsp
--Function: This function module "through the virtual serial port to the underlying core software AT command" response processing
--Parameters:
--cmd: AT command corresponding to this reply
--success: AT command execution result, true or false
--response: string of the execution result in the AT command's response
--intermediate: intermediate information in the response of the AT command
--Return Value: None

local function audiorsp(cmd,success,response,intermediate)
	local prefix = smatch(cmd,"AT(%+%u+%?*)")

	-- Record or play recording confirmation reply
	if prefix == "+AUDREC" then
		local action = smatch(cmd,"AUDREC=%d,%d,(%d)")		
		if action=="1" then
			dispatch("AUDIO_RECORD_CNF",success)
		elseif action=="3" then
			recordstopind()
		end
	-- Play tts or turn off tts response
	elseif prefix == "+QTTS" then
		local action = smatch(cmd,"QTTS=(%d)")
		if not success then
			if action == "1" or action == "2" then
				playerr()
			end
		else
			if action == "0" then
				dispatch("TTS_CLOSE_IND",ttscause)
			end
		end
		if action=="3" then
			ttstopind()
		end
	end
end

-- Register the handler for the notification below
ril.regurc("+AUDREC",audiourc)
ril.regurc("+QTTS",audiourc)
-- Register the response handler for the following AT commands
ril.regrsp("+AUDREC",audiorsp,0)
ril.regrsp("+QTTS",audiorsp,0)

--Function name: setspeakervol
--Function: Set the output volume of the audio channel
--Parameters:
--vol: volume level, ranging from audio.VOL0 to audio.VOL7, audio.VOL0 is muted
--Return Value: None

function setspeakervol(vol)
	audio.setvol(vol)
	speakervol = vol
end

--Function name: getspeakervol
--Function: Read the output volume of the audio channel
--Parameters: None
--Return value: volume level

function getspeakervol()
	return speakervol
end

--Function name: setaudiochannel
--Function: Set the audio channel
--Parameters:
--channel: audio channel, with the hardware design, the user program needs to be based on the hardware configuration, Air200 module is fixed with audiocore.HANDSET
--Return Value: None

local function setaudiochannel(channel)
	audio.setchannel(channel)
	audiochannel = channel
end

--Function name: getaudiochannel
--Function: Read the audio channel
--Parameters: None
--Return Value: Audio channel

local function getaudiochannel()
	return audiochannel
end

--Function name: setloopback
--Function: Set loopback test
--Parameters:
--flag: whether to open the loopback test, true is open, false is closed
--typ: test loop audio channel, with the hardware design, the user program needs to be based on the hardware configuration
--setvol: Whether to set the output volume, true is set, false is not set
--vol: the volume of the output
--Return Value: true Setting successful, false setting failed

function setloopback(flag,typ,setvol,vol)
	return audio.setloopback(flag,typ,setvol,vol)
end

--Function name: setmicrophonegain
--Function: Set the MIC volume
--Parameters:
--vol: mic Volume level in the range of audio.MIC_VOL0 to audio.MIC_VOL15, audio.MIC_VOL0 is mute
--Return Value: None

function setmicrophonegain(vol)
	audio.setmicvol(vol)
	microphonevol = vol
end

--Function name: getmicrophonegain
--Function: Read MIC volume level
--Parameters: None
--Return value: volume level

function getmicrophonegain()
	return microphonevol
end

--Function name: audiomsg
--Function: handle the underlying rtos.MSG_AUDIO external message reported
--Parameters:
--msg: play_end_ind, whether the normal playback is over
--play_error_ind, whether to play the error
--Return Value: None

local function audiomsg(msg)
	if msg.play_end_ind == true then
		if playname then audio.play(playname) return end
		playend()
	elseif msg.play_error_ind == true then
		if playname then playname = nil end
		playerr()
	end
end

-- register the handler for rtos.MSG_AUDIO external messages reported at the bottom
sys.regmsg(rtos.MSG_AUDIO,audiomsg)
-- Air200 module only supports RECEIVER channel, Air200S only supports LOUSPEAKER channel
setaudiochannel(base.HARDWARE=="Air200S" and audio.LOUDSPEAKER or audio.HANDSET)
-- The default volume level is set to level 4, level 4 is intermediate, level 0, level 7
setspeakervol(audio.VOL4)
-- The default MIC volume level is set to level 1, the lowest level is 0, and the highest level is 15
setmicrophonegain(audio.MIC_VOL1)


--spriority: The audio priority of the current play
--styp: audio type currently playing
--spath: The path of the audio file currently playing
--svol: current playing volume
--scb: Callback function for the current play or error
--sdup: Whether the currently playing audio needs to be played repeatedly
--sduprd: If sdup is true, this value indicates the repeat interval (in milliseconds), the default interval
--spending: Whether or not the audio to be played needs to be played after the audio has ended asynchronously
local spriority,styp,spath,svol,scb,sdup,sduprd

--Function name: playbegin
--Function: Close the last play, then play this request
--Parameters:
--priority: audio priority, the smaller the value, the higher the priority
--typ: audio type, currently only supports "FILE", "TTS", "TTSCC", "RECORD"
--path: audio file path
--vol: Play volume, the range audiocore.VOL0 to audiocore.VOL7. This parameter is optional
--cb: Callback function when audio playback is over or error occurs. The callback contains a parameter: 0 means the playback ended successfully; 1 means playback error; 2 means playback priority is not enough and no playback occurs. This parameter is optional
--dup: Whether to loop, true loop, false or nil not loop. This parameter is optional
--duprd: playback interval (in milliseconds), dup is true, this value makes sense. This parameter is optional
--Return Value: true if the call succeeded, otherwise, nil

local function playbegin(priority,typ,path,vol,cb,dup,duprd)
	print("playbegin")
	-- Reassign the current playback parameters
	spriority,styp,spath,svol,scb,sdup,sduprd,spending = priority,typ,path,vol,cb,dup,duprd

	-- Set the volume if there is a volume parameter
	if vol then
		setspeakervol(vol)
    end
	
	-- Call playback interface success
	if (typ=="TTS" and playtts(path))
		or (typ=="TTSCC" and playtts(path,"net"))
		or (typ=="RECORD" and playrecord(true,false,tonumber(smatch(path,"(%d+)&")),tonumber(smatch(path,"&(%d+)"))))
		or (typ=="FILE" and _play(path,dup and (not duprd or duprd==0))) then
		return true
	-- Failed to call play interface
	else
		spriority,styp,spath,svol,scb,sdup,sduprd,spending = nil
	end
end

--Function name: play
--Function: Play audio
--Parameters:
--priority: number type, mandatory parameter, audio priority. The larger the value is, the higher the priority is
--typ: string type, mandatory parameter, and audio type. Currently, only FILE, TTS, TTSCC, RECORD are supported.
--path: Required parameter, audio file path, related to typ:
--When typ is "FILE": string type, indicating the audio file path
--When typ is "TTS": string type indicating the UCS2 hexadecimal string to play data
--When typ is "TTSCC": string type, a UCS2 hexadecimal string to be played to the correspondent data
--When typ is "RECORD": string type, recording ID & recording duration (milliseconds)
--vol: number type, optional parameters, playback volume, the range audiocore.VOL0 to audiocore.VOL7
--cb: function type, optional parameter, the end of the audio playback or error callback function, the callback contains a parameter: 0 means the playback ended successfully; 1 means playback error; 2 means playback priority is not enough, no playback
--dup: bool type, optional parameters, whether looping, true loop, false or nil not loop
--duprd: number type, optional parameters, playback interval (in milliseconds), dup is true, this value makes sense
--Return Value: true if the call succeeded, otherwise, nil

function play(priority,typ,path,vol,cb,dup,duprd)
	assert(priority and typ,"play para err")
	print("play",priority,typ,path,vol,cb,dup,duprd,styp)
	-- Audio is playing
	if styp then
		-- The audio to be played has a higher priority than the audio playing in progress
		if priority > spriority then
			-- If there is a callback function for the audio being played, a callback is performed, passing in parameter 2
			if scb then scb(2) end
			-- Stop the playing audio
			if not stop() then
				spriority,styp,spath,svol,scb,sdup,sduprd,spending = priority,typ,path,vol,cb,dup,duprd,true
				return
			end
		-- The audio to be played has a lower priority than the playing audio
		elseif priority < spriority then
			-- Return nil directly, not allowed to play
			return
		-- The priority of the audio to be played is equal to the priority of the audio being played, there are two cases (1, playing in loop; 2, the user repeatedly calls the interface to play the same audio type)
		else
			-- If it is the second case, return directly; the first case, go straight down
			if not sdup then
				return
			end
		end
	end

	playbegin(priority,typ,path,vol,cb,dup,duprd)
end

--Function name: stop
--Function: Stop audio playback
--Parameters: None
--Returns: true if synchronization can be successfully stopped, otherwise nil

function stop()
	if styp then
		local typ,path = styp,spath		
		spriority,styp,spath,svol,scb,sdup,sduprd,spending = nil
		-- Stop the loop play timer
		sys.timer_stop_all(play)
		-- Stop audio playback
		_stop()
		if typ=="TTS" or typ=="TTSCC" then stoptts() return end
		if typ=="RECORD" then stoprecord(true,false,tonumber(smatch(path,"(%d+)&")),tonumber(smatch(path,"&(%d+)"))) return end
	end
	return true
end

--Function name: playend
--Function: Audio playback finishes processing function successfully
--Parameters: None
--Return Value: None

function playend()
	print("playend",sdup,sduprd)
	if (styp=="TTS" or styp=="TTSCC") and not sdup then stoptts() end
	if styp=="RECORD" and not sdup then stoprecord(true,false,tonumber(smatch(spath,"(%d+)&")),tonumber(smatch(spath,"&(%d+)"))) end
	-- need to repeat
	if sdup then
		-- There is a repeat interval
		if sduprd then
			sys.timer_start(play,sduprd,spriority,styp,spath,svol,scb,sdup,sduprd)
		-- There is no repeat interval
		elseif styp=="TTS" or styp=="TTSCC" or styp=="RECORD" then
			play(spriority,styp,spath,svol,scb,sdup,sduprd)
		end
	-- Do not need to repeat
	else
		-- If there is a callback function for the audio being played, a callback is performed, passing in parameter 0
		if scb then scb(0) end
		spriority,styp,spath,svol,scb,sdup,sduprd,spending = nil
	end
end

--Function name: playerr
--Function: Audio play failure handler
--Parameters: None
--Return Value: None

function playerr()
	print("playerr")
	if styp=="TTS" or styp=="TTSCC" then stoptts() end
	if styp=="RECORD" then stoprecord(true,false,tonumber(smatch(spath,"(%d+)&")),tonumber(smatch(spath,"&(%d+)"))) end
	-- If there is a callback function for the audio being played, a callback is performed, passing in parameter 1
	if scb then scb(1) end
	spriority,styp,spath,svol,scb,sdup,sduprd,spending = nil
end

local stopreqcb

--Function name: audstopreq
--Function: The script that sends the message AUDIO_STOP_REQ between lib scripts
--Parameters:
--cb: audio stop callback function
--Return Value: None

local function audstopreq(cb)
	if stop() and cb then cb() return end
	stopreqcb = cb
end

--Function name: ttstopind
--Function: After calling stoptts () interface, tts stops playing the message handler
--Parameters: None
--Return Value: None

function ttstopind()
	print("ttstopind",spending,stopreqcb)
	if stopreqcb then
		stopreqcb()
		stopreqcb = nil
	elseif spending then
		playbegin(spriority,styp,spath,svol,scb,sdup,sduprd)
	end
end

--Function name: recordstopind
--Function: After calling stoprecord () interface, record stops playing the message processing function
--Parameters: None
--Return Value: None

function recordstopind()
	print("recordstopind",spending,stopreqcb)
	if stopreqcb then
		stopreqcb()
		stopreqcb = nil
	elseif spending then
		playbegin(spriority,styp,spath,svol,scb,sdup,sduprd)
	end
end

local procer =
{
	AUDIO_STOP_REQ = audstopreq,--lib script to stop audio by sending message, user script not to send this message

}
-- Register message processing function table
sys.regapp(procer)
