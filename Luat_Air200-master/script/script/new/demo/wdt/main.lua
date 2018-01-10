-- PROJECT and VERSION variables must be defined at this location
-- PROJECT: ascii string type, you can easily define, as long as you do not use it
--VERSION: ascii string type, if using the function of firmware upgrade of Luat Cloud Platform, it must be defined according to "X.X.X" and X means 1 digit; otherwise it can be freely defined
PROJECT = "WDT"
VERSION = "1.0.0"
require"sys"
--If you use the UART output trace, open this line comment code "--sys.opntrace (true, 1)" can, the first two parameters 1 UART1 output trace, modify this parameter according to their own needs
--Here is the earliest place to set the trace port, the code is written here to ensure that the UART port output as much as possible "boot error message appears"
---If you write in the back of other locations, most likely not output error message, thereby increasing the difficulty of debugging

--sys.opntrace(true,1)
-- Load hardware watchdog function module
require"wdt"

sys.init(0,0)
sys.run()
