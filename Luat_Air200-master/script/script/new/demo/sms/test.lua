
--Module Name: SMS test
--Module Features: SMS sending and receiving test
--Module last modified: 2017.02.20

require"sms"
module(...,package.seeall)

--Function name: print
--Function: Print Interface, all prints in this file will be prefixed with smsapp
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


----------------------------------------- SMS reception function test [Start]-----------------------------------------
local function procnewsms(num,data,datetime)
	print("procnewsms",num,data,datetime)
end

sms.regnewsmscb(procnewsms)
-----------------------------------------SMS reception function test [End]-----------------------------------------





-----------------------------------------SMS send test [Start]-----------------------------------------
local function sendtest1(result,num,data)
	print("sendtest1",result,num,data)
end

local function sendtest2(result,num,data)
	print("sendtest2",result,num,data)
end

local function sendtest3(result,num,data)
	print("sendtest3",result,num,data)
end

local function sendtest4(result,num,data)
	print("sendtest4",result,num,data)
end

sms.send("10086","111111",sendtest1)
sms.send("10086","Article 2 SMS",sendtest2)
sms.send("10086","qeiuqwdsahdkjahdkjahdkja122136489759725923759823hfdskfdkjnbzndkjhfskjdfkjdshfkjdsfks83478648732432qeiuqwdsahdkjahdkjahdkja122136489759725923759823hfdskfdkjnbzndkjhfskjdfkjdshfkjdsfks83478648732432qeiuqwdsahdkjahdkjahdkja122136489759725923759823hfdskfdkjnbzndkjhfskjdfkjdshfkjdsfks83478648732432",sendtest3)
sms.send("10086","Wah Hong is sprinkle qeiuqwdsahdkjahdkjahdkja122136489759725923759823hfdskfdkjnbzndkjhfskjdfkjdshfkjdsfks83478648732432qeiuqwdsahdkjahdkjahdkja122136489759725923759823hfdskfdkjnbzndkjhfskjdfkjdshfkjdsfks83478648732432qeiuqwdsahdkjahdkjahdkja122136489759725923759823hfdskfdkjnbzndkjhfskjdfkjdshfkjdsfks83478648732432",sendtest4)
-----------------------------------------SMS send test [End]-----------------------------------------
