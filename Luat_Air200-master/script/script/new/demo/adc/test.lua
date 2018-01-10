
--Module Name: ADC test (adc accuracy of 10bit, voltage measurement range of 0 to 1.85V, measurement accuracy of 20MV)
--Module Function: Test ADC function
--Last modified: 2017.07.22


module(...,package.seeall)


--Function name: print
--Function: Print interface, all print in this file will be added test prefix
--Parameters: None
--Return Value: None

local function print(...)
	_G.print("test",...)
end

--adc id
local ADC_ID = 0

local function read()		
	-- Open adc
	adc.open(ADC_ID)
	-- read adc
	--adcval is of type number, indicating the original value of adc, with an invalid value of 0xFFFF
	--voltval is a number of type, which means that the converted voltage is in millivolts, the invalid value is 0xFFFF; the voltval returned by adc.read interface is enlarged by 3 times, so it needs to be divided by 3 and restored to the original voltage
	local adcval,voltval = adc.read(ADC_ID)
	print("adc.read",adcval,voltval/3,voltval)	
	-- if adcval is valid
	if adcval and adcval~=0xFFFF then
	end	
	-- if voltval is valid
	if voltval and voltval~=0xFFFF then
		
	--The voltval returned by the --adc.read interface is zoomed in by a factor of three, so divide by 3 here
		voltval = voltval/3
	end
end

sys.timer_loop_start(read,1000)

