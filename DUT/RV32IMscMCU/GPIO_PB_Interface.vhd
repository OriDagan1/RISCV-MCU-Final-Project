---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_PB - memory mapped peripheral WITH interrupt capability, KEY3..KEY1
--
-- Mapping : byte address 0x2014, reads KEY3..KEY1
-- Ref     : Figure 6   - "Pushbuttons hardware connection and debouncing"
--           Clause 6.i - "support an array of three pushbuttons as an input device"
--
-- This module does two independent jobs, and only these two:
--
--   1. Memory mapped input. A load (cs_i='1' & MemRead_ctrl_i='1') zero extends the current
--      state of the three keys onto data_rd_o, exactly the way PORT_SW reports the switches.
--      A store to 0x2014 has no effect - there is no register the CPU can write here, so
--      MemWrite_ctrl_i and data_wr_i are not brought into this module at all.
--
--   2. Interrupt events. One single-cycle pulse per key, raised on the 0 -> 1 transition of
--      that key and on nothing else. The pulses are produced unconditionally: they carry no
--      reference to cs_i or MemRead_ctrl_i, because a key event is an event whether or not
--      the CPU happens to be reading the port at that instant. These three lines are the IS
--      inputs of the interrupt controller of clause 6.v. IE, IFG, TYPE, the priority
--      encoder, INTR and INTA all live there and none of them appears here - the vector
--      table of clause 6.v gives each key its own flag and its own TYPE value (KEY1 -> 14h,
--      KEY2 -> 18h, KEY3 -> 1Ch), which is why the three requests leave this port separately
--      rather than as one shared line.
--
-- Polarity, and why the interrupt is on RELEASE:
-- Figure 6 draws the board wiring: the keys pull the line to ground through the 74HC245 and
-- resistors hold it at VCC3P3 otherwise, so the pushbuttons are active low. The waveform in
-- the same figure labels the two transitions - "Pushbutton depressed" is 1 -> 0 and
-- "Pushbutton released" is 0 -> 1. The preparation lecture fixes the event this design
-- reacts to as the rising one only, deliberately, to keep the event definition simple: there
-- is no edge-select register in this port and no configuration bit. The consequence is worth
-- stating plainly, because it is visible on the board - the interrupt fires when the button
-- is LET GO, not when it is pushed. Holding a key down produces nothing until it is released.
--
-- Debouncing: NONE is done here, on purpose. Figure 6 shows the bounce being removed by the
-- Schmitt trigger on the board itself - the figure's two traces are "Before Debouncing" and
-- "Schmitt Trigger Debounced" - and clause 4 calls them "four debounced pushbuttons". By the
-- time KEY reaches the FPGA pin it is already a clean single transition, so a debouncer in
-- VHDL would be dead logic sitting on an input that has nothing left to filter.
--
-- What IS done here is a two flop synchronizer, and it is not debouncing. This is an
-- implementation decision of this design; the project definition does not ask for it. The
-- reasoning: KEY is asynchronous to MCLK, and unlike PORT_SW - where the switch value only
-- feeds the read multiplexer and is sampled by exactly one flop, the register file write
-- port - the value here is captured into flops of this module and a control decision is
-- taken from it. A transition raises a request that will set a flag in the interrupt
-- controller and divert the program counter. A metastable sample on that path can fabricate
-- an interrupt that never happened or swallow one that did, so KEY is resynchronized into
-- the MCLK domain before the edge detector looks at it.
--
--=============================================================================================
-- Where the edge is detected, and what this obliges the interrupt controller to do
--=============================================================================================
-- Clause 6.v draws the flag of a single source as a D flip flop with D tied to "1", an
-- asynchronous clr_irq, and IS wired to its CLOCK input. Read literally, that means the
-- peripheral hands out a LEVEL and the controller catches the edge by being clocked on it.
-- This module does the opposite: it detects the edge itself and hands out a one cycle pulse.
--
-- The two are equivalent as seen from software - a flag that sets on key release and stays
-- set until cleared by software (note d of clause 6.v) - but they are not equivalent as
-- hardware, and the pulse was chosen deliberately:
--
--   * A flop clocked by IS turns three external pins into three clock domains. Quartus
--     infers them as clocks, TimeQuest cannot constrain them, and their asynchronous clear
--     is released asynchronously. In a project that is graded on its PPA and timing report,
--     that is a set of unconstrained paths that has to be explained away.
--   * The rest of this design already takes the synchronous route wherever a signal crosses
--     domains - DIV_ACCEL uses CDC_SYNC rather than flops clocked by a handshake line.
--
-- The obligation this places on the interrupt controller, which is NOT yet written:
--
--   * IFG must be a flop with an ENABLE driven by this pulse, not a flop clocked by it.
--     A flop clocked by keyN_irq_o would work in simulation and create a gated clock in
--     synthesis, which is the very thing this arrangement exists to avoid.
--   * The enable path must not be gated by the CPU stall. MCLK keeps running while the
--     division accelerator holds the PC, this module keeps sampling, and a key released
--     during a stall must still be recorded.
--   * Set must win over software clear if both land in the same cycle, otherwise a release
--     that coincides with an ISR writing IFG is lost. The literal drawing has the same race
--     between its IS clock edge and clr_irq; it is not a new problem, but it does have to be
--     decided explicitly rather than left to whichever branch of an if-statement comes last.
--
-- Note on the clock edge, because it matters for the above. The synchronizer and the edge
-- detector below run on the RISING edge of MCLK, unlike PORT_LEDR and the HEX pairs, which
-- capture on the falling edge to line up with the DTCM so that every target of a store
-- latches write data at the same instant. Nothing here is a store target, so that
-- constraint does not apply. IFG, however, IS a store target - software clears it - so it
-- will most likely be a falling edge register like the other bus written registers. A pulse
-- raised on a rising edge is high for one full MCLK period, so the falling edge sits in the
-- MIDDLE of it and samples it cleanly. Had this pulse been generated on the falling edge
-- instead, that sampling point would fall exactly on the transition. Do not "make it
-- consistent" with the other ports later without redoing this analysis.
--=============================================================================================
--
-- Reset: all three registers reset to '1', not to '0'. '1' is the idle level of an
-- unpressed active low key, so the state the module comes out of reset believing is the
-- state the pins are actually in. Resetting them to '0' would make the very first sample
-- after reset look like a 0 -> 1 transition on all three keys at once and fire three
-- spurious interrupts before the application has executed a single instruction. rst_i is
-- active high and must be driven from MCU.vhd's rst_w, which already resolves the polarity
-- of KEY0 (rst_w <= rst_i WHEN MODELSIM = 1 ELSE NOT rst_i), never from the raw board pin.
--
-- Bus interface: this module drives data_rd_o and nothing else. It presents zeros rather
-- than 'Z' when it is not selected, which is what every other port in this design does. The
-- tri-state buffer of Figure 5 is NOT inside the port - it lives in MCU.vhd, where one
-- BidirPin per device drives the shared io_bus_w from that device's data_rd_o under its own
-- output enable, and a further BidirPin parks the bus at zero when no device is driving.
-- Driving zeros here is therefore belt and braces rather than the mechanism: it keeps this
-- module's output defined for a testbench that instantiates it standalone, and it keeps the
-- behaviour unchanged after Quartus collapses the tri-state bus into a multiplexer, which
-- it must, because Cyclone V has no internal tri-state.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY GPIO_PB_Interface IS
	generic(
		DATA_BUS_WIDTH		: integer := 32
	);
	PORT(
		--Inputs
		clk_i				: IN	STD_LOGIC;
		rst_i				: IN	STD_LOGIC;
		cs_i				: IN	STD_LOGIC;	-- chip select, from the GPIO address decoder
		MemRead_ctrl_i		: IN	STD_LOGIC;
		KEY_i				: IN	STD_LOGIC_VECTOR(3 DOWNTO 1);	-- KEY3..KEY1, active low, debounced on board

		--Outputs
		data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Interrupt requests, one per key. Single cycle pulses, the IS inputs of clause 6.v
		key1_irq_o			: OUT	STD_LOGIC;
		key2_irq_o			: OUT	STD_LOGIC;
		key3_irq_o			: OUT	STD_LOGIC
	);
