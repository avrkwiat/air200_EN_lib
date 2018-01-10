
--Module Name: Phonebook test
--Module function: test phone book to read and write
--Module last modified: 2017.05.23

module(...,package.seeall)
require"pb"

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

--Function name: storagecb
--Function: set the phone book storage area callback function
--Parameters:
--result: set the result, true is successful, the rest is failed
--Return Value: None

local function storagecb(result)
	print("storagecb",result)
	-- Delete the first phonebook record
	pb.deleteitem(1,deletecb)
end

--Function name: writecb
--Function: write a phone book record callback function
--Parameters:
--result: write result, true is successful, the rest is failed
--Return Value: None

function writecb(result)
	print("writecb",result)
	-- Read the first phonebook record
	pb.read(1,readcb)
end

--Function name: deletecb
--Function: delete a phone book record callback function
--Parameters:
--result: delete result, true is successful, the rest is failed
--Return Value: None

function deletecb(result)
	print("deletecb",result)
	-- Write phone book record to the first position
	pb.writeitem(1,"name1","11111111111",writecb)
end

--Function name: readcb
--Function: read a phone book record callback function
--Parameters:
--result: read the result, true is successful, the rest is failed
--name: name
--number: number
--Return Value: None

function readcb(result,name,number)
	print("readcb",result,name,number)
end


local function ready(result,name,number)
	print("ready",result)
	if result then
		sys.timer_stop(pb.read,1,ready)
		-- set the phone book storage area, SM said sim card storage, ME said terminal storage, open the following 2 lines in a row test
		pb.setstorage("SM",storagecb)
		--pb.setstorage("ME",storagecb)
	end
end

-- The cycle timer is just to determine if the PB function module is ready
sys.timer_loop_start(pb.read,2000,1,ready)
