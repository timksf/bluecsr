package ExamplePeripherals;

import FIFOF  :: *;
import GetPut :: *;
import Vector :: *;

import BlueCSRCore :: *;

interface ExampleUart_ifc;
    interface Put#(Bit#(8)) rx;
    interface Get#(Bit#(8)) tx;

    method Bool rx_ready;    //a received byte waits in RX_DATA
endinterface

module [BlueCSRCtx_t#(32, 32)] uart_counters#(Bool received, Bool transmitted)(Empty);
    csr_regmap_def("UartCounters", "Counts bytes transferred at the UART byte interfaces.");

    csr_reg_def('h00, "RX_COUNT", "Bytes accepted from the receiver.");
    let i_rx_count <- csr_reg_counter_ro('h00, Bit#(32)'(0), 0, received,    "COUNT", "RX byte count", "Increments on each accepted byte.");

    csr_reg_def('h04, "TX_COUNT", "Bytes handed to the transmitter.");
    let i_tx_count <- csr_reg_counter_ro('h04, Bit#(32)'(0), 0, transmitted, "COUNT", "TX byte count", "Increments on each transmitted byte.");
endmodule

module [BlueCSRCtx_t#(32, 32)] uart_registers(ExampleUart_ifc);
    Integer fifo_depth = 4;

    FIFOF#(Bit#(8)) f_rx <- mkSizedFIFOF(fifo_depth);
    FIFOF#(Bit#(8)) f_tx <- mkSizedFIFOF(fifo_depth);

    PulseWire pw_received    <- mkPulseWire;
    PulseWire pw_transmitted <- mkPulseWire;

    csr_regmap_def("Uart", "UART register front end with byte interfaces for a serial PHY.");

    csr_reg_def('h00, "CONTROL", "Controls transfers at the UART byte interfaces.");
    Reg#(Bool) rg_enabled <- csr_reg_rw('h00, True, 0, "ENABLE", "Enable", "Enables the RX and TX byte interfaces.");

    csr_reg_def('h04, "RX_DATA", "Reading this register removes one received byte, if available.");
    csr_reg_fifo_ro_valid('h04, f_rx, "DATA", "Received byte", "Byte at the head of the RX FIFO.", "VALID", "Byte available", "Set when this read returned a byte.");

    csr_reg_def('h08, "TX_DATA", "A low-byte write queues one byte for transmission.");
    csr_reg_fifo_wo('h08, f_tx, "DATA", "Transmit byte", "Enqueues one byte. Writes fail when the TX FIFO is full.");

    function Bit#(32) read_info(Bit#(32) offset);
        case(offset)
            'h0:     return 'h5541_5254;
            'h4:     return 1;
            'h8:     return fromInteger(fifo_depth);
            default: return 0;
        endcase
    endfunction
    csr_region_ro('h80, 'h10, read_info, "IDENT", "Read-only signature, interface version, and FIFO depth in bytes.");
    csr_block('h100, 'h10, "STATS", uart_counters(pw_received, pw_transmitted));

    interface Put rx;
        method Action put(Bit#(8) data) if(rg_enabled);
            f_rx.enq(data);
            pw_received.send;
        endmethod
    endinterface

    interface Get tx;
        method ActionValue#(Bit#(8)) get if(rg_enabled);
            let data = f_tx.first;
            f_tx.deq;
            pw_transmitted.send;
            return data;
        endmethod
    endinterface

    method rx_ready = f_rx.notEmpty;
endmodule

module [BlueCSRCtx_t#(32, 32)] timer_registers(Empty);
    Reg#(Bit#(32)) rg_remaining <- mkReg(0);
    PulseWire      pw_start     <- mkPulseWire;

    csr_regmap_def("Timer", "One-shot countdown timer. Each tick is one SoC clock cycle.");

    csr_reg_def('h00, "RELOAD",      "Number of ticks to load when starting the timer.");
    Reg#(Bit#(32)) rg_reload <- csr_reg_rw('h00, 16, 0, "TICKS", "Reload value", "A value of zero leaves the timer idle.");

    function ActionValue#(BlueCSRResponse_t) start_timer(Bit#(32) data, Bit#(4) strobes);
        actionvalue
            if(strobes[0] == 1 && data[0] == 1) pw_start.send;
            return CSR_OKAY;
        endactionvalue
    endfunction

    function Bool can_start(Bit#(32) data, Bit#(4) strobes) = True;

    csr_reg_def('h04, "COMMAND",     "Starts or restarts the countdown.");
    csr_reg_act_wo('h04, Bit#(1)'(0), 0, can_start, CSR_SLVERR, start_timer, "START", "Start timer", "Write one in the low byte to load RELOAD.");

    Bool expired = rg_remaining == 1 && !pw_start;

    csr_reg_def('h08, "EXPIRATIONS", "Count of completed countdowns.");
    let i_expirations <- csr_reg_counter_ro('h08, Bit#(32)'(0), 0, expired, "COUNT", "Expiration count", "Increments once each time the countdown reaches zero.");

    csr_reg_def('h0c, "IRQ_STATUS",  "Sticky interrupt status. Write one to clear.");
    csr_reg_def('h10, "IRQ_ENABLE",  "Interrupt mask.");
    csr_irq('h0c, 'h10, 0, 0, expired, "TIMEOUT", "Timeout interrupt", "Set when the countdown reaches zero.");

    rule r_countdown (pw_start || rg_remaining != 0);
        rg_remaining <= pw_start ? rg_reload : rg_remaining - 1;
    endrule
endmodule

interface ExampleGpio_ifc;
    method Action pins_in(Bit#(8) pins);    //pin levels, low while not driven
    method Bit#(8) pins_out;
    method Bit#(8) pins_oe;
endinterface

module [BlueCSRCtx_t#(32, 32)] gpio_registers(ExampleGpio_ifc);
    Integer pins = 8;

    Wire#(Bit#(8)) w_pins_in <- mkDWire(0);

    csr_regmap_def("Gpio", "Eight general purpose pins with output enables and rising edge interrupts.");

    csr_reg_def('h00, "OUTPUT",        "Levels driven on the pins whose output is enabled.");
    Reg#(Bit#(8)) rg_output <- csr_reg_rw('h00, 0, 0, "LEVEL", "Output level", "One bit per pin.");

    csr_reg_def('h04, "OUTPUT_ENABLE", "Selects the pins this block drives.");
    Reg#(Bit#(8)) rg_oe     <- csr_reg_rw('h04, 0, 0, "ENABLE", "Output enable", "One bit per pin, set to drive the pin.");

    csr_reg_def('h08, "INPUT",         "Pin levels, sampled every cycle.");
    Reg#(Bit#(8)) rg_input  <- csr_reg_ro('h08, 0, 0, "LEVEL", "Input level", "One bit per pin.");

    csr_reg_def('h0c, "IRQ_STATUS",    "Sticky rising edge status. Write one to clear.");
    csr_reg_def('h10, "IRQ_ENABLE",    "Interrupt mask.");
    for(Integer i = 0; i < pins; i = i + 1)
        csr_irq('h0c, 'h10, i, 0, w_pins_in[i] == 1 && rg_input[i] == 0, "PIN" + integerToString(i), "Pin " + integerToString(i) + " rising edge", "Set when the pin changes from low to high.");

    rule r_sample;
        rg_input <= w_pins_in;
    endrule

    method Action pins_in(Bit#(8) pins_value);
        w_pins_in <= pins_value;
    endmethod

    method pins_out = rg_output;
    method pins_oe  = rg_oe;
endmodule

typedef 4 SysCtrlIrqs;

interface ExampleSysCtrl_ifc;
    method Bool irq;    //interrupt request to the CPU
endinterface

//interrupt sources stay pending in their peripherals, the controller only masks and combines their levels
module [BlueCSRCtx_t#(32, 32)] sysctrl_registers#(Vector#(SysCtrlIrqs, Bool) sources)(ExampleSysCtrl_ifc);
    csr_regmap_def("SysCtrl", "System identification, cycle counter, and interrupt controller.");

    csr_reg_def('h00, "ID",          "SoC identification.");
    Reg#(Bit#(32)) rg_id      <- csr_reg_ro('h00, 'h4253_4f43, 0, "VALUE", "Identification", "Reads as BSOC in ASCII.");

    csr_reg_def('h04, "SCRATCH",     "Free register for software.");
    Reg#(Bit#(32)) rg_scratch <- csr_reg_rw('h04, 0, 0, "VALUE", "Scratch value", "Not used by hardware.");

    csr_reg_def('h08, "CYCLES",      "Clock cycles since reset.");
    let i_cycles <- csr_reg_counter_ro('h08, Bit#(32)'(0), 0, True, "COUNT", "Cycle count", "Increments every cycle and wraps.");

    csr_reg_def('h10, "IRQ_PENDING", "Levels of the interrupt sources, sampled every cycle. Bit 0 is the timer, bit 1 the GPIO, bits 2 and 3 the UART receivers.");
    Reg#(Bit#(SysCtrlIrqs)) rg_pending <- csr_reg_ro('h10, 0, 0, "PENDING", "Pending sources", "One bit per source.");

    csr_reg_def('h14, "IRQ_ENABLE",  "Selects the sources that reach the CPU interrupt.");
    Reg#(Bit#(SysCtrlIrqs)) rg_enable  <- csr_reg_rw('h14, 0, 0, "ENABLE", "Enabled sources", "One bit per source.");

    rule r_sample;
        rg_pending <= pack(sources);
    endrule

    method irq = (pack(sources) & rg_enable) != 0;
endmodule

endpackage