END GPIO_PB_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF GPIO_PB_Interface IS

	-- KEY3..KEY1. The index is the key number, so KEY_i(2) is KEY2 and needs no translation
	-- table. KEY0 is absent from this port by design - it is the system reset (clause 6.v
	-- lists RESET as the non maskable source with TYPE 00h) and never reaches the data bus.
	CONSTANT PB_MSB			: integer := 3;
	CONSTANT PB_LSB			: integer := 1;

	-- How many keys this port carries, i.e. how many bits of the read data they occupy.
	-- The bus layout is NOT the pin layout: the keys are numbered 3..1 on the pins but
	-- occupy bits 2..0 of PORT_PB, so the read path below needs a width rather than a
	-- reuse of PB_MSB/PB_LSB. See the note on the read path for the specification.
	CONSTANT PB_COUNT		: integer := PB_MSB - PB_LSB + 1;

	-- The level an unpressed active low key sits at, held there by the pull ups of Figure 6.
	CONSTANT KEY_IDLE		: STD_LOGIC_VECTOR(PB_MSB DOWNTO PB_LSB) := (OTHERS => '1');

	SIGNAL key_meta_q		: STD_LOGIC_VECTOR(PB_MSB DOWNTO PB_LSB);	-- CDC stage 1, may go metastable
	SIGNAL key_sync_q		: STD_LOGIC_VECTOR(PB_MSB DOWNTO PB_LSB);	-- CDC stage 2, safe in the MCLK domain
	SIGNAL key_prev_q		: STD_LOGIC_VECTOR(PB_MSB DOWNTO PB_LSB);	-- key_sync_q delayed by one cycle
	SIGNAL key_irq_w		: STD_LOGIC_VECTOR(PB_MSB DOWNTO PB_LSB);

	SIGNAL rdata_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Input synchronizer and edge history
	--=======================================
	-- Three flops per key in one chain: two of them are the CDC synchronizer, the third
	-- holds the previous synchronized value so the edge detector below has something to
	-- compare against. Only key_sync_q and key_prev_q are ever read - key_meta_q exists
	-- solely to absorb metastability and must not fan out anywhere else.
	SYNCHRONIZER:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			key_meta_q	<= KEY_IDLE;
			key_sync_q	<= KEY_IDLE;
			key_prev_q	<= KEY_IDLE;
		elsif rising_edge(clk_i) then
			key_meta_q	<= KEY_i;
			key_sync_q	<= key_meta_q;
			key_prev_q	<= key_sync_q;
		end if;
	end process;

	--=======================================
	-- Rising edge detector : one pulse per key release
	--=======================================
	-- irq = current AND NOT previous, so the pulse appears in the single cycle in which the
	-- synchronized key is '1' and had been '0' the cycle before. A 1 -> 0 transition (the
	-- press) gives current='0' and produces nothing; a key held down or held up gives
	-- current = previous and produces nothing. Coming out of reset both registers already
	-- hold KEY_IDLE, so no pulse is generated until a key is actually pressed and released.
	key_irq_w	<= key_sync_q AND (NOT key_prev_q);

	key1_irq_o	<= key_irq_w(1);
	key2_irq_o	<= key_irq_w(2);
	key3_irq_o	<= key_irq_w(3);

	--=======================================
	-- Read path : device -> CPU
	--=======================================
	-- KEY1 -> bit 0, KEY2 -> bit 1, KEY3 -> bit 2. Bits 31:3 read as zero. KEY0 has no bit
	-- at all: it is the system RESET of clause 3 and is not part of this device.
	--
	-- THIS LAYOUT IS SPECIFIED, not chosen. The course forum settles it: "the assignment
	-- follows the order KEY1-KEY3 into bits 0-2 respectively. KEY0 is not included, since
	-- it is the interface for the system RESET operation." An earlier version of this file
	-- put KEY3..KEY1 in bits 3..1 with bit 0 reading zero, on the reasoning that aligning
	-- the bit index with the key number was the least surprising arrangement in the absence
	-- of a specification. There is a specification now, and it says otherwise.
	--
	-- NOT TO BE CONFUSED WITH THE IFG BIT POSITIONS, which are a different register with a
	-- different layout and are NOT affected by the above. The interrupt controller places
	-- KEY1IFG at bit 3, KEY2IFG at bit 4 and KEY3IFG at bit 5, from the IE/IFG register map
	-- on page 14 - see INT_CTRL.vhd, and the lecturer's own io_map.s, which defines
	-- KEY3IE_KEY2IE_KEY1IE as 0x38 and KEY1IFG_MASK as 0xFFF7. The two layouts genuinely
	-- differ; making one match the other would break the applications. Nothing links them
	-- in hardware either: the interrupt requests leave this module on their own dedicated
	-- lines and never travel through these bits.
	--
	-- The keys are reported in pin polarity, unmodified: '1' is released and '0' is pressed.
	-- Nothing is inverted here, which keeps the bit a program reads identical to the signal
	-- whose 0 -> 1 transition raised the matching interrupt request above.
	--
	-- The synchronized value is what reaches the bus, not the raw pin. It costs nothing -
	-- the flops exist for the interrupt path anyway - and it means the CPU and the edge
	-- detector always see one and the same view of the keys.
	-- key_sync_q is indexed 3 downto 1 and the slice is 2 downto 0, so this assignment maps
	-- by position: key_sync_q(3)=KEY3 -> bit 2, key_sync_q(2)=KEY2 -> bit 1,
	-- key_sync_q(1)=KEY1 -> bit 0, which is the order the forum specifies.
	rdata_w(DATA_BUS_WIDTH-1 DOWNTO PB_COUNT)	<= (OTHERS => '0');
	rdata_w(PB_COUNT-1 DOWNTO 0)				<= key_sync_q;

	-- The device answers only when the address on the bus is its own and the access is a
	-- load; a store to 0x2014 is silently ignored. MCU.vhd gates this same condition again
	-- on the enable of this port's BidirPin, so the bus is driven by exactly one device.
	data_rd_o	<= rdata_w WHEN (cs_i = '1' AND MemRead_ctrl_i = '1') ELSE (OTHERS => '0');

END rtl;