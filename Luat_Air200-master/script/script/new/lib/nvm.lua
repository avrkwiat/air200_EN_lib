--Module Name: Parameter Management
--Module functions: parameter initialization, read and write and restore the factory settings
--Last modified: 2017.02.23


module(...,package.seeall)

package.path = "/?.lua;".."/?.luae;"..package.path

-- The default parameter configuration is stored in the configname file
-- Real-time parameter configuration is stored in the paraname file
--para: real-time parameter table
--config: default parameter list
local paraname,para,libdftconfig,configname,econfigname = "/para.lua",{}


--Function name: print
--Function: Print interface, all print in this file will be added nvm prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("nvm",...)
end


--Function name: restore
--Function: The parameters are restored to the factory settings, and the contents of the configname file are copied into the paraname file
--Parameters: None
--Return Value: None

function restore()
	local fpara,fconfig = io.open(paraname,"wb"),io.open(configname,"rb")
	if not fconfig then fconfig = io.open(econfigname,"rb") end
	fpara:write(fconfig:read("*a"))
	fpara:close()
	fconfig:close()
	upd(true)
end

--Function name: serialize
--Function: According to different data types, according to different formats, write the formatted data to the file
--Parameters:
--pout: file handle
--o: data
--Return Value: None

local function serialize(pout,o)
	if type(o) == "number" then
		--number type, write the original data directly

		pout:write(o)	
	elseif type(o) == "string" then
		-- String type, around the original data plus double quotation marks

		pout:write(string.format("%q", o))
	elseif type(o) == "boolean" then
		--boolean type, converted to string write

		pout:write(tostring(o))
	elseif type(o) == "table" then
		--table type, plus newline, curly brackets, brackets, double quotation marks

		pout:write("{\n")
		for k,v in pairs(o) do
			if type(k) == "number" then
				pout:write(" [", k, "] = ")
			elseif type(k) == "string" then
				pout:write(" [\"", k,"\"] = ")
			else
				error("cannot serialize table key " .. type(o))
			end
			serialize(pout,v)
			pout:write(",\n")
		end
		pout:write("}\n")
	else
		error("cannot serialize a " .. type(o))
	end
end

--Function name: upd
--Function: Update the real-time parameter list
--Parameters:
--overide: whether to force the update of real-time parameters with default parameters
--Return Value: None

function upd(overide)
	for k,v in pairs(libdftconfig) do
		if k ~= "_M" and k ~= "_NAME" and k ~= "_PACKAGE" then
			if overide or para[k] == nil then
				para[k] = v
			end			
		end
	end
end

--Function name: load
--Function: Initialize the parameters
--Parameters: None
--Return Value: None

local function load()
	local f = io.open(paraname,"rb")
	if not f or f:read("*a") == "" then
		if f then f:close() end
		restore()
		return
	end
	f:close()
	
	f,para = pcall(require,string.match(paraname,"/(.+)%.lua"))
	if not f then
		restore()
		return
	end
	upd()
end

--Function name: save
--Function: Save the parameter file
--Parameters:
--s: true save, true save, false or nil not save
--Return Value: None

local function save(s)
	if not s then return end
	local f = io.open(paraname,"wb")

	f:write("module(...)\n")

	for k,v in pairs(para) do
		if k ~= "_M" and k ~= "_NAME" and k ~= "_PACKAGE" then
			f:write(k, " = ")
			serialize(f,v)
			f:write("\n")
		end
	end

	f:close()
end

--Function name: set
--Function: Set the value of a parameter
--Parameters:
--k: parameter name
--v: new value to be set
--r: set the reason, only pass in a valid parameter, and the new value of v and the old value has changed, will throw a PARA_CHANGED_IND message
--s: need to write to the file system, false is not written, the rest are written
--Return value: true

function set(k,v,r,s)
	local bchg = true
	if type(v) ~= "table" then
		bchg = (para[k] ~= v)
	end
	print("set",bchg,k,v,r,s)
	if bchg then		
		para[k] = v
		save(s or s==nil)
		if r then sys.dispatch("PARA_CHANGED_IND",k,v,r) end
	end
	return true
end

--Function name: sett
--Function: Set the value of one of the parameters of table type
--Parameters:
--k: table parameter name
--Key in the kk: table parameter
--v: new value to be set
--r: Set the reason, TPAL_CHANGED_IND message will be thrown only if valid parameter is passed, and new value of v and old value have changed
--s: need to write to the file system, false is not written, the rest are written
--Return value: true

function sett(k,kk,v,r,s)
	if para[k][kk] ~= v then
		para[k][kk] = v
		save(s or s==nil)
		if r then sys.dispatch("TPARA_CHANGED_IND",k,kk,v,r) end
	end
	return true
end

--Function name: flush
--Function: write parameters from memory to file
--Parameters: None
--Return Value: None

function flush()
	save(true)
end

--Function name: get
--Function: Read parameter value
--Parameters:
--k: parameter name
--Return value: parameter value

function get(k)
	if type(para[k]) == "table" then
		local tmp = {}
		for kk,v in pairs(para[k]) do
			tmp[kk] = v
		end
		return tmp
	else
		return para[k]
	end
end

---Function name: gett
--Function: Read the value of one of the parameters of table type
--Parameters:
--k: table parameter name
--Key in the kk: table parameter
--Return value: parameter value

function gett(k,kk)
	return para[k][kk]
end

--Function name: init
--Function: Initialize parameter storage module
--Parameters:
--dftcfgfile: the default configuration file
--Return Value: None

function init(dftcfgfile)
	local f
	f,libdftconfig = pcall(require,string.match(dftcfgfile,"(.+)%.lua"))
	configname,econfigname = "/lua/"..dftcfgfile,"/lua/"..dftcfgfile.."e"
	-- Initialize the configuration file, read the parameters from the file into memory

	load()
end
