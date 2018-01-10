
--Module Name: Pin Configuration Management
--Module Features: pinout, input, interrupt configuration and management
--Last modified: 2017.03.04

module(...,package.seeall)

local allpins = {}

--Function name: init
--Function: Initializes all pins in the allpins table
--Parameters: None
--Return Value: None

local function init()
	for _,v in ipairs(allpins) do
		if v.init == false then
			-- Do not initialize

		elseif v.ptype == nil or v.ptype == "GPIO" then
			v.inited = true
			pio.pin.setdir(v.dir or pio.OUTPUT,v.pin)
			--[[if v.dir == nil or v.dir == pio.OUTPUT then
				set(v.defval or false,v)
			else]]
			if v.dir == pio.INPUT or v.dir == pio.INT then
				v.val = pio.pin.getval(v.pin) == v.valid
			end
		--[[elseif v.set then
			set(v.defval or false,v)]]
		end
	end
end

--Function name: reg
--Function: Register the configuration of one or more PIN pins and initialize the PIN pin
--Parameters:
--cfg1: PIN pin configuration, table type
--...: 0 or more PIN pin configurations
--Return Value: None

function reg(cfg1,...)
	table.insert(allpins,cfg1)
	local i
	for i=1,arg.n do
		table.insert(allpins,unpack(arg,i,i))
		print("reg",unpack(arg,i,i).pin)
	end
	init()
end

--Function name: dereg
--Function: Deregister the configuration of one or more PIN pins and turn off the PIN pin
--Parameters:
--cfg1: PIN pin configuration, table type
--...: 0 or more PIN pin configurations
--Return Value: None

function dereg(cfg1,...)
	pio.pin.close(cfg1.pin)
	for k,v in pairs(allpins) do
		if v.pin==cfg1.pin then
			table.remove(allpins,k)
		end
	end
	
	for k,v in pairs(allpins) do
		pio.pin.close(unpack(arg,i,i).pin)
		if v.pin==unpack(arg,i,i).pin then
			table.remove(allpins,k)
		end
	end
end

--Function name: get
--Function: Read the input or interrupt pin level status
--Parameters:
--???????? p: pin name
--Returns: true if the pin's level matches the valid value of the pin configuration; false otherwise

function get(p)
	return pio.pin.getval(p.pin) == p.valid
end

--Function name: set
--Function: Set the level of the output pin
--Parameters:
--???????? bval: true means the same level as the configured valid value, and false means the opposite
--p: pin name
--Return Value: None

function set(bval,p)
	p.val = bval

	if not p.inited and (p.ptype == nil or p.ptype == "GPIO") then
		p.inited = true
		pio.pin.setdir(p.dir or pio.OUTPUT,p.pin)
	end

	if p.set then p.set(bval,p) return end

	if p.ptype ~= nil and p.ptype ~= "GPIO" then print("unknwon pin type:",p.ptype) return end

	local valid = p.valid == 0 and 0 or 1 -- Default high effective

	local notvalid = p.valid == 0 and 1 or 0
	local val = bval == true and valid or notvalid

	if p.pin then pio.pin.setval(val,p.pin) end
end


--Function name: setdir
--Function: Set the direction of the pin
--Parameters:
--???????? dir: pio.OUTPUT, pio.OUTPUT1, pio.INPUT, or pio.INT, for more details, refer to the "dir Value Definition"
--p: pin name
--Return Value: None

function setdir(dir,p)
	if p and p.ptype == nil or p.ptype == "GPIO" then
		if not p.inited then
			p.inited = true
		end
		if p.pin then
			pio.pin.close(p.pin)
			pio.pin.setdir(dir,p.pin)
			p.dir = dir
		end
	end
end


--Function name: intmsg
--Function: Interrupt pin interrupt handler will throw a logic interrupt message to other modules
--Parameters:
--???????? msg: table type; msg.int_id: interrupt level type, cpu.INT_GPIO_POSEDGE high interrupt; msg.int_resnum: interrupt pin id
--Return Value: None

local function intmsg(msg)
	local status = 0

	if msg.int_id == cpu.INT_GPIO_POSEDGE then status = 1 end

	for _,v in ipairs(allpins) do
		if v.dir == pio.INT and msg.int_resnum == v.pin then
			v.val = v.valid == status
			if v.intcb then v.intcb(v.val) end
			return
		end
	end
end
-- Register pin interrupt handler

sys.regmsg(rtos.MSG_INT,intmsg)
