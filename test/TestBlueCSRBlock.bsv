package TestBlueCSRBlock;

import ClientServer :: *;
import FIFOF :: *;
import GetPut :: *;
import StmtFSM :: *;
import Vector :: *;

import BlueCSR :: *;
import BlueCSRMux :: *;

interface BlockA_ifc;
    interface Reg#(Bit#(32)) value;
    method Action   irq_event(Bool value);
    method Bit#(16) write_addr;
    method Bit#(8)  read_count;
    method Bit#(8)  write_count;
endinterface

interface BlockB_ifc;
    interface Reg#(Bit#(32)) value;
    interface Reg#(Bit#(32)) leaf;
endinterface

interface BlockTop_ifc;
    interface BlockA_ifc a;
    interface BlockB_ifc b;
endinterface

module mkBlockServer(Server#(BlueCSR_Req_t#(16, 32), BlueCSR_Rsp_t#(32)));
    FIFOF#(BlueCSR_Rsp_t#(32)) f_rsp    <- mkSizedFIFOF(1);
    Reg#(Bit#(32))            rg_value <- mkReg(0);

    interface Put request;
        method Action put(BlueCSR_Req_t#(16, 32) req);
            if(req.wr) rg_value <= req.wdata;
            f_rsp.enq(BlueCSR_Rsp_t {
                rdata: req.wr ? 0 : rg_value + zeroExtend(req.addr),
                resp:  CSR_OKAY
            });
        endmethod
    endinterface
    interface response = toGet(f_rsp);
endmodule

module [BlueCSRCtx_t#(16, 32)] block_a_regs(BlockA_ifc);
    Wire#(Bool)    w_irq_event    <- mkDWire(False);
    Reg#(Bit#(16)) rg_write_addr  <- mkReg(0);
    Reg#(Bit#(32)) rg_region_data <- mkReg(0);

    let i_server <- mkBlockServer;

    function Bit#(32) read_region(Bit#(16) addr) = rg_region_data + zeroExtend(addr);
    function Action write_region(Bit#(16) addr, Bit#(32) data);
        action
            rg_write_addr  <= addr;
            rg_region_data <= data;
        endaction
    endfunction

    csr_regmap_def("ChildA", "Registers, callbacks, server and IRQ");
    csr_reg_def('h00, "DATA", "Child A data");
    Reg#(Bit#(32)) rg_value <- csr_reg_rw('h00, 0, 0, "VALUE", "Value", "Read-write value");
    csr_reg_prot('h00, CSR_SEC_SECURE_ONLY, CSR_SEC_SECURE_ONLY);
    csr_reg_def('h10, "PENDING", "Interrupt pending");
    csr_reg_def('h14, "ENABLE",  "Interrupt enable");
    csr_irq('h10, 'h14, 0, 0, w_irq_event, "EVENT", "Event", "Sticky child event");
    csr_reg_def('h18, "TRIGGER", "Read and write triggers");
    let rg_read_trigger  <- csr_reg_trigr('h18, False);
    let rg_write_trigger <- csr_reg_trigw('h18, False);

    Reg#(Bit#(8)) rg_read_count  <- mkReg(0);
    Reg#(Bit#(8)) rg_write_count <- mkReg(0);

    rule r_count_reads(rg_read_trigger == 1);
        rg_read_count <= rg_read_count + 1;
    endrule
    rule r_count_writes(rg_write_trigger == 1);
        rg_write_count <= rg_write_count + 1;
    endrule
    csr_region_rw('h40, 'h20, read_region, write_region, "REGION", "Region-relative callbacks");
    csr_region_prot('h40, 'h20, CSR_SEC_SECURE_ONLY, CSR_ALLOW_ALL);
    csr_region_server('h80, 'h20, True, CSR_SLVERR, i_server, "SERVER", "Region-relative server");

    interface value = rg_value;
    method irq_event   = w_irq_event._write;
    method write_addr  = rg_write_addr;
    method read_count  = rg_read_count;
    method write_count = rg_write_count;
endmodule

module [BlueCSRCtx_t#(16, 32)] block_leaf_regs(Reg#(Bit#(32)));
    Reg#(Bit#(32)) rg_value <- mkReg(0);

    function ActionValue#(BlueCSR_Rsp_t#(32)) read_value();
        actionvalue
            return BlueCSR_Rsp_t { rdata: rg_value, resp: CSR_OKAY };
        endactionvalue
    endfunction
    function ActionValue#(BlueCSRResponse_t) write_value(Bit#(32) data, Bit#(4) strb);
        actionvalue
            if(strb == 'hf) rg_value <= data;
            return strb == 'hf ? CSR_OKAY : CSR_SLVERR;
        endactionvalue
    endfunction

    function Bool can_write(Bit#(32) data, Bit#(4) strb) = True;

    csr_regmap_def("Leaf", "Nested action register");
    csr_reg_def('h00, "DATA", "Nested leaf data");
    csr_reg_act_rw('h00, Bit#(32)'(0), 0, True, BlueCSR_Rsp_t { rdata: 0, resp: CSR_SLVERR }, read_value, can_write, CSR_SLVERR, write_value, "VALUE", "Value", "Action read and write");
    return rg_value;
endmodule

module [BlueCSRCtx_t#(16, 32)] block_b_regs#(Bit#(32) initial_value)(BlockB_ifc);
    csr_regmap_def("ChildB", "Parameterized child with a nested block");
    csr_reg_def('h04, "DATA", "Child B data");
    Reg#(Bit#(32)) rg_value <- csr_reg_rw('h04, initial_value, 0, "VALUE", "Value", "Read-write value");
    let            i_leaf   <- csr_block('h80, 'h80, "LEAF", block_leaf_regs);

    interface value = rg_value;
    interface leaf  = i_leaf;
endmodule

module [BlueCSRCtx_t#(16, 32)] block_unnamed_regs(Empty);
    csr_reg_def(0, "RAW", "Child without map metadata");
    csr_reg_rc(0, Bit#(32)'('hfeed), 0, "VALUE", "Value", "Constant");
endmodule

module [BlueCSRCtx_t#(16, 32)] block_unnamed_wrapper(Empty);
    csr_block(0, 'h40, "", block_unnamed_regs);
endmodule

module [BlueCSRCtx_t#(16, 32)] block_top_regs(BlockTop_ifc);
    csr_regmap_def("Combined", "One decoder for all child maps");
    //earlier parent entries must not be shifted or prefixed
    csr_reg_def(0, "TOP", "Parent identifier");
    csr_reg_rc(0, Bit#(32)'('hcafe), 0, "VALUE", "Value", "Parent constant");
    let i_a <- csr_block('h100, 'h100, "A", block_a_regs);
    let i_b <- csr_block('h400, 'h100, "B", block_b_regs(3));
    csr_block('h600, 'h40, "",         block_unnamed_wrapper);
    csr_block('h700, 'h40, "Fallback", block_unnamed_regs);

    interface a = i_a;
    interface b = i_b;
endmodule

module [Module] mkBlockTest#(Bool buffer_in, Bool buffer_out, Bool use_mux)(ReadOnly#(Bool));
    BlueCSRCfg_t                                cfg      = BlueCSRCfg_t { buffer_in: buffer_in, buffer_out: buffer_out, default_response: CSR_DECERR };
    BlueCSRAccess_ifc#(16, 32, 1, BlockTop_ifc) i_regs   <- create_blue_csr_cfg(block_top_regs, cfg);
    BlueCSR_ifc#(16, 32, 1)                     csr      = i_regs.external;
    Integer                                     bus_base = use_mux ? 'h8000 : 0;

    if(use_mux) begin
        Vector#(1, BlueCSRSubmap_t#(16))    submaps  = replicate(BlueCSRSubmap_t { base: 'h8000, mask: 'hf000 });
        Vector#(1, BlueCSR_ifc#(16, 32, 1)) children = replicate(i_regs.external);

        let i_mux <- mkBlueCSRMux(submaps, children);
        csr = i_mux;
    end
    Reg#(Bool) rg_done <- mkReg(False);

    function Action request(Bool wr, Bit#(16) addr, Bit#(32) data, BlueCSRProt_t prot);
        return csr.request.put(BlueCSR_Req_t {
            wr:    wr,
            addr:  addr + fromInteger(bus_base),
            wdata: data,
            wstrb: 'hf,
            prot:  prot
        });
    endfunction

    function Action check_response(Bit#(32) data, BlueCSRResponse_t resp);
        action
            let rsp <- csr.response.get;
            if(rsp.rdata != data || rsp.resp != resp) begin
                $display("FAIL: block in=%0d out=%0d mux=%0d expected=%h/%0d got=%h/%0d", buffer_in, buffer_out, use_mux, data, resp, rsp.rdata, rsp.resp);
                $finish(1);
            end
        endaction
    endfunction

    function Stmt access(Bool wr, Bit#(16) addr, Bit#(32) data, Bit#(32) expected, BlueCSRResponse_t resp);
        return seq
            request(wr, addr, data, CSR_SECURE);
            check_response(expected, resp);
        endseq;
    endfunction

    Stmt test = seq
        access(False, 'h000, 0,          'hcafe,     CSR_OKAY);
        access(True,  'h100, 'h12345678, 0,          CSR_OKAY);
        access(False, 'h100, 0,          'h12345678, CSR_OKAY);
        access(False, 'h404, 0,          3,          CSR_OKAY);
        access(True,  'h404, 'h87654321, 0,          CSR_OKAY);
        access(False, 'h404, 0,          'h87654321, CSR_OKAY);
        $display("PASS: two child maps and unchanged parent entries in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        request(False, 'h100, 0, CSR_INSECURE);
        check_response(0, CSR_DECERR);
        $display("PASS: shifted register policy in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        access(False, 'h118, 0, 0, CSR_OKAY);
        access(True,  'h118, 0, 0, CSR_OKAY);
        action
            if(i_regs.internal.a.read_count != 1 || i_regs.internal.a.write_count != 1) begin
                $display("FAIL: shifted read or write trigger");
                $finish(1);
            end
        endaction
        $display("PASS: shifted triggers in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        access(True,  'h14c, 'h1000, 0, CSR_OKAY);
        action
            if(i_regs.internal.a.write_addr != 'hc) begin
                $display("FAIL: callback did not receive region-relative write address");
                $finish(1);
            end
        endaction
        access(False, 'h154, 0, 'h1014, CSR_OKAY);
        request(False, 'h154, 0, CSR_INSECURE);
        check_response(0, CSR_DECERR);
        $display("PASS: region-relative callbacks and policy in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        access(True,  'h184, 'h2000, 0,      CSR_OKAY);
        access(False, 'h19c, 0,      'h201c, CSR_OKAY);
        $display("PASS: region-relative server in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        i_regs.internal.a.irq_event(True);
        access(True, 'h114, 1, 0, CSR_OKAY);
        action
            if(!csr.irqs[0]) begin
                $display("FAIL: child IRQ did not reach combined vector");
                $finish(1);
            end
        endaction
        access(True, 'h110, 1, 0, CSR_OKAY);
        action
            if(csr.irqs[0]) begin
                $display("FAIL: child IRQ did not clear");
                $finish(1);
            end
        endaction
        $display("PASS: child IRQ in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        access(False, 'h300, 0, 0, CSR_DECERR);
        access(True,  'h300, 1, 0, CSR_DECERR);
        $display("PASS: gap decode errors in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        access(True,  'h480, 'habcdef01, 0,          CSR_OKAY);
        access(False, 'h480, 0,          'habcdef01, CSR_OKAY);
        $display("PASS: nested action register in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);
        action
            if(i_regs.internal.b.leaf != 'habcdef01 || i_regs.internal.b.value != 'h87654321) begin
                $display("FAIL: returned child interface does not expose bus-written values");
                $finish(1);
            end
            i_regs.internal.a.value <= 'h76543210;
            i_regs.internal.b.leaf  <= 'h11223344;
        endaction
        access(False, 'h100, 0, 'h76543210, CSR_OKAY);
        access(False, 'h480, 0, 'h11223344, CSR_OKAY);
        $display("PASS: returned child interfaces in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);

        access(False, 'h600, 0, 'hfeed, CSR_OKAY);
        access(False, 'h700, 0, 'hfeed, CSR_OKAY);
        $display("PASS: empty prefix and children without map metadata in=%0d out=%0d mux=%0d", buffer_in, buffer_out, use_mux);
        rg_done <= True;
    endseq;
    FSM        i_fsm      <- mkFSM(test);
    Reg#(Bool) rg_started <- mkReg(False);

    rule r_start(!rg_started);
        i_fsm.start;
        rg_started <= True;
    endrule
    method _read = rg_done;
endmodule

(* synthesize *)
module mkTestBlueCSRBlock(Empty);
    let i_direct   <- mkBlockTest(False, False, False);
    let i_buffered <- mkBlockTest(True,  False, False);
    let i_out      <- mkBlockTest(False, True,  False);
    let i_both     <- mkBlockTest(True,  True,  True);
    let i_mux      <- mkBlockTest(False, False, True);

    RegMapDoc_t#(32)  markdown  <- doc_blue_csr_markdown(block_top_regs);
    RegMapDoc_t#(32)  text_doc  <- doc_blue_csr(block_top_regs);
    RegMapDoc_t#(32)  plain_doc <- doc_blue_csr_markdown(block_leaf_regs);
    BlueCSRExport_ifc i_export  <- export_systemrdl_blue_csr(block_top_regs, "sim/testBlueCSRBlock.rdl");
    Reg#(UInt#(16))   rg_cycles <- mkReg(0);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 2000) begin
            $display("FAIL: block test timed out");
            $finish(1);
        end
    endrule
    rule r_finish(i_direct && i_buffered && i_out && i_both && i_mux && i_export.done);
        if(!i_export.success) begin
            $display("FAIL: block SystemRDL export");
            $finish(1);
        end
        $display("%s", markdown.reg_defs);
        $display("%s", text_doc.reg_defs);
        $display("PASS: csr_block including mux composition and all exports");
        $finish(0);
    endrule
endmodule

endpackage
