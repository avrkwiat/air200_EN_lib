require"common"
module(...,package.seeall)

local i2cid = 1


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--Function name: init
--Function: Open i2c, write initialization command to slave register and read value from slave register
--Parameters: None
--Return Value: None

local function init()
	local i2cslaveaddr = 0x0E
	-- Note: here i2cslaveaddr is a 7bit address
	-- If the i2c peripheral manual to 8bit address, you need to move the 8bit address to the right one, assigned to the i2cslaveaddr variable
	-- If i2c peripheral manual is given to the 7bit address directly to the 7bit address assigned to the i2cslaveaddr variable
	-- When initiating a read and write operation, the first byte after the start signal is the command byte
	-- Bit 0 of the command byte indicates a read / write bit, 0 indicates a write, and 1 indicates a read
	-- Command byte bit7-bit1,7 bit that peripheral address
	--i2c the underlying driver in the read operation, with (i2cslaveaddr << 1) | 0x01 command byte
	--i2c The underlying driver generates a command byte with (i2cslaveaddr << 1) | 0x00 when writing
	if i2c.setup(i2cid,i2c.SLOW,i2cslaveaddr) ~= i2c.SLOW then
		print("init fail")
		return
	end
	local cmd,i = {0x1B,0x00,0x6A,0x01,0x1E,0x20,0x21,0x04,0x1B,0x00,0x1B,0xDA,0x1B,0xDA}
	for i=1,#cmd,2 do
		i2c.write(i2cid,cmd[i],cmd[i+1])
		print("init",string.format("%02X",cmd[i]),common.binstohexs(i2c.read(i2cid,cmd[i],1)))
	end
end

init()

-- Turn off i2c after 5 seconds
sys.timer_start(i2c.close,5000,i2cid)
