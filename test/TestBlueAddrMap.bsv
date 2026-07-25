package TestBlueAddrMap;

import StmtFSM :: *;
import ModuleContext :: *;
import Vector :: *;
import BuildVector :: *;

import BlueAddrMap :: *;
import BlueInterruptMap :: *;
import BlueCSRCore :: *;

interface TestAhbTarget_ifc;
    method Bit#(2) target_id;
endinterface

interface TestApbTarget_ifc;
    method Bit#(2) target_id;
endinterface

module mkTestAhbTarget#(Bit#(2) id)(TestAhbTarget_ifc);
    method Bit#(2) target_id = id;
endmodule

module mkTestApbTarget#(Bit#(2) id)(TestApbTarget_ifc);
    method Bit#(2) target_id = id;
endmodule

// A mapped-device module instantiates its peripheral and contributes the
// corresponding entry to its caller's fabric context.
module [AddrMapCtx_t#(32, TestApbTarget_ifc)] mapped_apb_target#(Integer base, String name, Bit#(2) id)(TestApbTarget_ifc);
    TestApbTarget_ifc i_target <- mkTestApbTarget(id);
    addr_map_target(base, 'h0000_1000, name, i_target);
    return i_target;
endmodule

interface TestApbSubsystem_ifc;
    interface TestApbTarget_ifc uart;
    interface TestApbTarget_ifc gpio;
    interface TestApbTarget_ifc boot_status;
endinterface

// This is one downstream APB segment. Its peripheral instances and map are
// separate from the upstream high-performance fabric.
module [AddrMapCtx_t#(32, TestApbTarget_ifc)] apb_peripheral_map(TestApbSubsystem_ifc);
    addr_map_def("exampleSoCAPB");

    TestApbTarget_ifc i_uart <- mapped_apb_target('h1000_0000, "UART0", 0);
    TestApbTarget_ifc i_gpio <- mapped_apb_target('h1001_0000, "GPIO0", 1);
    TestApbTarget_ifc i_boot <- mapped_apb_target('h1002_0000, "BOOT_STATUS", 2);

    interface uart = i_uart;
    interface gpio = i_gpio;
    interface boot_status = i_boot;
endmodule

interface TestAhbToApbBridge_ifc#(type downstream_ifc);
    interface TestAhbTarget_ifc upstream;
    interface AddrMapDecoder_ifc#(32) downstream_decoder;
    interface downstream_ifc downstream;
endinterface

// A protocol bridge consumes the APB context once and exposes one native AHB
// target to the parent fabric. A real implementation also connects the two
// protocols' channels and keeps their response state.
module [Module] mkTestAhbToApbBridge#(AddrMapCtx_t#(32, TestApbTarget_ifc, downstream_ifc) downstream_ctx)(TestAhbToApbBridge_ifc#(downstream_ifc));
    TestAhbTarget_ifc i_upstream <- mkTestAhbTarget(1);
    AddrMap_ifc#(32, downstream_ifc) i_downstream <- create_addr_map(
        downstream_ctx
    );

    interface upstream = i_upstream;
    interface downstream_decoder = i_downstream.decoder;
    interface downstream = i_downstream.internal;
endmodule

interface TestSocFabric_ifc;
    interface TestAhbTarget_ifc memory;
    interface TestAhbToApbBridge_ifc#(TestApbSubsystem_ifc) peripherals;
endinterface

// The upstream map sees one memory and one bridge aperture. It does not repeat
// the downstream peripheral map or depend on a separately ordered client list.
module [AddrMapCtx_t#(32, TestAhbTarget_ifc)] soc_address_map(TestSocFabric_ifc);
    addr_map_def("exampleSoC");

    TestAhbTarget_ifc i_memory <- mkTestAhbTarget(0);
    TestAhbToApbBridge_ifc#(TestApbSubsystem_ifc) i_peripherals
        <- liftModule(mkTestAhbToApbBridge(apb_peripheral_map));

    addr_map_target('h8000_0000, 'h0001_0000, "SRAM", i_memory);
    addr_map_target(
        'h1000_0000,
        'h0004_0000,
        "APB_PERIPHERALS",
        i_peripherals.upstream
    );

    interface memory = i_memory;
    interface peripherals = i_peripherals;
endmodule

interface TestIRQSource_ifc#(numeric type n);
    interface IRQLines_ifc#(n) irqs;
    method Action set_irqs(Bit#(n) value);
endinterface

module mkTestIRQSource(TestIRQSource_ifc#(n));
    Reg#(Bit#(n)) rg_irqs <- mkReg(0);

    interface IRQLines_ifc irqs;
        method Vector#(n, Bool) lines = unpack(rg_irqs);
    endinterface

    method set_irqs = rg_irqs._write;
endmodule

interface TestInterruptSources_ifc;
    interface TestIRQSource_ifc#(2) uart;
    method Bool gpio_irq;
    method Action set_gpio_irq(Bool value);
    method Action set_shared_irq(Bool value);
endinterface

module [IRQMapCtx_t#(8)] soc_irq_map(TestInterruptSources_ifc);
    irq_map_def("exampleSoCInterrupts");

    TestIRQSource_ifc#(2) i_uart <- mkTestIRQSource;
    Reg#(Bool) rg_gpio_irq   <- mkReg(False);
    Reg#(Bool) rg_shared_irq <- mkReg(False);

    irq_map_source(2, "UART0",      i_uart.irqs.lines);
    irq_map_source(3, "SHARED_IRQ", vec(rg_shared_irq));
    irq_map_source(5, "GPIO0",      vec(rg_gpio_irq));

    interface uart = i_uart;
    method gpio_irq = rg_gpio_irq;
    method set_gpio_irq = rg_gpio_irq._write;
    method set_shared_irq = rg_shared_irq._write;
endmodule

(* synthesize *)
module mkTestBlueAddrMap(Empty);
    AddrMap_ifc#(32, TestSocFabric_ifc) map <- create_addr_map(soc_address_map);
    AddrMapDoc_t doc <- doc_addr_map(soc_address_map);
    IRQMap_ifc#(8, TestInterruptSources_ifc) interrupts
        <- create_irq_map(soc_irq_map);

    function Action expect_hit(
            AddrMapDecoder_ifc#(32) decoder,
            Bit#(32) address,
            Bool expected_hit,
            Bit#(32) expected_offset
        );
        action
            let got = decoder.lookup(address);
            if(got.hit != expected_hit
                    || got.global_addr != address
                    || got.offset != expected_offset) begin
                $display(
                    "Address map mismatch at %08x: hit=%0d global=%08x offset=%08x",
                    address,
                    got.hit,
                    got.global_addr,
                    got.offset
                );
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_span(
            Bit#(32) address,
            Bit#(32) bytes,
            Bool expected_hit
        );
        action
            let got = map.decoder.lookup_span(address, bytes);
            if(got.hit != expected_hit || got.global_addr != address) begin
                $display(
                    "Address span mismatch at %08x + %0d: hit=%0d global=%08x",
                    address,
                    bytes,
                    got.hit,
                    got.global_addr
                );
                $finish(1);
            end
        endaction
    endfunction

    Stmt test = seq
        expect_hit(map.decoder, 'h8000_0010, True, 'h0000_0010);
        expect_hit(map.decoder, 'h1001_0004, True, 'h0001_0004);
        expect_hit(map.decoder, 'h2000_0000, False, 0);

        // The bridge forwards the global address. Its own APB map performs the
        // leaf decode and reports the peripheral-local offset separately.
        expect_hit(
            map.internal.peripherals.downstream_decoder,
            'h1001_0004,
            True,
            4
        );
        expect_hit(
            map.internal.peripherals.downstream_decoder,
            'h1003_0000,
            False,
            0
        );

        expect_span('h8000_FFFC, 4, True);
        expect_span('h8000_FFFE, 4, False);

        action
            if(map.internal.memory.target_id != 0
                    || map.internal.peripherals.upstream.target_id != 1
                    || map.internal.peripherals.downstream.gpio.target_id != 1) begin
                $display("Fabric context returned the wrong instantiated devices");
                $finish(1);
            end
            messageM(doc.text);
        endaction

        action
            interrupts.internal.uart.set_irqs('b01);
            interrupts.internal.set_gpio_irq(False);
            interrupts.internal.set_shared_irq(False);
        endaction
        action
            if(!interrupts.irqs.lines[2]
                    || interrupts.irqs.lines[3]
                    || interrupts.irqs.lines[5]
                    || interrupts.irqs.lines[0]) begin
                $display("Interrupt wire map routed the wrong sources");
                $finish(1);
            end
        endaction

        action
            interrupts.internal.uart.set_irqs('b10);
            interrupts.internal.set_gpio_irq(True);
            interrupts.internal.set_shared_irq(False);
        endaction
        action
            if(interrupts.irqs.lines[2]
                    || !interrupts.irqs.lines[3]
                    || !interrupts.irqs.lines[5]) begin
                $display("Interrupt vector bases routed the wrong sources");
                $finish(1);
            end
        endaction

        action
            interrupts.internal.uart.set_irqs(0);
            interrupts.internal.set_gpio_irq(False);
            interrupts.internal.set_shared_irq(True);
        endaction
        action
            if(!interrupts.irqs.lines[3]
                    || interrupts.irqs.lines[2]
                    || interrupts.irqs.lines[5]) begin
                $display("Interrupt map did not OR overlapping source ranges");
                $finish(1);
            end
        endaction

        $display("Finished BlueAddrMap TB");
        $finish(0);
    endseq;

    mkAutoFSM(test);
endmodule

endpackage
