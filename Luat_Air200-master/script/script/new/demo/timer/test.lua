module(...,package.seeall)

-- Timer test program
-- Timer 1: Cycle timer, cycle time is 1 second, "TimerFunc1 check1" is printed every time, timer 2 is detected to timer 5 is active, print out the timer is active
-- Timer 2: One-shot timer, triggered 5 seconds after startup, "TimerFunc2" printed, and then automatically turned off
-- Timer 3: One-shot timer, triggered 10 seconds after startup, "TimerFunc3" printed, and then automatically turned off
-- Timer 4: Loop timer with 2-second cycle, "TimerFunc4" every time
-- Timer 5: One-shot timer, triggered 60 seconds after startup, "TimerFunc5", timer 4 off, timer 6,7,8, and then turned off automatically
-- Timer 6: Cycle timer with 1 second cycle, "TimerFunc1 check6" every time
-- Timer 7: Cycle timer with 1 second cycle, printing "TimerFunc1 check7" each time
-- Timer 8: One-shot timer, triggered 5 seconds after startup, "CloseTimerFunc1 check check6 check7" is printed and then automatically turned off
local function TimerFunc2AndTimerFunc3(id)
	print("TimerFunc"..id)
end

local function TimerFunc4()
	print("TimerFunc4")
end

local function TimerFunc5()
	print("TimerFunc5")
	sys.timer_stop(TimerFunc4)
	sys.timer_loop_start(TimerFunc1,1000,"check6")
	sys.timer_loop_start(TimerFunc1,1000,"check7")
	sys.timer_start(CloseTimerFunc1,5000)
end

function CloseTimerFunc1()
	print("CloseTimerFunc1 check check6 check7")
	sys.timer_stop_all(TimerFunc1)
end

function TimerFunc1(id)
	print("TimerFunc1 "..id)
	if id=="check1" then		
		if sys.timer_is_active(TimerFunc2AndTimerFunc3,2) then print("Timer2 active") end
		if sys.timer_is_active(TimerFunc2AndTimerFunc3,3) then print("Timer3 active") end
		if sys.timer_is_active(TimerFunc4) then print("Timer4 active") end
		if sys.timer_is_active(TimerFunc5) then print("Timer5 active") end
	end
end



sys.timer_loop_start(TimerFunc1,1000,"check1")
sys.timer_start(TimerFunc2AndTimerFunc3,5000,2)
sys.timer_start(TimerFunc2AndTimerFunc3,10000,3)
sys.timer_loop_start(TimerFunc4,2000)
sys.timer_start(TimerFunc5,60000)
