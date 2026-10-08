//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.12.02 (64-bit) 
//Created Time: 2026-10-07 15:01:19
create_clock -name system_clock -period 37.037 -waveform {0 10} [get_ports {clk}]
