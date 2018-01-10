-- PROJECT and VERSION variables must be defined at this location
-- PROJECT: ascii string type, you can easily define, as long as you do not use it
--VERSION: ascii string type, if using the function of firmware upgrade of Luat Cloud Platform, it must be defined according to "X.X.X" and X means 1 digit; otherwise it can be freely defined
PROJECT = "USER_SERVER_UPDATE"
VERSION = "1.0.0"
require"sys"
--If you use the UART output trace, open this line comment code "--sys.opntrace (true, 1)" can, the first two parameters 1 UART1 output trace, modify this parameter according to their own needs
--Here is the earliest place to set the trace port, the code is written here to ensure that the UART port output as much as possible "boot error message appears"
---If you write in the back of other locations, most likely not output error message, thereby increasing the difficulty of debugging

--sys.opntrace(true,1)

--Use the user's own upgrade server, follow these steps
--1, load the update module require "update"
--2, set the user's own upgrade server address and port update.setup ("udp", "www.userserver.com", 2233)
--After performing the above two steps, each time the device is powered on and the network is ready, it automatically connects to the upgrade server to perform the upgrade function
--3, if you need to regularly perform the upgrade function, open - update.setperiod (3600) comments, according to their needs, configure the timing period
--4, if you need to perform real-time upgrade function, reference --sys.timer_start (update.request, 120000), according to their own needs, call update.request ()

require"update"
update.setup("udp","www.userserver.com",2233)
--update.setperiod(3600)
--sys.timer_start(update.request,120000)
require"dbg"
sys.timer_start(dbg.setup,12000,"UDP","ota.airm2m.com",9072)
require"test"
-- S3 development board: the hardware has opened the watchdog function, the use of S3 development board users, to open this line of comment code "--require" wdt "", or about 4 minutes will restart
--require"wdt"

sys.init(0,0)
sys.run()
