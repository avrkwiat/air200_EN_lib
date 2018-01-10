
-- PROJECT and VERSION variables must be defined at this location
-- PROJECT: ascii string type, you can easily define, as long as you do not use it
--VERSION: ascii string type, if using the function of firmware upgrade of Luat Cloud Platform, it must be defined according to "X.X.X" and X means 1 digit; otherwise it can be freely defined
PROJECT = "LBS_LOC"
VERSION = "1.0.0"

--The use of base stations to obtain latitude and longitude functions, you must follow these steps:
--1, open the front end of Luat IoT platform page: https://iot.openluat.com/
--2, if there is no user name, registered users
--3, registered users, if there is no corresponding project, create a new project
--4, into the corresponding project, click on the project information on the left, there will be information on the right, find ProductKey: The ProductKey content, assigned to the PRODUCT_KEY variable

PRODUCT_KEY = "v32xEAKsGTIEQxtqgwCldp5aPlcnPs3K"
require"sys"

--If you use the UART output trace, open this line comment code "--sys.opntrace (true, 1)" can, the first two parameters 1 UART1 output trace, modify this parameter according to their own needs
--Here is the earliest place to set the trace port, the code is written here to ensure that the UART port output as much as possible "boot error message appears"
---If you write in the back of other locations, most likely not output error message, thereby increasing the difficulty of debugging

--sys.opntrace(true,1)
require"test"

-- S3 development board: the hardware has opened the watchdog function, the use of S3 development board users, to open this line of comment code "--require" wdt "", or about 4 minutes will restart
--require"wdt"

sys.init(0,0)
sys.run()
