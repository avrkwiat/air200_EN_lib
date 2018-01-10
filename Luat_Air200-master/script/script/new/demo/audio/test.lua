module(...,package.seeall)

require"audio"
require"common"


-- Audio play priority, corresponding to the priority parameter in the audio.play interface. The larger the value is, the higher the priority is. The user sets the priority according to his own needs
--PWRON: boot ringtones
--CALL: Ringtone
-- SMS: new sms ringtone
--TTS: TTS play
PWRON,CALL,SMS,TTS = 3,2,1,0

local function testcb(r)
	print("testcb",r)
end

-- Play audio file test interface, each time you open a line of code for testing
local function testplayfile()

	-- Single ringtones, the default volume level
	--audio.play (CALL, "FILE", "/ ldata / call.mp3")
	-- Single ringtones, volume level 7
	--audio.play (CALL, "FILE", "/ ldata / call.mp3", audiocore.VOL7)
	-- Single ringtones, volume level 7, the end of play or error call testcb callback function
	--audio.play (CALL, "FILE", "/ ldata / call.mp3", audiocore.VOL7, testcb)
	-- ring ring tones, volume level 7, there is no cycle interval (a play immediately after the next play)
	audio.play(CALL,"FILE","/ldata/call.mp3",audiocore.VOL7,nil,true)
	-- ring ring tones, volume level 7, the cycle interval of 2000 milliseconds
	--audio.play(CALL,"FILE","/ldata/call.mp3",audiocore.VOL7,nil,true,2000)
end


-- Play tts test interface, each time you open a line of code for testing
-- "Hello, here is Shanghai HeZhou Communication Technology Co., Ltd., now 18:30"
local ttstr = "Hello, here is Shanghai HeZhou Communication Technology Co., Ltd., now 18:30"
local function testplaytts()
	-- Single play, default volume level
	--audio.play (TTS, "TTS", common.binstohexs (common.gb2312toucs2 (ttstr)))
	-- Single play, volume level 7
	--audio.play (TTS, "TTS", common.binstohexs (common.gb2312toucs2 (ttstr)), audiocore.VOL7)
	-- Single play, volume level 7, playback ended or error call testcb callback function
	--audio.play (TTS, "TTS", common.binstohexs (common.gb2312toucs2 (ttstr)), audiocore.VOL7, testcb)
	-- Loop play, volume level 7, no loop interval (play once after the next play immediately)
	audio.play(TTS,"TTS",common.binstohexs(common.gb2312toucs2(ttstr)),audiocore.VOL7,nil,true)
	
	-- Loop playback, volume level 7, the cycle interval is 2000 milliseconds
	--audio.play(TTS,"TTS",common.binstohexs(common.gb2312toucs2(ttstr)),audiocore.VOL7,nil,true,2000)
end


-- Play conflict test interface, each time you open an if statement for testing
local function testplayconflict()	

	if true then
		-- Ring ringtones
		audio.play(CALL,"FILE","/ldata/call.mp3",audiocore.VOL7,nil,true)
		-- After 5 seconds, play the ring tone
		sys.timer_start(audio.play,5000,PWRON,"FILE","/ldata/pwron.mp3",audiocore.VOL7,nil,true)
		
	end

	

	
--	if true then
--		-- Ring ringtones
--		audio.play (CALL, "FILE", "/ ldata / call.mp3", audiocore.VOL7, nil, true)
--		-- After 5 seconds, try ringing a new SMS ringtone, but with insufficient priority, will not play
--		sys.timer_start (audio.play, 5000, SMS, "FILE", "/ ldata / sms.mp3", audiocore.VOL7, nil, true)
--		--The company is located in:
--	end
	
	
	
--	if true then	
--		-- Loop TTS
--		audio.play(TTS,"TTS",common.binstohexs(common.gb2312toucs2(ttstr)),audiocore.VOL7,nil,true)		
--		-- After 10 seconds, play the ring tone
--		sys.timer_start(audio.play,10000,PWRON,"FILE","/ldata/pwron.mp3",audiocore.VOL7,nil,true)	
--	end
	
end


-- Each time you open the following line of code to test
if string.match(sys.getcorever(),"TTS") then
	sys.timer_start(testplaytts,5000)
else
	sys.timer_start(testplayfile,5000)
end
--sys.timer_start(testplayconflict,5000)
