package TestBlueCSRCounter;

import GetPut :: *;
import List :: *;
import ModuleCollect :: *;
import StmtFSM :: *;

import BlueCSRCore :: *;
import BlueCSRValidation :: *;

interface CounterTest_ifc;
    method Action pulse;
    method Action run(Bool enabled);
    method Action add(UInt#(16) amount);
endinterface

module [BlueCSRCtx_t#(8, 32)] counter_test_map(CounterTest_ifc);
    PulseWire                pw_pulse <- mkPulseWire;
    Reg#(Bool)               rg_run   <- mkReg(False);
    Wire#(Maybe#(UInt#(16))) w_add    <- mkDWire(tagged Invalid);

    csr_regmap_def("CounterTest", "Counter and accumulator fields");

    csr_reg_def('h00, "EVENTS", "Pulse counter and free running counter");
    let _events <- csr_reg_counter   ('h00, UInt#(16)'(0),        0, pw_pulse, "PULSES", "Pulses", "Counts pulses, writable.");
    let _cycles <- csr_reg_counter   ('h00, UInt#(16)'(5),       16, rg_run,   "CYCLES", "Cycles", "Counts every cycle while running, writable.");

    csr_reg_def('h04, "RO", "Hardware owned counter");
    let _ro     <- csr_reg_counter_ro('h04, UInt#(32)'(0),        0, pw_pulse, "COUNT",  "Count",  "Counts pulses, read only.");

    csr_reg_def('h08, "SUM", "Accumulator");
    let _sum    <- csr_reg_accumulate('h08, UInt#(16)'('hfff0), 0, w_add,    "SUM",    "Sum",    "Adds amounts, wraps.");

    method Action pulse = pw_pulse.send;
    method Action run(Bool enabled);
        rg_run <= enabled;
    endmethod
    method Action add(UInt#(16) amount);
        w_add <= tagged Valid amount;
    endmethod
endmodule

(* synthesize *)
module [Module] mkTestBlueCSRCounter(Empty);
    BlueCSRAccess_ifc#(8, 32, 0, CounterTest_ifc) i_csr     <- create_blue_csr(counter_test_map, False);
    Reg#(Bit#(32))                                rg_value  <- mkReg(0);
    Reg#(UInt#(16))                               rg_cycles <- mkReg(0);

    let {_, entries} <- getCollection(counter_test_map);
    let validation = validate_blue_csr_entries(entries);
    let fields     = List::concat(List::map(get_regfield_def, entries));
    if(!validation.valid) errorM(validation.errors);
    if(length(fields) != 4 || fields[0].access_type != CSR_RW || fields[2].access_type != CSR_RO ||
       fields[1].reset_value != "0x5" || fields[3].width != 16) begin
        errorM("Counter metadata does not match the declared fields.");
    end

    function Stmt access(Bool wr, Bit#(8) addr, Bit#(32) data, Bit#(4) strb, BlueCSRResponse_t expected_resp);
        return seq
            i_csr.external.request.put(BlueCSR_Req_t { wr: wr, addr: addr, wdata: data, wstrb: strb, prot: CSR_SECURE });
            action
                let rsp <- i_csr.external.response.get;
                rg_value <= rsp.rdata;
                if(rsp.resp != expected_resp) begin
                    $display("FAIL: wr=%0d addr=%h response %h", wr, addr, pack(rsp.resp));
                    $finish(1);
                end
            endaction
        endseq;
    endfunction

    function Action check(Bit#(32) expected, String what);
        action
            if(rg_value != expected) begin
                $display("FAIL: %s expected %h got %h", what, expected, rg_value);
                $finish(1);
            end
        endaction
    endfunction

    Stmt test = seq
        access(False, 'h00, 0, 0, CSR_OKAY);
        check('h00050000, "reset values");

        repeat(3) i_csr.internal.pulse;
        access(False, 'h00, 0, 0, CSR_OKAY);
        check('h00050003, "three pulses");
        access(False, 'h04, 0, 0, CSR_OKAY);
        check(3, "read only copy");

        //byte strobes: only the low half (PULSES) is written
        access(True, 'h00, 'hffff0010, 'b0011, CSR_OKAY);
        access(False, 'h00, 0, 0, CSR_OKAY);
        check('h00050010, "strobed preset");

        //read only counters reject writes and keep counting
        access(True, 'h04, 'h1234, 'hf, CSR_DECERR);
        i_csr.internal.pulse;
        access(False, 'h04, 0, 0, CSR_OKAY);
        check(4, "read only after rejected write");

        //a counter that counts every cycle can still be cleared
        i_csr.internal.run(True);
        delay(20);
        access(True, 'h00, 'h00000010, 'b1100, CSR_OKAY);
        access(False, 'h00, 0, 0, CSR_OKAY);
        i_csr.internal.run(False);
        action
            UInt#(16) cycles = unpack(rg_value[31:16]);
            if(cycles == 0 || cycles > 8) begin
                $display("FAIL: clear lost under continuous events, cycles=%0d", cycles);
                $finish(1);
            end
        endaction

        //accumulator adds amounts and wraps
        i_csr.internal.add(8);
        i_csr.internal.add(10);
        access(False, 'h08, 0, 0, CSR_OKAY);
        check('h00000002, "accumulator wrap");
        access(True, 'h08, 'h100, 'hf, CSR_OKAY);
        i_csr.internal.add(1);
        access(False, 'h08, 0, 0, CSR_OKAY);
        check('h00000101, "accumulator preset");

        $display("PASS: counter and accumulator fields");
        $finish(0);
    endseq;
    mkAutoFSM(test);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 2000) begin
            $display("FAIL: counter test timed out");
            $finish(1);
        end
    endrule
endmodule

endpackage
