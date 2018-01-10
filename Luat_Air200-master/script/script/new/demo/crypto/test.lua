module(...,package.seeall)

require"common"



--Encryption and decryption algorithm results can be controlled
--http://tool.oschina.net/encrypt?type=2
--http://www.ip33.com/crc.html
--http://tool.chacuo.net/cryptaes
--carry out testing


local slen = string.len


--Function name: print
--Function: Print Interface, all prints in this file will be prefixed with aliyuniot
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--Function name: base64test
--Function: base64 encryption and decryption algorithm test
--Parameters: None
--Return Value: None

local function base64test()
	local originstr = "123456crypto.base64_encodemodule(...,package.seeall)sys.timer_start(test,5000)jdklasdjklaskdjklsa"
	local encodestr = crypto.base64_encode(originstr,slen(originstr))
	print("base64_encode",encodestr)
	print("base64_decode",crypto.base64_decode(encodestr,slen(encodestr)))
end


--Function name: hmacmd5test
--Function: hmac_md5 algorithm test
--Parameters: None
--Return Value: None

local function hmacmd5test()
	local originstr = "asdasdsadas"
	local signkey = "123456"
	print("hmac_md5",crypto.hmac_md5(originstr,slen(originstr),signkey,slen(signkey)))
end


--Function name: md5test
--Function: md5 algorithm test
--Parameters: None
--Return Value: None

local function md5test()
	local originstr = "sdfdsfdsfdsffdsfdsfsdfs1234"
	print("md5",crypto.md5(originstr,slen(originstr)))
end


--Function name: hmacsha1test
--Function: hmac_sha1 algorithm test
--Parameters: None
--Return Value: None

local function hmacsha1test()
	local originstr = "asdasdsadasweqcdsjghjvcb"
	local signkey = "12345689012345"
	print("hmac_sha1",crypto.hmac_sha1(originstr,slen(originstr),signkey,slen(signkey)))
end



--Function name
--Function name: sha1test
--Function: sha1 algorithm test
--Parameters: None
--Return Value: None
--: Hmacsha1test
--Function: hmac_sha1 algorithm test
--Parameters: None
--Return Value: None

local function sha1test()
	local originstr = "sdfdsfdsfdsffdsfdsfsdfs1234"
	print("sha1",crypto.sha1(originstr,slen(originstr)))
end


--Function name: crctest
--Function: crc algorithm test
--Parameters: None
--Return Value: None

local function crctest()
	local originstr = "sdfdsfdsfdsffdsfdsfsdfs1234"
	print("crc16_modbus",string.format("%04X",crypto.crc16_modbus(originstr,slen(originstr))))
	print("crc32",string.format("%08X",crypto.crc32(originstr,slen(originstr))))
end


--Function name: aestest
--Function: aes algorithm test
--Parameters: None
--Return Value: None

local function aestest()
	local originstr = "123456crypto.base64_encodemodule(...,package.seeall)sys.timer_start(test,5000)jdklasdjklaskdjklsa"
	-- Encryption mode: ECB, padding: zeropadding, data block: 128 bits
	local encodestr = crypto.aes128_ecb_encrypt(originstr,slen(originstr),"1234567890123456",16)
	print("aes128_ecb_encrypt",common.binstohexs(encodestr))
	print("aes128_ecb_decrypt",crypto.aes128_ecb_decrypt(encodestr,slen(encodestr),"1234567890123456",16))
		
	--cbc not yet supported
	--encodestr = crypto.aes128_cbc_encrypt(originstr,slen(originstr),"1234567890123456",16,"1234567890123456",16)
	--print("aes128_cbc_encrypt",common.binstohexs(encodestr))
	--print("aes128_cbc_decrypt",crypto.aes128_cbc_decrypt(encodestr,slen(encodestr),"1234567890123456",16,"1234567890123456",16))
end


--Function name: test
--Function: Algorithm test entry
--Parameters: None
--Return Value: None

local function test()
	base64test()
	hmacmd5test()
	md5test()
	hmacsha1test()
	sha1test()
	crctest()
	aestest()
end

sys.timer_start(test,5000)
