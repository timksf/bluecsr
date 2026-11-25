package BlueCSRSoCExample;

import Connectable :: *;
import GetPut      :: *;
import StmtFSM     :: *;

import Ahb                :: *;
import AhbMaster          :: *;
import ExamplePeripherals :: *;
import ExampleSoC         :: *;

module [Module] mkBlueCSRSoCExample(Empty);
    ExampleSoC_ifc         i_soc    <- mkBlueCSRSoC;
    AhbMaster_ifc#(32, 32) i_master <- mkAhbMaster(2);
    mkConnection(i_master.fabric, i_soc.ahb);

    Bit#(32) rom_base     = 'h0000_0000;
    Bit#(32) sysctrl_base = 'h1000_0000;
    Bit#(32) sram_base    = 'h2000_0000;
    Bit#(32) uart0_base   = 'h4000_1000;
    Bit#(32) uart1_base   = 'h4000_2000;
    Bit#(32) timer_base   = 'h4000_3000;
    Bit#(32) gpio_base    = 'h4000_4000;

    let protection = ahb_protection(AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE);

    function Stmt access(Bit#(32) address, Bool write, Bit#(32) data, AhbSize_t size, Bool expect_error);
        return seq
            i_master.request.put(ahb_single_request(AhbRequest_t {
                address   : address,
                write     : write,
                write_data: write ? data : 0,
                size      : size,
                protection: protection,
                lock      : False
            }));
            action
                let response <- i_master.response.get;
                if(response.slave_error != expect_error || (!write && !expect_error && response.read_data != data))
                    $fatal(1, "AHB access at %h returned %h, error %b; expected %h, error %b",
                        address, response.read_data, response.slave_error, data, expect_error);
            endaction
        endseq;
    endfunction

    function Stmt read_word(Bit#(32) address, Bit#(32) expected);
        return access(address, False, expected, AHB_WORD, False);
    endfunction

    function Stmt write_word(Bit#(32) address, Bit#(32) data);
        return access(address, True, data, AHB_WORD, False);
    endfunction

    function Stmt exercise_uart(ExampleUart_ifc i_uart, Bit#(32) base, Bit#(8) rx, Bit#(8) tx);
        return seq
            i_uart.rx.put(rx);
            read_word(base + 'h04, zeroExtend(rx) | 'h100);
            read_word(base + 'h04, 0);
            access(base + 'h08, True, zeroExtend(tx), AHB_BYTE, False);
            action
                let byte_out <- i_uart.tx.get;
                if(byte_out != tx) $fatal(1, "Unexpected byte from UART at %h: %h", base, byte_out);
            endaction
            read_word(base + 'h100, 1);
            read_word(base + 'h104, 1);
        endseq;
    endfunction

    function Stmt check(Bool condition, String message);
        return seq
            action
                if(!condition) $fatal(1, message);
            endaction
        endseq;
    endfunction

    Reg#(UInt#(12)) rg_cycles <- mkReg(0);
    Reg#(Bit#(8))   rg_pins   <- mkReg(0);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 4095) $fatal(1, "Timed out running the SoC example");
    endrule

    rule r_drive_pins;
        i_soc.peripherals.gpio.pins_in(rg_pins);
    endrule

    mkAutoFSM(seq
        //AHB memories
        read_word(rom_base, 'h2000_1000);
        read_word(rom_base + 'h04, 'h0000_0101);
        access(rom_base, True, 0, AHB_WORD, True);
        write_word(sram_base, 'h1234_5678);
        access(sram_base + 'h01, True, 'h0000_ab00, AHB_BYTE, False);
        access(sram_base + 'h02, True, 'hcdef_0000, AHB_HALFWORD, False);
        read_word(sram_base, 'hcdef_ab78);
        write_word(sram_base + 'hffc, 'h0bad_cafe);
        read_word(sram_base + 'hffc, 'h0bad_cafe);

        //system controller behind the AHB adapter
        read_word(sysctrl_base + 'h00, 'h4253_4f43);
        write_word(sysctrl_base + 'h04, 'hdead_beef);
        read_word(sysctrl_base + 'h04, 'hdead_beef);
        write_word(sysctrl_base + 'h14, 'b0011);
        read_word(sysctrl_base + 'h10, 0);

        read_word(uart0_base + 'h00, 1);
        read_word(uart0_base + 'h80, 'h5541_5254);
        read_word(uart0_base + 'h88, 4);
        exercise_uart(i_soc.peripherals.uart0, uart0_base, 'h41, 'h42);
        read_word(uart1_base + 'h100, 0);
        exercise_uart(i_soc.peripherals.uart1, uart1_base, 'h61, 'h62);

        //a waiting byte is pending at the controller but masked
        i_soc.peripherals.uart1.rx.put('h55);
        read_word(sysctrl_base + 'h10, 'b1000);
        check(!i_soc.irq, "Masked UART source raised the CPU interrupt");
        read_word(uart1_base + 'h04, 'h155);

        write_word(timer_base + 'h00, 4);
        write_word(timer_base + 'h10, 1);
        write_word(timer_base + 'h04, 1);
        await(i_soc.peripherals.timer_irq);
        check(i_soc.irq, "Timer interrupt did not reach the CPU");
        read_word(timer_base + 'h08, 1);
        read_word(timer_base + 'h0c, 1);
        read_word(sysctrl_base + 'h10, 'b0001);
        write_word(timer_base + 'h0c, 1);
        read_word(timer_base + 'h0c, 0);
        check(!i_soc.peripherals.timer_irq && !i_soc.irq, "Timer interrupt stayed asserted after clearing it");

        //GPIO outputs, inputs and rising edge interrupt
        write_word(gpio_base + 'h00, 'ha5);
        write_word(gpio_base + 'h04, 'h0f);
        check(i_soc.peripherals.gpio.pins_out == 'ha5 && i_soc.peripherals.gpio.pins_oe == 'h0f, "GPIO outputs do not match their registers");
        write_word(gpio_base + 'h10, 'h04);
        rg_pins <= 'h02;
        read_word(gpio_base + 'h08, 'h02);
        check(!i_soc.peripherals.gpio_irq, "Masked GPIO pin raised the interrupt");
        rg_pins <= 'h06;
        await(i_soc.peripherals.gpio_irq);
        check(i_soc.irq, "GPIO interrupt did not reach the CPU");
        read_word(gpio_base + 'h0c, 'h06);
        read_word(sysctrl_base + 'h10, 'b0010);
        write_word(gpio_base + 'h0c, 'h06);
        read_word(gpio_base + 'h0c, 0);
        check(!i_soc.peripherals.gpio_irq && !i_soc.irq, "GPIO interrupt stayed asserted after clearing it");

        //unmapped addresses on both segments
        access('h4000_5000, False, 0, AHB_WORD, True);
        access('h3000_0000, False, 0, AHB_WORD, True);
        $display("PASS: SoC memories, system controller, UARTs, timer, GPIO, interrupts, and unmapped access");
    endseq);
endmodule

endpackage
