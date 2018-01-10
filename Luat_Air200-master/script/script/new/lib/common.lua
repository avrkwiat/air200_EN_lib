
--Module Name: Common Library Functions
--Module features: encoding format conversion, time zone time conversion
--Module last modified: 2017.02.20


-- Define module, import dependent libraries
module(...,package.seeall)

-- Load common global functions to local

local tinsert,ssub,sbyte,schar,sformat,slen = table.insert,string.sub,string.byte,string.char,string.format,string.len


--Function name: ucs2toascii
--Function: ascii string unicode encoded hexadecimal string into ascii string, for example "0031003200330034" -> "1234"
--Parameters:
--inum: String to be converted
--Return Value: The converted string

function ucs2toascii(inum)
	local tonum = {}
	for i=1,slen(inum),4 do
		tinsert(tonum,tonumber(ssub(inum,i,i+3),16)%256)
	end

	return schar(unpack(tonum))
end

--Function name: nstrToUcs2Hex
--Function: ascii string is converted into a unicode encoded hexadecimal string of ascii strings that supports only numbers and +, such as "+1234" -> "002B0031003200330034"
--Parameters:
--inum: String to be converted
--Return Value: The converted string

function nstrToUcs2Hex(inum)
	local hexs = ""
	local elem = ""

	for i=1,slen(inum) do
		elem = ssub(inum,i,i)
		if elem == "+" then
			hexs = hexs .. "002B"
		else
			hexs = hexs .. "003" .. elem
		end
	end

	return hexs
end


--Function name: numtobcdnum
--Function: The number ASCII string is converted to the BCD encoding format string, only numbers and + are supported. For example, "+8618126324567" -> 91688121364265f7 means that the first byte is 0x91, the second byte is 0x68, .... ..)
--Parameters:
--num: string to be converted
--Return Value: The converted string

function numtobcdnum(num)
  local len, numfix,convnum = slen(num),"81",""
  
  if ssub(num, 1,1) == "+" then
    numfix = "91"
    len = len-1
    num = ssub(num, 2,-1)
  end

  if len%2 ~= 0 then --Odd digits

    for i=1, len/2  do
      convnum = convnum .. ssub(num, i*2,i*2) .. ssub(num, i*2-1,i*2-1)
    end
    convnum = convnum .. "F" .. ssub(num,len, len)
  else -- Even digit

    for i=1, len/2  do
      convnum = convnum .. ssub(num, i*2,i*2) .. ssub(num, i*2-1,i*2-1)
    end
  end
  
  return numfix .. convnum
end

--Function name: bcdnumtonum
--Function: The BCD encoding format string is converted to a number ASCII string that supports only numbers and +, such as 91688121364265f7 (meaning the first byte is 0x91, the second byte is 0x68, ...) -> +8618126324567 "
--Parameters:
--num: string to be converted
--Return Value: The converted string

function bcdnumtonum(num)
  local len, numfix,convnum = slen(num),"",""
  
  if len%2 ~= 0 then
    print("your bcdnum is err " .. num)
    return
  end
  
  if ssub(num, 1,2) == "91" then
    numfix = "+"
  end
  
  len,num = len-2,ssub(num, 3,-1)
  
  for i=1, len/2  do
    convnum = convnum .. ssub(num, i*2,i*2) .. ssub(num, i*2-1,i*2-1)
  end
    
  if ssub(convnum,len,len) == "f"  or ssub(convnum,len,len) == "F" then
    convnum = ssub(convnum, 1,-2)
  end
  
  return numfix .. convnum
end

--Function name: binstohexs
--Function: The binary data is converted into a hexadecimal string format, for example 91688121364265f7 (indicating that the first byte is 0x91 and the second byte is 0x68, ...) -> "91688121364265f7"
--Parameters:
--bins: binary data
--s: after the conversion, every two bytes delimiter, there is no default delimiter
--Return Value: The converted string

function binstohexs(bins,s)
	local hexs = "" 

	if bins == nil or type(bins) ~= "string" then return nil,"nil input string" end

	for i=1,slen(bins) do
		hexs = hexs .. sformat("%02X",sbyte(bins,i)) ..(s==nil and "" or s)
	end
	hexs = string.upper(hexs)
	return hexs
end

--Function name: hexstobins
--Function: The hexadecimal string is converted into binary data format, for example "91688121364265f7" -> 91688121364265f7 (indicating that the first byte is 0x91 and the second byte is 0x68, ...)
--Parameters:
--hexs: hexadecimal string
--Return Value: The converted data

function hexstobins(hexs)
	local tbins = {}
	local num

	if hexs == nil or type(hexs) ~= "string" then return nil,"nil input string" end

	for i=1,slen(hexs),2 do
		num = tonumber(ssub(hexs,i,i+1),16)
		if num == nil then
			return nil,"error num index:" .. i .. ssub(hexs,i,i+1)
		end
		tinsert(tbins,num)
	end

	return schar(unpack(tbins))
end

--Function name: ucs2togb2312
--Function: unicode small end encoding into gb2312 encoding
--Parameters:
--ucs2s: unicode Small-end encoded data
--Return Value: gb2312 encoded data

function ucs2togb2312(ucs2s)
	local cd = iconv.open("gb2312","ucs2")
	return cd:iconv(ucs2s)
end

--Function name: gb2312toucs2
--Function: gb2312 encoding into unicode small-end encoding
--Parameters:
--gb2312s: gb2312 encoding data
--Return values: unicode small-end encoded data

function gb2312toucs2(gb2312s)
	local cd = iconv.open("ucs2","gb2312")
	return cd:iconv(gb2312s)
end

--Function name: ucs2betogb2312
--Function: unicode big end code into gb2312 encoding
--Parameters:
--ucs2s: unicode big endian encoded data
--Return Value: gb2312 encoded data

