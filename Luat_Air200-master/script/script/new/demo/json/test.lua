module(...,package.seeall)


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

-----------------------Encode test------------------------
local torigin =
{
	KEY1 = "VALUE1",
	KEY2 = "VALUE2",
	KEY3 = "VALUE3",
	KEY4 = "VALUE4",
	KEY5 = {KEY5_1="VALU5_1",KEY5_2="VALU5_2"},
	KEY6 = {1,2,3},
}

local jsondata = json.encode(torigin)
print(jsondata)
-----------------------Encode test------------------------




-----------------------encodedecode test test------------------------
--{"KEY3":"VALUE3","KEY4":"VALUE4","KEY2":"VALUE2","KEY1":"VALUE1","KEY5":{"KEY5_2":"VALU5_2","KEY5_1":"VALU5_1"}},"KEY6":[1,2,3]}
local origin = "{\"KEY3\":\"VALUE3\",\"KEY4\":\"VALUE4\",\"KEY2\":\"VALUE2\",\"KEY1\":\"VALUE1\",\"KEY5\":{\"KEY5_2\":\"VALU5_2\",\"KEY5_1\":\"VALU5_1\"},\"KEY6\":[1,2,3]}"
local tjsondata,result,errinfo = json.decode(origin)
if result then
	print(tjsondata["KEY1"])
	print(tjsondata["KEY2"])
	print(tjsondata["KEY3"])
	print(tjsondata["KEY4"])
	print(tjsondata["KEY5"]["KEY5_1"],tjsondata["KEY5"]["KEY5_2"])
	print(tjsondata["KEY6"][1],tjsondata["KEY6"][2],tjsondata["KEY6"][3])
else
	print("json.decode error",errinfo)
end
-----------------------decode test------------------------

