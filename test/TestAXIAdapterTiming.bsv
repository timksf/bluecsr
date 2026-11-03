package TestAXIAdapterTiming;

/*
 * Cycle-level checks for mkBlueCSRAXI4LiteAdapter with unbuffered (0) and
 * buffered (1) request paths. Each adapter sits behind its own synthesis
 * boundary, as it would in hardware, and is driven by a register-based master
 */

import FIFOF :: *;
import StmtFSM :: *;

import BlueAXI :: *;
import BlueCSR :: *;

interface TimingDut_ifc;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;
endinterface

module [BlueCSRCtx_t#(32, 32)] timing_csrs(Empty);
    csr_regmap_def("Timing", "AXI adapter timing test registers");
    csr_reg_def('h00, "ID", "Constant");
    csr_reg_rc('h00, Bit#(32)'('hCAFE0001), 0, "ID", "ID", "Constant ID.");
    csr_reg_def('h04, "DATA", "Read/write data");
    Reg#(Bit#(32)) rg_data <- csr_reg_rw('h04, 0, 0, "DATA", "Data", "Read/write data.");
endmodule

module [Module] mkTimingDut#(Integer buffer)(TimingDut_ifc);
    BlueCSRAccess_ifc#(32, 32, 0, Empty) csr <- create_blue_csr(timing_csrs, False);
    BlueCSR_AXI4Lite_ifc#(32, 32, 0) axi <- mkBlueCSRAXI4LiteAdapter(csr.external, buffer, buffer);
    interface s_rd = axi.s_rd;
    interface s_wr = axi.s_wr;
endmodule

(* synthesize *)
module mkTimingDut0(TimingDut_ifc);
    let dut <- mkTimingDut(0);
    return dut;
endmodule

(* synthesize *)
module mkTimingDut1(TimingDut_ifc);
    let dut <- mkTimingDut(1);
    return dut;
endmodule

interface TimingTester_ifc;
    method Bool done;
endinterface

module mkTimingTester#(TimingDut_ifc dut, String name, Integer latency)(TimingTester_ifc);
    Reg#(UInt#(32)) rg_cycle <- mkReg(0);

    Reg#(Bool)     rg_arvalid <- mkReg(False);
    Reg#(Bit#(32)) rg_araddr  <- mkReg(0);
    Reg#(Bool)     rg_rready  <- mkReg(True);
    Reg#(Bool)     rg_awvalid <- mkReg(False);
    Reg#(Bit#(32)) rg_awaddr  <- mkReg(0);
    Reg#(Bool)     rg_wvalid  <- mkReg(False);
    Reg#(Bit#(32)) rg_wdata   <- mkReg(0);
    Reg#(Bool)     rg_bready  <- mkReg(True);

    //cycle of the last request handshakes; used for latency checks
    Reg#(UInt#(32)) rg_ar_cycle <- mkReg(0);
    Reg#(UInt#(32)) rg_aw_cycle <- mkReg(0);
    Reg#(UInt#(32)) rg_w_cycle  <- mkReg(0);
    Reg#(Bool)      rg_check_latency <- mkReg(True);
    Reg#(Bool)      rg_rvalid_prev   <- mkReg(False);
    Reg#(Bool)      rg_bvalid_prev   <- mkReg(False);

    //previous-cycle response outputs for the stability checks
    Reg#(Bool)      rg_r_stalled <- mkReg(False);
    Reg#(Bit#(34))  rg_r_prev    <- mkReg(0);
    Reg#(Bool)      rg_b_stalled <- mkReg(False);
    Reg#(Bit#(2))   rg_b_prev    <- mkReg(0);

    FIFOF#(Tuple2#(Bit#(32), AXI4_Lite_Response)) f_r <- mkSizedFIFOF(4);
    FIFOF#(AXI4_Lite_Response)                    f_b <- mkSizedFIFOF(4);

    Reg#(Bool) rg_done <- mkReg(False);

    function Action fail(String msg) = action
        $display("[%s] cycle %0d: %s", name, rg_cycle, msg);
        $finish(1);
    endaction;

    function Action fail_value(String msg, Bit#(32) got, Bit#(32) expected) = action
        $display("[%s] cycle %0d: %s: got %08x, expected %08x", name, rg_cycle, msg, got, expected);
        $finish(1);
    endaction;

    rule r_drive;
        dut.s_rd.parvalid(rg_arvalid);
        dut.s_rd.paraddr(rg_araddr);
        dut.s_rd.parprot(unpack(0));
        dut.s_rd.prready(rg_rready);
        dut.s_wr.pawvalid(rg_awvalid);
        dut.s_wr.pawaddr(rg_awaddr);
        dut.s_wr.pawprot(unpack(0));
        dut.s_wr.pwvalid(rg_wvalid);
        dut.s_wr.pwdata(rg_wdata);
        dut.s_wr.pwstrb('hF);
        dut.s_wr.pbready(rg_bready);
    endrule

    rule r_cycle;
        rg_cycle <= rg_cycle + 1;
    endrule

    rule r_monitor;
        let cycle = rg_cycle;

        if(rg_arvalid && dut.s_rd.arready) begin
            rg_arvalid  <= False;
            rg_ar_cycle <= cycle;
        end
        if(rg_awvalid && dut.s_wr.awready) begin
            rg_awvalid  <= False;
            rg_aw_cycle <= cycle;
        end
        if(rg_wvalid && dut.s_wr.wready) begin
            rg_wvalid  <= False;
            rg_w_cycle <= cycle;
        end

        Bit#(34) r_now = {dut.s_rd.rdata, pack(dut.s_rd.rresp)};
        if(rg_r_stalled && (!dut.s_rd.rvalid || r_now != rg_r_prev))
            fail("R channel changed while stalled");
        rg_r_stalled <= dut.s_rd.rvalid && !rg_rready;
        rg_r_prev    <= r_now;

        Bit#(2) b_now = pack(dut.s_wr.bresp);
        if(rg_b_stalled && (!dut.s_wr.bvalid || b_now != rg_b_prev))
            fail("B channel changed while stalled");
        rg_b_stalled <= dut.s_wr.bvalid && !rg_bready;
        rg_b_prev    <= b_now;

        //latency runs from the request handshake to the cycle VALID rises
        rg_rvalid_prev <= dut.s_rd.rvalid;
        rg_bvalid_prev <= dut.s_wr.bvalid;
        if(rg_check_latency && dut.s_rd.rvalid && !rg_rvalid_prev
                && cycle - rg_ar_cycle != fromInteger(latency))
            fail_value("read latency", pack(cycle - rg_ar_cycle), fromInteger(latency));
        let request_cycle = max(rg_aw_cycle, rg_w_cycle);
        if(rg_check_latency && dut.s_wr.bvalid && !rg_bvalid_prev
                && cycle - request_cycle != fromInteger(latency))
            fail_value("write latency", pack(cycle - request_cycle), fromInteger(latency));

        if(dut.s_rd.rvalid && rg_rready)
            f_r.enq(tuple2(dut.s_rd.rdata, dut.s_rd.rresp));
        if(dut.s_wr.bvalid && rg_bready)
            f_b.enq(dut.s_wr.bresp);
    endrule

    function Action read(Bit#(32) addr) = action
        rg_arvalid <= True;
        rg_araddr  <= addr;
    endaction;

    function Action write(Bit#(32) addr, Bit#(32) data) = action
        rg_awvalid <= True;
        rg_awaddr  <= addr;
        rg_wvalid  <= True;
        rg_wdata   <= data;
    endaction;

    function Action expect_read(Bit#(32) data, AXI4_Lite_Response resp) = action
        match {.d, .r} = f_r.first;
        f_r.deq;
        if(d != data)
            fail_value("read data", d, data);
        if(r != resp)
            fail_value("read response", zeroExtend(pack(r)), zeroExtend(pack(resp)));
    endaction;

    function Action expect_write(AXI4_Lite_Response resp) = action
        f_b.deq;
        if(f_b.first != resp)
            fail_value("write response", zeroExtend(pack(f_b.first)), zeroExtend(pack(resp)));
    endaction;

    Stmt s = seq
        //single accesses: response exactly `latency` cycles after the handshake
        read('h00);
        expect_read('hCAFE0001, OKAY);
        write('h04, 'h12345678);
        expect_write(OKAY);
        read('h04);
        expect_read('h12345678, OKAY);
        read('h40);
        expect_read(0, DECERR);

        //AW and W on different cycles; latency counts from the later one
        action rg_awvalid <= True; rg_awaddr <= 'h04; endaction
        repeat(2) noAction;
        action rg_wvalid <= True; rg_wdata <= 'hAAAA0001; endaction
        expect_write(OKAY);
        action rg_wvalid <= True; rg_wdata <= 'hBBBB0002; endaction
        repeat(2) noAction;
        action rg_awvalid <= True; rg_awaddr <= 'h04; endaction
        expect_write(OKAY);

        //backpressure: responses stay valid and stable
        action read('h04); rg_rready <= False; endaction
        repeat(4) noAction;
        rg_rready <= True;
        expect_read('hBBBB0002, OKAY);
        action write('h04, 'hCCCC0003); rg_bready <= False; endaction
        repeat(4) noAction;
        rg_bready <= True;
        expect_write(OKAY);

        //a read and a write in the same cycle: the read is served first
        //the write waits for the read, so its latency is not checked here
        rg_check_latency <= False;
        action read('h04); write('h04, 'hDDDD0004); endaction
        expect_read('hCCCC0003, OKAY);
        expect_write(OKAY);
        read('h04);
        expect_read('hDDDD0004, OKAY);

        //back-to-back reads
        read('h00);
        await(!rg_arvalid);
        read('h04);
        await(!rg_arvalid);
        read('h00);
        expect_read('hCAFE0001, OKAY);
        expect_read('hDDDD0004, OKAY);
        expect_read('hCAFE0001, OKAY);

        rg_done <= True;
    endseq;

    FSM fsm <- mkFSM(s);
    Reg#(Bool) rg_started <- mkReg(False);

    rule r_start if(!rg_started);
        fsm.start;
        rg_started <= True;
    endrule

    method done = rg_done;
endmodule

module [Module] mkTestAXIAdapterTiming(Empty);
    TimingDut_ifc dut0 <- mkTimingDut0;
    TimingDut_ifc dut1 <- mkTimingDut1;

    TimingTester_ifc t0 <- mkTimingTester(dut0, "buffer 0", 1);
    TimingTester_ifc t1 <- mkTimingTester(dut1, "buffer 1", 2);

    Reg#(UInt#(16)) rg_timeout <- mkReg(0);

    rule r_timeout;
        rg_timeout <= rg_timeout + 1;
        if(rg_timeout == 2000) begin
            $display("AXI adapter timing TB timed out");
            $finish(1);
        end
    endrule

    rule r_finish if(t0.done && t1.done);
        $display("Finished AXI adapter timing TB");
        $finish(0);
    endrule
endmodule

endpackage
