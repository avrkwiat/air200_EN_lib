require"pins"
module(...,package.seeall)

-- All pins in the open source module that can be used as GPIOs are configured as follows, each configured for demonstration purposes only
-- The user will eventually need to modify their own needs

--pin value is defined as follows:
--pio.P0_XX: for GPIOXX, for example, pio.P0_15, for GPIO15
--pio.P1_XX: for GPOXX, for example, pio.P1_8, for GPO8

--dir value is defined as follows (default is pio.OUTPUT):
--pio.OUTPUT: that output, initialization is output low
--pio.OUTPUT1: that the output, initialization is output high
--pio.INPUT: that input, you need to poll the input level status
--pio.INT: Interrupt, the status of the state changes will be reported when the message into the module intmsg function

--valid value is defined as follows (default value is 1):
--The value of --valid is used in conjunction with the set and get interfaces in pins.lua
--dir for output when used with pins.set interface, if the first argument of pins.set is true then it will output the level indicated by the valid value, 0 means low, 1 means high
--dir input or interrupt, with the get interface to use, if the pin's level and the valid value of the same, get interface returns true; otherwise returns false
--dir is an interrupt, cb interrupt pin callback function, an interrupt occurs, if configured cb, will call cb, if the level of interrupt generated and valid the same value, then cb (true), otherwise cb ( false)

-- equivalent to PIN22 = {pin = pio.P1_8, dir = pio.OUTPUT, valid = 1}
-- Pin 22: GPO8, configured as output, initializes output low; valid = 1, calls pins.set (true, pin22), outputs high, Then output low
PIN22 = {pin=pio.P1_8}

-- 23rd pin: GPO6; configured as output, initialized high output; valid = 0, calls pins.set (true, pin23), outputs low, Then output high
PIN23 = {pin=pio.P1_6,dir=pio.OUTPUT1,valid=0}

-- The three configurations below have the same meaning as PIN22
PIN25 = {pin=pio.P0_14}
PIN26 = {pin=pio.P0_3}
PIN27 = {pin=pio.P0_1}


local function pin5cb(v)
	print("pin5cb",v)
end

-- 5th pin: GPIO6; configured as interrupt; valid = 1
-- intcb interrupt handler interrupt handler, interrupt generated, if high, the callback intcb (true); if it is low, the callback intcb (false)
-- true if it is high when get (PIN5) is invoked; false if it is low
PIN5 = {name="PIN5",pin=pio.P0_6,dir=pio.INT,valid=1,intcb=pin5cb}

-- Similar to PIN22
--PIN6 = {pin=pio.P0_15}


-- 20th pin: GPIO13; configured as input; valid = 0
-- returns false if get (PIN20) is high if it is invoked, true if it is low
PIN20 = {pin=pio.P0_13,dir=pio.INPUT,valid=0}

-- The three configurations below have the same meaning as PIN22
PIN21 = {pin=pio.P0_8}
PIN16 = {pin=pio.P0_24}
PIN17 = {pin=pio.P0_25}

pins.reg(PIN22,PIN23,PIN25,PIN26,PIN27,PIN5,--[[PIN6,]]PIN20,PIN21,PIN16,PIN17)
