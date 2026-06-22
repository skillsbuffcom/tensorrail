* =============================================================================
* TensorRail-Mini — 3.3V LDO Power Supply Simulation
* Target: AMS1117-3.3 on ECP5 carrier board
*
* Models:
*   - AMS1117-3.3 behavioural LDO (LAPLACE error amplifier — requires ngspice 40+)
*   - USB 5V input with line ripple
*   - Full output decoupling network (bulk tantalum + per-rail ceramics)
*   - ECP5 85F + dual PSRAM static load (250mA)
*   - Dynamic load step: systolic array computation burst (+150mA for 5ms)
*     mirrors the led[1]=busy assertion in top.v
*   - led[0] power-on indicator LED circuit (330O, D2 on carrier)
*
* Tool: ngspice 40+  (LAPLACE { } in controlled sources requires ngspice >= 40)
* Run:  ngspice -b ldo_power_supply.sp
* =============================================================================

.title TensorRail-Mini LDO + Decoupling

* USB 5V input
* 100mO cable/connector resistance; PULSE models USB host enumeration glitch
Vusb    vbus  0  DC 5.0  PULSE(4.75 5.25 0 500u 500u 8m 20m)
Rsrc    vbus  vin  0.1

* Input bypass (100uF electrolytic bulk + 100nF ceramic near LDO VIN pin)
Cin1    vin   0   100u  IC=5.0
Cin2    vin   0   100n

* AMS1117-3.3 behavioural model
* Error amplifier: Adc=1000, dominant pole at 1 kHz (wp = 2pi*1000 = 6283 rad/s)
* LAPLACE { expr } { H(s) } requires ngspice 40+
Eref   vref   0  VALUE { 1.25 }

* Output voltage divider feedback (sets Vout = Vref*(1 + R1/R2) = 3.3V)
Rfb1   vout   vfb  560
Rfb2   vfb    0    240

* Error amplifier with single dominant pole
Eamp   veamp  0  LAPLACE { V(vref) - V(vfb) } { 1000 / (1 + s/6283.2) }

* Pass element (models NPN Darlington in AMS1117)
Gpass  vin    vout  VALUE { MAX(0, V(veamp) * 0.5) }

* Quiescent current path (~5mA IQ at no load)
Rq     vin    vout  1k

* Output decoupling network
* AMS1117 stability requires >=10uF at output
* Board layout (per carrier Gerbers): tantalum bulk + 6x100nF ceramics
Cout_bulk   vout  0  10u   IC=3.3
Cout_fpga1  vout  0  100n
Cout_fpga2  vout  0  100n
Cout_fpga3  vout  0  100n
Cout_fpga4  vout  0  100n
Cout_psram0 vout  0  100n
Cout_psram1 vout  0  100n

* Static load
* ECP5 85F: ~180mA, 2x PSRAM: ~36mA, CP2102N: ~10mA, 4 LEDs: ~20mA
* Total ~246mA -> 13.4 ohm
Rload_static  vout  0  13.4

* Dynamic load: systolic array burst
* When led[1] (busy) asserts in top.v, 4x4 MAC array switches
* Models +150mA burst at t=5ms for 5ms (one tile computation at 48MHz)
Iload_burst   vout  0  PULSE(0 0.15 5m 50u 50u 5m 20m)

* led[0] power-on indicator (D2 on carrier board)
* FPGA GPIO -> 330 ohm -> green LED -> GND
* Vf ~2.1V, If = (3.3 - 2.1) / 330 ~3.6mA
Vledio   vled_drv  0  DC 3.3
Rled     vled_drv  vled_a  330
Dled     vled_a    0  LED_GREEN
.model LED_GREEN D (Is=2.52e-9 Rs=0.6 N=1.8 Cjo=4p Vj=0.75 BV=5)

* Transient: 30ms captures USB enumeration glitch (t=0) and
* systolic array burst (t=5ms). 10us step = good waveform resolution.
.tran 10u 30m UIC

.options ABSTOL=1e-9 RELTOL=0.001 VNTOL=1e-6
.options method=gear ITL4=150

.end
