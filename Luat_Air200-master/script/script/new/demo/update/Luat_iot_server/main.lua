-- PROJECT and VERSION variables must be defined at this location
-- PROJECT: ascii string type, you can easily define, as long as you do not use it
--VERSION: ascii string type, if using the function of firmware upgrade of Luat Cloud Platform, it must be defined according to "X.X.X" and X means 1 digit; otherwise it can be freely defined
PROJECT = "LUAT_IOT_SERVER_UPDATE"
VERSION = "1.0.0"
--[[
To use the Luat IoT firmware upgrade feature, you must follow these steps:
1, open the front end of Luat IoT platform page: https://iot.openluat.com/
2, if there is no user name, registered users
3, registered users, if there is no corresponding project, create a new project
4, into the corresponding project, click on the project information on the left, there will be information on the right, find ProductKey: The ProductKey content, assigned to the PRODUCT_KEY variable
]]
PRODUCT_KEY = "v32xEAKsGTIEQxtqgwCldp5aPlcnPs3K"
require"sys"
--If you use the UART output trace, open this line comment code "--sys.opntrace (true, 1)" can, the first two parameters 1 UART1 output trace, modify this parameter according to their own needs
--Here is the earliest place to set the trace port, the code is written here to ensure that the UART port output as much as possible "boot error message appears"
---If you write in the back of other locations, most likely not output error message, thereby increasing the difficulty of debugging

--sys.opntrace(true,1)

--Follow the steps below when using the upgrade server of Luat Cloud Platform
--1, load the update module require "update"
--After the above step is performed, each time the device is powered on and the network is ready, it automatically connects to the upgrade server to perform the upgrade function
--2, if you need to regularly perform the upgrade function, open - update.setperiod (3600) comments, according to their needs, configure the timing period
--3, if you need to perform real-time upgrade function, reference --sys.timer_start (update.request, 120000), according to their needs, call update.request ()

require"update"
--update.setperiod(3600)
--sys.timer_start(update.request,120000)
require"dbg"
sys.timer_start(dbg.setup,12000,"UDP","ota.airm2m.com",9072)
require"test"
-- S3 development board: the hardware has opened the watchdog function, the use of S3 development board users, to open this line of comment code "--require" wdt "", or about 4 minutes will restart
--require"wdt"

sys.init(0,0)
sys.run()
