require"config"
require"nvm"
module(...,package.seeall)

--Functional Requirements:
--Test config.lua 4 parameters
--After each parameter changes, all the parameters will be printed out


local function print(...)
	_G.print("test",...)
end

local function getTablePara(t)
	if type(t)=="table" then
		local ret = "{"
		for i=1,#t do
			ret = ret..t[i]..(i==#t and "" or ",")
		end
		ret = ret.."}"
		return ret
	end
end

local function printAllPara()
	_G.print("\r\n\r\n")
	print("---printAllPara begin---")
	_G.print("strPara = "..nvm.get("strPara"))
	_G.print("numPara = "..nvm.get("numPara"))
	_G.print("boolPara = "..tostring(nvm.get("boolPara")))
	_G.print("tablePara = "..getTablePara(nvm.get("tablePara")))
	print("---printAllPara end  ---\r\n\r\n")
end

local function restoreFunc()
	print("restoreFunc")
	nvm.restore()
	printAllPara()
end

local function paraChangedInd(k,v,r)
	print("paraChangedInd",k,v,r)
    printAllPara()
	return true
end

local function tParaChangedInd(k,kk,v,r)
	print("tParaChangedInd",k,kk,v,r)
    printAllPara()
	return true
end

local procer =
{
	PARA_CHANGED_IND = paraChangedInd, -- call nvm.set interface to modify the value of the parameter, if the value of the parameter changes, nvm.lua will call the sys.dispatch interface throw PARA_CHANGED_IND message
	TPARA_CHANGED_IND = tParaChangedInd,	-- Call the nvm.sett interface to modify the value of one of the parameters of the table type, if the value changes, nvm.lua will call the sys.dispatch interface to throw the TPARA_CHANGED_IND message
}
-- Register message handling functions

sys.regapp(procer)

-- Initialize the parameter management module

nvm.init("config.lua")

-- Print out all parameters

printAllPara()
-- Modify strPara parameter value for the str2, after the modification, nvm.lua will call the sys.dispatch interface throw PARA_CHANGED_IND message, test.lua PARA_CHANGED_IND message should be processed call paraChangedInd (observe paraChangedInd print out k, v, r) , Print out all parameters automatically
nvm.set("strPara","str2","strPara2")
-- Modify strPara parameter value is str3, modified, although strPara value becomes str3, but nvm.lua will not throw PARA_CHANGED_IND message
-- because the third parameter was not passed in when nvm.set was called
--nvm.set("strPara","str3")
sys.timer_start(nvm.set,1000,"strPara","str3")

-- Modify numPara parameter value is 2, after modification, nvm.lua will call the sys.dispatch interface throw PARA_CHANGED_IND message, test.lua should handle PARA_CHANGED_IND message call paraChangedInd (Please observe the paraChangedInd printed out k, v, r) , Print out all parameters automatically
--nvm.set("numPara",2,"numPara2",false)
sys.timer_start(nvm.set,2000,"numPara",2,"numPara2",false)
--nvm.set("numPara",3,"numPara3",false)
sys.timer_start(nvm.set,3000,"numPara",3,"numPara3",false)
--nvm.set("numPara",4,"numPara4",false)
sys.timer_start(nvm.set,4000,"numPara",4,"numPara4",false)
-- After the implementation of the above three nvm.set statement, the value of numPara eventually becomes 4, but it becomes 4 in memory, the file is actually stored in 1, execute the following statement, will write File system
nvm.flush()
-- In other words, the fourth parameter in nvm.set is written to the file system (false is not written to the file system, and the rest are written to the file system), the purpose is to reduce the number of write files if the continuous setting of many parameters

-- Similar to nvm.set ("strPara", "str2", "strPara2")
--nvm.set("tablePara",{"item2-1","item2-2","item2-3"},"tablePara2")
sys.timer_start(nvm.set,5000,"tablePara",{"item2-1","item2-2","item2-3"},"tablePara2")
-- Modify only the second item in tablePara to item3-2
--nvm.sett("tablePara",2,"item3-2","tablePara3")
sys.timer_start(nvm.sett,6000,"tablePara",2,"item3-2","tablePara3")

-- Restore factory settings and print out all parameters
sys.timer_start(restoreFunc,9000)
