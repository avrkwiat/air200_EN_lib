--Module Name: Hardware Watchdog
--Module Function: Support hardware watchdog function
--Last modified: 2017.02.16
--Design docs reference doc \ Xia Man GPS locator related documents \ Watchdog descritption.doc


module(...,package.seeall)

-- Module reset microcontroller pin

local RST_SCMWD_PIN = pio.P0_6
-- The module and the microcontroller feed each other's pins

local WATCHDOG_PIN = pio.P0_5

--scm_active: whether the microcontroller is operating normally, true means normal, false or nil means abnormal
--get_scm_cnt: "Remaining number of times to detect whether the MCU is feeding the dog to the module"
local scm_active,get_scm_cnt = true,20
--testcnt: The number of dogs that have been fed during the dog feeding test
--testing: Whether feeding dog test
local testcnt,testing = 0

--Function name: getscm
--Function: Read the "MCU pin to the module feed dog" level
--Parameters:
--tag: "normal" means normal feeding dog, "test" means feeding dog test
--Return Value: None

local function getscm(tag)
	-- Dogs are not allowed to feed normally if the dog feeding test is in progress

	if tag=="normal" and testing then return end
	-- Test the number of remaining minus one

	get_scm_cnt = get_scm_cnt - 1
	-- If it is a dog feed test, stop normal dog feed process

	if tag=="test" then
		sys.timer_stop(getscm,"normal")
	end
	-- The number of remaining tests is not 0 yet

	if get_scm_cnt > 0 then
		-- feeding dog test

		if tag=="test" then
			-- If high is detected

			if pio.pin.getval(WATCHDOG_PIN) == 1 then				
				testcnt = testcnt+1
				-- did not meet three consecutive feeding dog, 100 milliseconds, continue feeding the dog next time

				if testcnt<3 then
					sys.timer_start(feed,100,"test")
					get_scm_cnt = 20
					return
				-- Feed the dog test is over, feed the dog 3 times in succession, the one-chip computer will reset the module

				else
					testing = nil
				end
			end
		end
		-- 100 ms followed by detection

		sys.timer_start(getscm,100,tag)
	-- the test is over

	else
		get_scm_cnt = 20
		if tag=="test" then
			testing = nil
		end
		-- Dogs are being fed and the microcontroller is running abnormally

		if tag=="normal" and not scm_active then
			-- Reset the microcontroller

			pio.pin.setval(0,RST_SCMWD_PIN)
			sys.timer_start(pio.pin.setval,100,1,RST_SCMWD_PIN)
			print("wdt reset 153b")
			scm_active = true
		end
	end
	-- If a low level is detected, then the microcontroller is operating normally

	if pio.pin.getval(WATCHDOG_PIN) == 0 and not scm_active then
		scm_active = true
		print("wdt scm_active = true")
	end
end

--Function name: feedend
--Function: Test "whether the one-chip computer feeds the dog to the module" is normal or not
--Parameters:
--tag: "normal" means normal feeding dog, "test" means feeding dog test
--Return Value: None

local function feedend(tag)
	-- Dogs are not allowed to feed normally if the dog feeding test is in progress

	if tag=="normal" and testing then return end
	-- Mutually feed dog pins configured as input

	pio.pin.close(WATCHDOG_PIN)
	pio.pin.setdir(pio.INPUT,WATCHDOG_PIN)
	print("wdt feedend",tag)
	-- If it is a dog feed test, stop normal dog feed process

	if tag=="test" then
		sys.timer_stop(getscm,"normal")
	end
	-- read the dog feed input level after 100 milliseconds
	-- read every 100 milliseconds, read 20 consecutive times, as long as once read low, that "the microcontroller feed the dog module" normal
	sys.timer_start(getscm,100,tag)
end

--Function name: feed
--Function: The module begins to feed the dog to the one-chip computer
--Parameters:
--tag: "normal" means normal feeding dog, "test" means feeding dog test
--Return Value: None

function feed(tag)
	-- Dogs are not allowed to feed normally if the dog feeding test is in progress

	if tag=="normal" and testing then return end
	-- If the microcontroller is running properly or is feeding the dog test

	if scm_active or tag=="test" then
		scm_active = false
	end

	-- mutual dog feed pin configured as output, "the module began to feed the dog", the output 2 seconds low

	pio.pin.close(WATCHDOG_PIN)
	pio.pin.setdir(pio.OUTPUT,WATCHDOG_PIN)
	pio.pin.setval(0,WATCHDOG_PIN)
	print("wdt feed",tag)
	-- 2 minutes to start the next normal feeding dog

	sys.timer_start(feed,120000,"normal")
	-- If it is a dog feed test, stop normal dog feed process

	if tag=="test" then
		sys.timer_stop(feedend,"normal")
	end
	-- 2 seconds after the test began "microcontroller to feed the dog module" is normal

	sys.timer_start(feedend,2000,tag)
end

--Function name: open
--Function: Open the hardware watchdog function on the Air200 development board and immediately feed the dog
--Parameters: None
--Return Value: None

function open()
	pio.pin.setdir(pio.OUTPUT,WATCHDOG_PIN)
	pio.pin.setval(1,WATCHDOG_PIN)
	feed("normal")
end

--Function name: close
--Function: Turn off the hardware watchdog function on the Air200 development board
--Parameters: None
--Return Value: None

function close()
	sys.timer_stop_all(feedend)
	sys.timer_stop_all(feed)
	sys.timer_stop_all(getscm)
	sys.timer_stop(pio.pin.setval,1,RST_SCMWD_PIN)
	pio.pin.close(RST_SCMWD_PIN)
	pio.pin.close(WATCHDOG_PIN)
	scm_active,get_scm_cnt,testcnt,testing = true,20,0
end

--Function name: test
--Function: Test the functionality of the "Hardware Watchdog Reset Air200 Module" on the Air200 Development Board
--Parameters: None
--Return Value: None

function test()
	if not testing then
		testcnt,testing = 0,true
		feed("test")
	end
end

-- Module reset microcontroller pin, the default output high

pio.pin.setdir(pio.OUTPUT1,RST_SCMWD_PIN)
pio.pin.setval(1,RST_SCMWD_PIN)

open()
