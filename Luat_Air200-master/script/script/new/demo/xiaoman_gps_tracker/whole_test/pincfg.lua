
--Module Name: GPIO
--Module Features: GPIO Configuration and Operation
--Last modified: 2017.02.16

require"pins"
module(...,package.seeall)

-- Although this pin of GSENSOR supports interrupts, interrupts will wake up the system and increase power consumption
-- So configure the input method to poll this pin state in gsensor.lua
GSENSOR = {pin=pio.P0_3,dir=pio.INPUT,valid=0}
WATCHDOG = {pin=pio.P0_14,init=false,valid=0}
RST_SCMWD = {pin=pio.P0_12,defval=true,valid=1}

pins.reg(GSENSOR,WATCHDOG,RST_SCMWD)

