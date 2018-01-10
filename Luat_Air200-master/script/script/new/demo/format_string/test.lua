module(...,package.seeall)-- All programs are visible

--[[Data format conversion demo
    Value, binary number, character -]]
require "common"-- Utilize the common in the library

require"common"



--[[function name: bittese
    Function: introduce the use of bit library, and print out
    Return Value: None -]]
local function bittest()
	print("bittest:")      -- start of the program running mark
	print(bit.bit(2))	-- The parameter is the number of digits, the effect is 1 to move two digits to the left to print 4
	
	print(bit.isset(5,0))-- The first parameter is the test number, the second is the test location. Number 0 to 7 from right to left. True if the value is 1, or false otherwise
	print(bit.isset(5,1))-- print false
	print(bit.isset(5,2))-- print true
	print(bit.isset(5,3))-- Return returns false
	
	print(bit.isclear(5,0))-- Contrary to the above
	print(bit.isclear(5,1))
	print(bit.isclear(5,2))
	print(bit.isclear(5,3))
	
	print(bit.set(0,0,1,2,3))-- Set 1 in the appropriate number of digits to print 15
	
    print(bit.clear(5,0,2)) -- Set 0 in the corresponding position to print 0
	
	print(bit.bnot(5))-- Bitwise reverse
	
	print(bit.band(1,1))-- And, - Output 1
	
	print(bit.bor(1,2))--or-, Output 3
	
	print(bit.bxor(1,2))-- XOR, same as 0, different from 1
	
	print(bit.lshift(1,2))-- Logic left, "100", output is 4
	
	print(bit.rshift(4,2))-- Logically right shift, "001", output is 1
	
	print(bit.arshift(2,2))-- Arithmetic shifts to the right, the number added on the left depends on the sign and the output is zero
  
end





--[[function name: packedtest
    Features: Extend the pack pack's feature demos
    Parameters: None
    Return Value: None
    --]]
local function packedtest()
	
	--[[Some variables are wrapped in a string according to the format .'z 'Finite zero string,' p 'longbyte first,' P 'longcharacter first,
	'a' long Phrase first, 'A' string, 'f' float, 'd' double, 'n'Lua number,' c 'character,' b 'unsigned char,' h 'Short,' H 'unsigned short
	'i' plastic, 'I' unsigned plastic, 'l' long, 'L' unsigned long]]
	print("pcak.pack test£º")
	print(common.binstohexs(pack.pack("H",100)))-- When "100" is packed as a string, "0064" is printed
	print(common.binstohexs(pack.pack("h",100)))-- When "100" is packed as a string, it is - "0064" is printed when "100" is packed as an integer, and "0064" is printed.
	print(pack.pack("A","LUAT"))
	print("pack.unpack test:")
	nextpox1,val1,val2,val3,val4=pack.unpack("luat100","c4")-- "nextpos" next position to be resolved
	print(nextpox1,val1,val2,val3,val4)        -- Corresponding to "l", "u", "a", "t" ascii code data
	print(string.char(val1,val2,val3,val4))    -- Ascii code data into character output
	nextpox2,string1=pack.unpack("luat100","A4")-- Output "luat"
	print(nextpox2,string1)
	nextpox3,number1,number2=pack.unpack(common.hexstobins("006400000064"),">H>i")--[[Output unsigned short and plastic because unsigned short is four bytes
	Plastic is 8 bytes, the output is 100,100--]]
	print(nextpox3,number1,number2)
	nextpox3,number1=pack.unpack(common.hexstobins("0064"),">h")-- The output is 100 because the short type is four bytes
    print(nextpox3,number1)
end

--Short for 4 bytes
--    Long integer occupies 8 bytes (64 bits)
--    Double accounted for 8 bytes
--    Long double type accounted for 16 bytes
-- 
--    Data type range
--    Integer [signed] int -2147483648 ~ + 2147483648
--   Unsigned integer unsigned [int] 0 ~ 4294967295
--    Short integer short [int] -32768 ~ 32768
--    Unsigned short unsigned short [int] 0 ~ 65535
--   Long integer Long int -2147483648 ~ +2147483648
--    Unsigned long Unsigned [int] 0 ~ 4294967295
--    Character [signed] char -128 ~ +127
 --   Unsigned char unsigned char 0 ~ 255
--Does not support fractional types 


--function name: stringtest
--    Function: sting library use of several interfaces demo
--    Parameters: None
--    Return Value: None --]]
	
	
local function stringtest()
	print("stringtest:")
	print(string.char(97,98,99))-- Convert the corresponding value to a character
	print(string.byte("abc"),2) -- The first parameter is a string, the second parameter is the location. The function is to convert the given position in the string into a numeric value
	local i=100
	local string1="luat great"
	print(string.format("%04d//%s",i,string1))--[[The character after the indicator control format can be: decimal 'd'; hex 'x'
	Octal 'o'; Float 'f'; String 's', the number of control format is the same with the following parameters. Function: Output parameters in a specific format. --]]
	print(string.gsub("luat is","is","great"))-- The first parameter is the target string, the second parameter is the standard string, the third is to be replaced string
	-- print out "luat great"