function ucs2betogb2312(ucs2s)
	local cd = iconv.open("gb2312","ucs2be")
	return cd:iconv(ucs2s)
end

--Function name: gb2312toucs2be
--Function: gb2312 encoding into unicode big endian encoding
--Parameters:
--gb2312s: gb2312 encoding data
--Return value: unicode large-end encoded data

function gb2312toucs2be(gb2312s)
	local cd = iconv.open("ucs2be","gb2312")
	return cd:iconv(gb2312s)
end

--Function name: ucs2toutf8
--Function: unicode small-end encoding into utf8 encoding
--Parameters:
--ucs2s: unicode Small-end encoded data
--Return value: utf8 code data

function ucs2toutf8(ucs2s)
	local cd = iconv.open("utf8","ucs2")
	return cd:iconv(ucs2s)
end

--Function name: utf8toucs2
--Function: utf8 encoding into unicode small-end encoding
--Parameters:
--utf8s: utf8 encoded data
--Return values: unicode small-end encoded data

function utf8toucs2(utf8s)
	local cd = iconv.open("ucs2","utf8")
	return cd:iconv(utf8s)
end

--Function name: ucs2betoutf8
--Function: unicode large-end encoding into utf8 encoding
--Parameters:
--ucs2s: unicode big endian encoded data
--Return Value: utf8 encoded data

function ucs2betoutf8(ucs2s)
	local cd = iconv.open("utf8","ucs2be")
	return cd:iconv(ucs2s)
end

--Function name: utf8toucs2be
--Function: utf8 encoding into unicode big end encoding
--Parameters:
--utf8s: utf8 encoded data
--Return value: unicode large-end encoded data

function utf8toucs2be(utf8s)
	local cd = iconv.open("ucs2be","utf8")
	return cd:iconv(utf8s)
end

--Function name: utf8togb2312
--Function: utf8 encoding into gb2312 encoding
--Parameters:
--utf8s: utf8 encoded data
--Return Value: gb2312 encoded data

function utf8togb2312(utf8s)
	local cd = iconv.open("ucs2","utf8")
	local ucs2s = cd:iconv(utf8s)
	cd = iconv.open("gb2312","ucs2")
	return cd:iconv(ucs2s)
end

--Function name: gb2312toutf8
--Function: gb2312 encoding into utf8 encoding
--Parameters:
--gb2312s: gb2312 encoding data
--Return Value: utf8 encoded data

function gb2312toutf8(gb2312s)
	local cd = iconv.open("ucs2","gb2312")
	local ucs2s = cd:iconv(gb2312s)
	cd = iconv.open("utf8","ucs2")
	return cd:iconv(ucs2s)
end

local function timeAddzone(y,m,d,hh,mm,ss,zone)

	if not y or not m or not d or not hh or not mm or not ss then
		return
	end

	hh = hh + zone
	if hh >= 24 then
		hh = hh - 24
		d = d + 1
		if m == 4 or m == 6 or m == 9 or m == 11 then
			if d > 30 then
				d = 1
				m = m + 1
			end
			elseif m == 1 or m == 3 or m == 5 or m == 7 or m == 8 or m == 10 then
			if d > 31 then
				d = 1
				m = m + 1
			end
			elseif m == 12 then
			if d > 31 then
				d = 1
				m = 1
				y = y + 1
			end
		elseif m == 2 then
			if (((y+2000)%400) == 0) or (((y+2000)%4 == 0) and ((y+2000)%100 ~=0)) then
				if d > 29 then
					d = 1
					m = 3
				end
			else
				if d > 28 then
					d = 1
					m = 3
				end
			end
		end
	end
	local t = {}
	t.year,t.month,t.day,t.hour,t.min,t.sec = y,m,d,hh,mm,ss
	return t
end
local function timeRmozone(y,m,d,hh,mm,ss,zone)
	if not y or not m or not d or not hh or not mm or not ss then
		return
	end
	hh = hh + zone
	if hh < 0 then
		hh = hh + 24
		d = d - 1
		if m == 2 or m == 4 or m == 6 or m == 8 or m == 9 or m == 11 then
			if d < 1 then
				d = 31
				m = m -1
			end
		elseif m == 5 or m == 7  or m == 10 or m == 12 then
			if d < 1 then
				d = 30
				m = m -1
			end
		elseif m == 1 then
			if d < 1 then
				d = 31
				m = 12
				y = y -1
			end
		elseif m == 3 then
			if (((y+2000)%400) == 0) or (((y+2000)%4 == 0) and ((y+2000)%100 ~=0)) then
				if d < 1 then
					d = 29
					m = 2
				end
			else
				if d < 1 then
					d = 28
					m = 2
				end
			end
		end
	end
	local t = {}
	t.year,t.month,t.day,t.hour,t.min,t.sec = y,m,d,hh,mm,ss
	return t
end


--Function name: transftimezone
--Function: The time of the current time zone is converted to the time of the new time zone
--Parameters:
--y: current time zone year
--m: current time zone month
--d: the current time zone day
--hh: current time zone hours
--mm: current distinction
--ss: current time zone seconds
--pretimezone: current time zone
--nowtimezone: new time zone
--Return Value: Returns the time corresponding to the new time zone, table format {year, month.day, hour, min, sec}

function transftimezone(y,m,d,hh,mm,ss,pretimezone,nowtimezone)
	local t = {}
	local zone = nil
	zone = nowtimezone - pretimezone

	if zone >= 0 and zone < 23 then
		t = timeAddzone(y,m,d,hh,mm,ss,zone)
	elseif zone < 0 and zone >= -24 then
		t = timeRmozone(y,m,d,hh,mm,ss,zone)
	end
	return t
end

