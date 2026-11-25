package BlueCSRSoCExample;

import Connectable :: *;
import GetPut      :: *;
import StmtFSM     :: *;

import Ahb                :: *;
import AhbMaster          :: *;
import BlueAddrMap        :: *;
import BlueCSRFabricMap   :: *;
import ExamplePeripherals :: *;
import ExampleSoC         :: *;

function Action write_example_doc(String path, String contents);
    action
        File fh <- $fopen(path, "w");
        if(fh == InvalidFile) $fatal(1, "Could not open %s", path);
        else begin
            $fwrite(fh, "%s", contents);
            $fclose(fh);
        end
    endaction
endfunction

module [Module] mkBlueCSRSoCExample(Empty);
    match {.i_fabric, .doc} <- create_fabric_with_map(example_ahb_config(), soc_map);

    ExampleSoC_ifc        i_soc     = example_soc_ports(i_fabric);
    AhbMaster_ifc#(32, 32) i_master <- mkAhbMaster(2);
    mkConnection(i_master.fabric, i_soc.ahb);

    Bit#(32) uart0_base = 'h4000_1000;
    Bit#(32) uart1_base = 'h4000_2000;
    Bit#(32) timer_base = 'h4000_3000;

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

    Reg#(UInt#(11)) rg_cycles <- mkReg(0);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 1023) $fatal(1, "Timed out running the SoC example");
    endrule

    mkAutoFSM(seq
        action
            write_example_doc("sim/BlueCSRSoCExample.md",  doc_fabric_map_markdown(doc));
            write_example_doc("sim/BlueCSRSoCExample.rdl", doc_fabric_map_systemrdl(doc));
        endaction

        write_word('h0000_0000, 'h1234_5678);
        read_word('h0000_0000, 'h1234_5678);

        read_word(uart0_base + 'h00, 1);
        read_word(uart0_base + 'h80, 'h5541_5254);
        read_word(uart0_base + 'h88, 4);
        exercise_uart(i_soc.peripherals.uart0, uart0_base, 'h41, 'h42);
        read_word(uart1_base + 'h100, 0);
        exercise_uart(i_soc.peripherals.uart1, uart1_base, 'h61, 'h62);

        write_word(timer_base + 'h00, 4);
        write_word(timer_base + 'h10, 1);
        write_word(timer_base + 'h04, 1);
        await(i_soc.peripherals.timer_irq);
        read_word(timer_base + 'h08, 1);
        read_word(timer_base + 'h0c, 1);
        write_word(timer_base + 'h0c, 1);
        read_word(timer_base + 'h0c, 0);
        action
            if(i_soc.peripherals.timer_irq) $fatal(1, "Timer interrupt stayed asserted after clearing it");
        endaction

        access('h4000_4000, False, 0, AHB_WORD, True);
        $display("PASS: SoC scratch memory, both UARTs, timer IRQ, and unmapped access");
    endseq);
endmodule

endpackage
