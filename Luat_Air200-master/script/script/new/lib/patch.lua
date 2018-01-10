--Module Name: Lua comes with patch interface
--Module features: patch Some Lua comes with the interface, to avoid abnormal crashes
--Last modified on: 2017.02.14


-- Save the os.time interface that comes with Lua
local oldostime = os.time

--Function name: safeostime
--Function: package custom os.time interface
--Parameters:
--t: date table, if not passed, using the current system time
--Return value: t Time The number of seconds elapsed since 0:00:00 on January 1, 1970

function safeostime(t)
	return oldostime(t) or 0
end

-- Lua comes with the os.time interface points to a custom safeostime interface

os.time = safeostime

-- Save Lua's own os.date interface

local oldosdate = os.date


--Function name: safeosdate
--Function: package custom os.date interface
--Parameters:
--s: output format
--t: the number of seconds elapsed since 0:00:00 on January 1, 1970
--Return value: Reference Lua comes with os.date interface description

function safeosdate(s,t)
    if s == "*t" then
        return oldosdate(s,t) or {year = 2012,
                month = 12,
                day = 11,
                hour = 10,
                min = 9,
                sec = 0}
    else
        return oldosdate(s,t)
    end
end

-- Lua comes with os.date interface points to a custom safeosdate interface

os.date = safeosdate

-- Save Lua's own json.decode interface

local oldjsondecode = json.decode

--Function name: safejsondecode
--Function: package custom json.decode interface
--Parameters:
--s: string in json format
--return value:
--The first return value is parsing json string after the table
--The second return value is the result of the parsing (true means success, false fails)
--The third return value is optional (only the second return value is false, it makes sense), that an error message

function safejsondecode(s)
	local result,info = pcall(oldjsondecode,s)
	if result then
		return info,true
	else
		return {},false,info
	end
end

-- Lua comes with json.decode interface points to a custom safejsondecode interface

json.decode = safejsondecode

