package SCOoOTERMapSupport;

import ClientServer :: *;
import FIFOF :: *;
import GetPut :: *;
import ModuleContext :: *;
import SpecialFIFOs :: *;
import Vector :: *;

import Interfaces :: *;
import SPICore :: *;
import Types :: *;

import BlueCSRCore :: *;

interface SCOoOTERSPIMemory_ifc;
    interface MemMappedIFC#(32) memory_bus;
    interface MemMappedIFC#(32) control_bus;

    (* always_ready, always_enabled *)
    method Bit#(1) spi_clk;
    (* always_ready, always_enabled *)
    method Bit#(1) spi_mosi;
    (* always_ready, always_enabled *)
    method Action spi_miso(Bit#(1) value);
    (* always_ready, always_enabled *)
    method Bool spi_cs;
endinterface

interface SCOoOTERSPIControl_ifc;
    method Bit#(32) clkdiv;
endinterface

interface SCOoOTERBlueCSRAdapter_ifc#(numeric type ni);
    interface MemMappedIFC#(32) memory_bus;
    method Vector#(ni, Bool) irqs;
endinterface

interface SCOoOTERBlueCSRControl_ifc;
    method Action interrupt_event;
endinterface

interface SCOoOTERBlueCSRStub_ifc;
    interface MemMappedIFC#(32) memory_bus;
    method Vector#(1, Bool) irqs;
    method Action interrupt_event;
endinterface

interface SCOoOTERDevices_ifc;
    interface SCOoOTERSPIMemory_ifc spi_memory;
    interface SCOoOTERBlueCSRStub_ifc bluecsr_stub;
    interface MemMappedIFC#(32) rv_controller;
    interface MemMappedIFC#(32) clint;
    interface MemMappedIFC#(32) plic;
    interface MemMappedIFC#(32) axi_full;
    interface MemMappedIFC#(32) axi_lite;

    method Vector#(2, Bool) platform_irqs;
    method Bool expansion_irq;
endinterface

module [BlueCSRCtx_t#(32, 32)] scoooter_spi_control_regs(SCOoOTERSPIControl_ifc);
    Reg#(Bit#(32)) rg_clkdiv;

    csr_regmap_def("scoooterSPIControl", "SCOoOTER SPI memory control registers.");

    csr_reg_def('h00, "CLOCK_DIVIDER", "SPI clock divider register.");
    rg_clkdiv <- csr_reg_rw('h00, Bit#(32)'(4), 0, "CLKDIV", "Clock Divider", "Sets the SPI serial clock divider.");

    method clkdiv = rg_clkdiv;
endmodule

module [BlueCSRCtx_t#(32, 32)] scoooter_bluecsr_stub_regs(SCOoOTERBlueCSRControl_ifc);
    Wire#(Bool) w_interrupt_event <- mkDWire(False);

    csr_regmap_def("scoooterBlueCSRStub", "Example BlueCSR-controlled SCOoOTER peripheral.");

    csr_reg_def('h00, "IDENTIFICATION", "Peripheral identification register.");
    csr_reg_rc('h00, Bit#(32)'('h4253_4352), 0, "IDENT", "Identification", "ASCII BSCR.");

    csr_reg_def('h04, "IRQ_PENDING", "Interrupt pending register.");
    csr_reg_def('h08, "IRQ_ENABLE", "Interrupt enable register.");
    csr_irq('h04, 'h08, 0, 0, w_interrupt_event, "EVENT_IRQ", "Event Interrupt", "An external event is pending.");

    method Action interrupt_event = w_interrupt_event._write(True);
endmodule

// SCOoOTER has independent read and write servers, while BlueCSR uses one
// ordered stream. This adapter serializes both directions and restores IDs.
// Input addresses are peripheral-local offsets selected by the fabric.
module [Module] mkSCOoOTERBlueCSRAdapter#(BlueCSR_ifc#(32, 32, ni) csr)(SCOoOTERBlueCSRAdapter_ifc#(ni));
    FIFOF#(Tuple2#(UInt#(32), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) f_read_requests <- mkFIFOF;
    FIFOF#(Tuple4#(UInt#(32), Bit#(32), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) f_write_requests <- mkFIFOF;
    FIFOF#(Tuple2#(Bit#(32), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) f_read_responses <- mkFIFOF;
    FIFOF#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) f_write_responses <- mkFIFOF;

    Reg#(Bool) rg_pending       <- mkReg(False);
    Reg#(Bool) rg_pending_write <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) rg_pending_id <- mkRegU;

    (* descending_urgency = "r_issue_read, r_issue_write" *)
    rule r_issue_read if(!rg_pending);
        let request = f_read_requests.first;
        f_read_requests.deq;
        csr.request.put(
            BlueCSR_Req_t {
                wr:     False,
                addr:   pack(tpl_1(request)),
                wdata:  0,
                wstrb:  0,
                prot:   CSR_SECURE
            }
        );
        rg_pending       <= True;
        rg_pending_write <= False;
        rg_pending_id    <= tpl_2(request);
    endrule

    rule r_issue_write if(!rg_pending);
        let request = f_write_requests.first;
        f_write_requests.deq;
        csr.request.put(
            BlueCSR_Req_t {
                wr:     True,
                addr:   pack(tpl_1(request)),
                wdata:  tpl_2(request),
                wstrb:  tpl_3(request),
                prot:   CSR_SECURE
            }
        );
        rg_pending       <= True;
        rg_pending_write <= True;
        rg_pending_id    <= tpl_4(request);
    endrule

    rule r_complete_request if(rg_pending);
        let response <- csr.response.get;
        if(rg_pending_write) f_write_responses.enq(rg_pending_id);
        else f_read_responses.enq(tuple2(response.rdata, rg_pending_id));
        rg_pending <= False;
    endrule

    interface MemMappedIFC memory_bus;
        interface Server mem_r;
            interface request  = toPut(f_read_requests);
            interface response = toGet(f_read_responses);
        endinterface

        interface Server mem_w;
            interface request  = toPut(f_write_requests);
            interface response = toGet(f_write_responses);
        endinterface
    endinterface

    method irqs = csr.irqs;
endmodule

// SPICore's data servers already match a SCOoOTER memory target. A separate
// BlueCSR aperture controls the same instance and continuously supplies its
// clock divider, while the physical SPI pins remain explicit.
module [Module] mkSCOoOTERSPIMemory(SCOoOTERSPIMemory_ifc);
    SPICore#(TAdd#(TLog#(NUM_CPU), 1)) i_spi <- mkSPICore;
    BlueCSRAccess_ifc#(32, 32, 0, SCOoOTERSPIControl_ifc) i_csr <- create_blue_csr(scoooter_spi_control_regs, False);
    SCOoOTERBlueCSRAdapter_ifc#(0) i_control <- mkSCOoOTERBlueCSRAdapter(i_csr.external);

    rule r_set_spi_clkdiv;
        i_spi.set_clkdiv(i_csr.internal.clkdiv);
    endrule

    interface MemMappedIFC memory_bus;
        interface mem_r = i_spi.r;
        interface mem_w = i_spi.w;
    endinterface

    interface control_bus = i_control.memory_bus;

    method spi_clk  = i_spi.spi_clk;
    method spi_mosi = i_spi.spi_mosi;
    method spi_miso = i_spi.spi_miso;
    method spi_cs   = i_spi.spi_cs;
endmodule

module [Module] mkSCOoOTERBlueCSRStub(SCOoOTERBlueCSRStub_ifc);
    BlueCSRAccess_ifc#(32, 32, 1, SCOoOTERBlueCSRControl_ifc) i_csr <- create_blue_csr(scoooter_bluecsr_stub_regs, False);
    SCOoOTERBlueCSRAdapter_ifc#(1) i_adapter <- mkSCOoOTERBlueCSRAdapter(i_csr.external);

    interface memory_bus = i_adapter.memory_bus;
    method irqs = i_adapter.irqs;
    method interrupt_event = i_csr.internal.interrupt_event;
endmodule

// These stubs stand in for SCOoOTER's protocol-specific width adapters. The
// map itself only sees uniform native MemMappedIFC endpoints.
module mkMemMappedTargetStub(MemMappedIFC#(32));
    FIFOF#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) f_read_ids  <- mkBypassFIFOF;
    FIFOF#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) f_write_ids <- mkBypassFIFOF;

    interface Server mem_r;
        interface Put request;
            method Action put(Tuple2#(UInt#(32), Bit#(TAdd#(TLog#(NUM_CPU), 1))) request);
                f_read_ids.enq(tpl_2(request));
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get;
                let id = f_read_ids.first;
                f_read_ids.deq;
                return tuple2(0, id);
            endmethod
        endinterface
    endinterface

    interface Server mem_w;
        interface Put request;
            method Action put(Tuple4#(UInt#(32), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) request);
                f_write_ids.enq(tpl_4(request));
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get;
                let id = f_write_ids.first;
                f_write_ids.deq;
                return id;
            endmethod
        endinterface
    endinterface
endmodule

module mkSCOoOTERDevices(SCOoOTERDevices_ifc);
    SCOoOTERSPIMemory_ifc  i_spi_memory    <- liftModule(mkSCOoOTERSPIMemory);
    SCOoOTERBlueCSRStub_ifc i_bluecsr_stub <- liftModule(mkSCOoOTERBlueCSRStub);
    MemMappedIFC#(32)      i_rv_controller <- mkMemMappedTargetStub;
    MemMappedIFC#(32)      i_clint         <- mkMemMappedTargetStub;
    MemMappedIFC#(32)      i_plic          <- mkMemMappedTargetStub;
    MemMappedIFC#(32)      i_axi_full      <- mkMemMappedTargetStub;
    MemMappedIFC#(32)      i_axi_lite      <- mkMemMappedTargetStub;

    interface spi_memory    = i_spi_memory;
    interface bluecsr_stub  = i_bluecsr_stub;
    interface rv_controller = i_rv_controller;
    interface clint         = i_clint;
    interface plic          = i_plic;
    interface axi_full      = i_axi_full;
    interface axi_lite      = i_axi_lite;

    method Vector#(2, Bool) platform_irqs = unpack(2'b11);
    method Bool expansion_irq = False;
endmodule

endpackage