end




--Function Name: bitstohexs ()
--   Function: The binary number into hexadecimal, and output the converted hexadecimal digit string, separated by a delimiter between each byte
--   Print a hexadecimal number string
--   Arguments: The first argument is a binary number, the second is a delimiter
--   return value:     
local function binstohexs(binstring,s)
	
	hexs=common.binstohexs(binstring,s) -- The common library in the base library is called
	print(hexs)                  -- Output a hexadecimal digit string	
end 



	

--function name: hexstobits
--  Function: The hexadecimal number is converted to binary number, and stored in the array, the output converted binary
--Parameters: hexadecimal number
--	return value:                           --]]
local function hexstobins(hexstring)-- Convert hexadecimal numbers to binary
	print(common.hexstobins(hexstring)) -- Note that some of the binary is printable and some is not
end







--Function name: ucs2togb2312
--Function: unicode small-end encoding into gb2312 encoding, and print out gd2312 encoded data
--Parameters:
--ucs2s: unicode Small-end encoded data, pay attention to the number of bytes of input parameters
--return value:

local function ucs2togb2312(ucs2s)
	print("ucs2togb2312")	
	local gd2312num=common.ucs2togb2312(ucs2s)-- The call is common.ucs2togb2312, the string returned is encoded
	print("gb2312  code£º"..gd2312num)	
end







--Function name: gb2312toucs2
--Function: gb2312 encoding into unicode hexadecimal small-end encoded data and print
--Parameters:
--gb2312s: gb2312 encoding data, pay attention to the number of bytes of the input parameters
--return value:

local function gb2312toucs2(gd2312num)
	print("gb2312toucs2")
	local ucs2num=common.gb2312toucs2(gd2312num)
	print("unicode little-endian code:"..common.binstohexs(ucs2num))-- To convert binary to hexadecimal, otherwise it can not be output
end 






--Function name: ucs2betogb2312
--Function: unicode large-end encoding into gb2312 encoding and print out gb2312 encoding data,
--Big-end encoded data is swapped with the small-end encoded data
--Parameters:
--ucs2s: unicode big endian encoded data, pay attention to the number of bytes of the input parameters
--return value:

local function ucs2betogb2312(ucs2s)
	print("ucs2betogb2312")
	local gd2312num=common.ucs2betogb2312(ucs2s) -- Converted data directly into characters can be output directly
	print("gd2312 code £º"..gd2312num)	
end



--Function name: gb2312toucs2be
--Function: gb2312 encoding into unicode large-end encoding, and print unicode big-end encoding
--Parameters:
--gb2312s: gb2312 encoding data, pay attention to the number of bytes of the input parameters
--Return value: unicode large-end encoded data

function gb2312toucs2be(gb2312s)
	print("gb2312toucs2be")
    local ucs2benum=common.gb2312toucs2be(gb2312s)
	print("unicode big-endian code :"..common.binstohexs(ucs2benum))
end



--Function name: ucs2toutf8
--Function: unicode small-end encoding into utf8 encoding, and print utf8 hex encoded data
--Parameters:
--ucs2s: unicode Small-end encoded data, pay attention to the number of bytes of input parameters
--return value:

local function ucs2toutf8(usc2)
	print("ucs2toutf8")
	local utf8num=common.ucs2toutf8(usc2)
	print("utf8  code£º"..common.binstohexs(utf8num))
	
end





--Function name: utf8togb2312
--Function: utf8 encoding into gb2312 encoding, and print out gb2312 encoded data
--Parameters:
--utf8s: utf8 encoded data, pay attention to the number of bytes of the input parameters
--return value:

local function utf8togb2312(utf8s)
	print("utf8togb2312")
	local gb2312num=common.utf8togb2312(utf8s)
	print("gd2312 code£º"..gb2312num)
	
end





-- [[Function Call -]]

bittest()
packedtest()
stringtest()






-- [[Test procedures, examples of interfaces, the simulator can be directly tested, with "I" as an example -]]

binstohexs("ab")
hexstobins("3132")

ucs2togb2312(common.hexstobins("1162"))  -- "1162" is the ucs2 encoding of the "me" word, where common.hexstobins is called to convert the argument to binary, which is two bytes.
gb2312toucs2(common.hexstobins("CED2")) -- "CED2" is the gb22312 encoding of "me" 
ucs2betogb2312(common.hexstobins("6211"))-- "6211" is the ucs2be encoding of "me"
gb2312toucs2be(common.hexstobins("CED2"))
ucs2toutf8(common.hexstobins("1162"))
utf8togb2312(common.hexstobins("E68891"))-- "E68891" is utf8 encoding of "me"









