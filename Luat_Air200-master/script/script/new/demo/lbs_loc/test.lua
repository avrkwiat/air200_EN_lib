module(...,package.seeall)
require"lbsloc"
-- Whether to check the GPS location string information

local qryaddr

--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end


--Function name: qrygps
--Function: Query GPS location request
--Parameters: None
--Return Value: None

local function qrygps()
	qryaddr = not qryaddr
	lbsloc.request(getgps,qryaddr)
end


--Function name: getgps
--Function: get the latitude and longitude callback function
--Parameters:
--result: number type, get the result, 0 means success, the rest means failure. When the result is 0, the following five parameters make sense
--1: Repeatedly initiated get request (need to wait until the last call to call the callback before sending)
--2:20 second timeout failed to get (maybe the network is not ready)
--3: The latitude and longitude data returned by the server is in wrong format
--4: Communication with the server failed
--lat: string type, latitude, integer part 3, fractional part 7, for example 031.2425864
--lng: string type, longitude, integer part 3, fractional part 7, for example 121.4736522
--addr: string type, GB2312 encoded string of positions. Calling lbsloc.request longitude and latitude, the second argument is true to return this parameter
--latdm: string type, latitude, degree formatting, integer part 5, fractional part 6, dddmm.mmmmmm, for example 03114.555184
--lngdm: string type, latitude, degree formatting, integer part 5, fractional part 6, dddmm.mmmmmm, for example 12128.419132
--Return Value: None

function getgps(result,lat,lng,addr,latdm,lngdm)
	print("getgps",result,lat,lng,addr,latdm,lngdm)
	-- Get latitude and longitude success
	if result==0 then
	--failure
	else
	end
	sys.timer_start(qrygps,20000)
end


-- After 20 seconds to check the latitude and longitude, the query results returned by the callback function getgps
sys.timer_start(qrygps,20000)
