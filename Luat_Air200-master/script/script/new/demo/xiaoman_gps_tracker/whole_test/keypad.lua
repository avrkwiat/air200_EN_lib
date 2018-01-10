
--Module Name: Key Detection
--Module Features: Key Detection, Short Keys and Long Keys Generated Internal Messages: MMI_KEYPAD_IND and MMI_KEYPAD_LONGPRESS_IND
--Last modified: 2017.02.16


module(...,package.seeall)

local curkey
local KEY_LONG_PRESS_TIME_PERIOD = 3000
KEY_SOS = "SOS"
local keymap = {["12"] = KEY_SOS}
local sta = "IDLE"

local function keylongpresstimerfun ()
	if curkey then
		sys.dispatch("MMI_KEYPAD_LONGPRESS_IND",curkey,"KEY")
		sta = "LONG"
	end
end

local function stopkeylongpress()
	curkey = nil
	sys.timer_stop(keylongpresstimerfun)
end

local function startkeylongpress(key)
	stopkeylongpress()
	curkey = key
	sys.timer_start(keylongpresstimerfun,KEY_LONG_PRESS_TIME_PERIOD)
end

local function keymsg(msg)
	print("keypad.keymsg",msg.key_matrix_row,msg.key_matrix_col)
	local key = keymap[msg.key_matrix_row..msg.key_matrix_col]
	if key then
		if msg.pressed then
			sta = "PRESSED"
			startkeylongpress(key)			
		else
			stopkeylongpress()
			if sta == "PRESSED" then
				sys.dispatch("MMI_KEYPAD_IND",key)
			end
			sta = "IDLE"
		end
	end
end

sys.regmsg(rtos.MSG_KEYPAD,keymsg)
rtos.init_module(rtos.MOD_KEYPAD,0,0x04,0x02)
