package TestBlueCSRAct;

import FIFOF :: *;
import GetPut :: *;
import List :: *;
import ModuleCollect :: *;
import StmtFSM :: *;

import BlueCSRCore :: *;
import BlueCSRValidation :: *;

interface ActionTest_ifc;
    method Action supply(Bit#(32) data);
    method ActionValue#(Bit#(36)) consume;
    method Action enable_read(Bool enabled);
    method Bit#(8) reads;
    method Bit#(32) value;
endinterface

module [BlueCSRCtx_t#(8, 32)] action_test_map(ActionTest_ifc);
    FIFOF#(Bit#(32)) f_read  <- mkSizedFIFOF(1);
    FIFOF#(Bit#(36)) f_write <- mkSizedFIFOF(1);
    Reg#(Bool)      rg_read_enabled <- mkReg(True);
    Reg#(Bit#(8))   rg_reads        <- mkReg(0);
    Reg#(Bit#(32))  rg_value        <- mkReg('h12345678);

    function ActionValue#(BlueCSR_Rsp_t#(32)) read_fifo();
        actionvalue
            let data = f_read.first;
            f_read.deq;
            return BlueCSR_Rsp_t { rdata: data, resp: data == 'hbadf00d ? CSR_SLVERR : CSR_OKAY };
        endactionvalue
    endfunction

    function Bool can_write(Bit#(32) data, Bit#(4) strb);
        return strb[0] == 0 || data == 'hdeadbeef || f_write.notFull;
    endfunction

    function ActionValue#(BlueCSRResponse_t) write_fifo(Bit#(32) data, Bit#(4) strb);
        actionvalue
            if(strb[0] == 1 && data != 'hdeadbeef) f_write.enq({strb, data});
            return (strb[0] == 1 && data == 'hdeadbeef) ? CSR_SLVERR : CSR_OKAY;
        endactionvalue
    endfunction

    function ActionValue#(BlueCSR_Rsp_t#(32)) read_value();
        actionvalue
            rg_reads <= rg_reads + 1;
            return BlueCSR_Rsp_t { rdata: rg_value, resp: CSR_EXOKAY };
        endactionvalue
    endfunction

    function Bool value_available(Bit#(32) data, Bit#(4) strb) = True;

    function ActionValue#(BlueCSRResponse_t) write_value(Bit#(32) data, Bit#(4) strb);
        actionvalue
            if(data != 'hbad) begin
                Bit#(32) next_value = rg_value;
                for(Integer b = 0; b < 4; b = b + 1) begin
                    Bit#(32) mask = 32'hff << fromInteger(b * 8);
                    if(strb[b] == 1) next_value = (next_value & ~mask) | (data & mask);
                end
                rg_value <= next_value;
            end
            return data == 'hbad ? CSR_SLVERR : CSR_OKAY;
        endactionvalue
    endfunction

    csr_regmap_def("ActionTest", "Action access helpers");
    csr_reg_def('h00, "READ", "Guarded side-effecting read");
    csr_reg_act_ro('h00, Bit#(8)'(0), 8, f_read.notEmpty,
        BlueCSR_Rsp_t { rdata: 'hfeedface, resp: CSR_SLVERR }, read_fifo,
        "DATA", "Data", "Callback returns a complete bus word.");

    csr_reg_def('h04, "WRITE", "Guarded command write");
    csr_reg_act_wo('h04, Bit#(2)'(0), 0, can_write, CSR_SLVERR, write_fifo,
        "OP", "Operation", "Callback sees every bit and byte strobe.");

    csr_reg_def('h08, "RW", "Independent action read and write");
    csr_reg_act_rw('h08, Bit#(32)'('h12345678), 0, rg_read_enabled,
        BlueCSR_Rsp_t { rdata: 'hcafebabe, resp: CSR_DECERR }, read_value,
        value_available, CSR_SLVERR, write_value,
        "VALUE", "Value", "State is owned by the callbacks.");
    csr_reg_prot('h08, CSR_SEC_SECURE_ONLY, CSR_SEC_INSECURE_ONLY);

    method Action supply(Bit#(32) data) = f_read.enq(data);
    method ActionValue#(Bit#(36)) consume;
        f_write.deq;
        return f_write.first;
    endmethod
    method Action enable_read(Bool enabled);
        rg_read_enabled <= enabled;
    endmethod
    method reads = rg_reads;
    method value = rg_value;
endmodule

module [Module] mkActionTest#(Bool buffer_in)(ReadOnly#(Bool));
    BlueCSRAccess_ifc#(8, 32, 0, ActionTest_ifc) i_csr <- create_blue_csr(action_test_map, buffer_in);
    Reg#(Bool) rg_done <- mkReg(False);

    function Stmt access(Bool wr, Bit#(8) addr, Bit#(32) data, Bit#(4) strb, BlueCSRProt_t prot, Bit#(32) expected_data, BlueCSRResponse_t expected_resp);
        return seq
            i_csr.external.request.put(BlueCSR_Req_t {
                wr: wr, addr: addr, wdata: data, wstrb: strb, prot: prot
            });
            action
                let rsp <- i_csr.external.response.get;
                if(rsp.rdata != expected_data || rsp.resp != expected_resp) begin
                    $display("FAIL: buffer=%0d wr=%0d addr=%h data=%h strb=%h expected=%h/%h got=%h/%h",
                        buffer_in, wr, addr, data, strb, expected_data, pack(expected_resp), rsp.rdata, pack(rsp.resp));
                    $finish(1);
                end
            endaction
        endseq;
    endfunction

    Stmt test = seq
        // Unavailable guarded operations must respond without invoking methods.
        access(False, 'h00, 0, 0, CSR_SECURE, 'hfeedface, CSR_SLVERR);
        access(True,  'h00, 1, 'hf, CSR_SECURE, 0, CSR_DECERR);
        access(False, 'h04, 0, 0, CSR_SECURE, 0, CSR_DECERR);
        i_csr.internal.supply('h89abcdef);
        access(False, 'h00, 0, 0, CSR_SECURE, 'h89abcdef, CSR_OKAY);
        access(False, 'h00, 0, 0, CSR_SECURE, 'hfeedface, CSR_SLVERR);
        i_csr.internal.supply('hbadf00d);
        access(False, 'h00, 0, 0, CSR_SECURE, 'hbadf00d, CSR_SLVERR);
        access(False, 'h00, 0, 0, CSR_SECURE, 'hfeedface, CSR_SLVERR);

        access(True, 'h04, 'h12345678, 5, CSR_SECURE, 0, CSR_OKAY);
        access(True, 'h04, 'h98765432, 1, CSR_SECURE, 0, CSR_SLVERR);
        // Rejection and strobe no-ops remain available even with a full FIFO.
        access(True, 'h04, 'hdeadbeef, 'hf, CSR_SECURE, 0, CSR_SLVERR);
        access(True, 'h04, 'hffffffff, 2, CSR_SECURE, 0, CSR_OKAY);
        access(True, 'h04, 'hffffffff, 0, CSR_SECURE, 0, CSR_OKAY);
        action
            let data <- i_csr.internal.consume;
            if(data != 36'h512345678) begin
                $display("FAIL: action write data/strobes were altered");
                $finish(1);
            end
        endaction
        access(True, 'h04, 'hfedcba98, 1, CSR_SECURE, 0, CSR_OKAY);
        action
            let data <- i_csr.internal.consume;
            if(data != 36'h1fedcba98) $finish(1);
        endaction

        access(False, 'h08, 0, 0, CSR_SECURE, 'h12345678, CSR_EXOKAY);
        access(False, 'h08, 0, 0, CSR_INSECURE, 0, CSR_DECERR);
        access(True, 'h08, 'hffffffff, 'hf, CSR_SECURE, 0, CSR_DECERR);
        access(True, 'h08, 'habcdef00, 6, CSR_INSECURE, 0, CSR_OKAY);
        access(False, 'h08, 0, 0, CSR_SECURE, 'h12cdef78, CSR_EXOKAY);
        access(True, 'h08, 'hbad, 'hf, CSR_INSECURE, 0, CSR_SLVERR);
        i_csr.internal.enable_read(False);
        access(False, 'h08, 0, 0, CSR_SECURE, 'hcafebabe, CSR_DECERR);
        action
            if(i_csr.internal.reads != 2 || i_csr.internal.value != 'h12cdef78) begin
                $display("FAIL: rejected access invoked a callback");
                $finish(1);
            end
        endaction
        // Read readiness does not gate the independent write direction.
        access(True, 'h08, 'h55, 1, CSR_INSECURE, 0, CSR_OKAY);
        i_csr.internal.enable_read(True);

        // A held response must not cause the side effect to repeat.
        i_csr.external.request.put(BlueCSR_Req_t {
            wr: False, addr: 'h08, wdata: 0, wstrb: 0, prot: CSR_SECURE
        });
        delay(8);
        action
            if(i_csr.internal.reads != 3) begin
                $display("FAIL: read callback repeated while response was stalled");
                $finish(1);
            end
            let rsp <- i_csr.external.response.get;
            if(rsp.rdata != 'h12cdef55 || rsp.resp != CSR_EXOKAY) $finish(1);
        endaction
        access(False, 'h0c, 0, 0, CSR_SECURE, 0, CSR_DECERR);
        access(False, 'h09, 0, 0, CSR_SECURE, 0, CSR_DECERR);
        rg_done <= True;
    endseq;
    mkAutoFSM(test);
    method _read = rg_done;
endmodule

// Also elaborate a narrower bus with a field ending at the top bus bit.
module [BlueCSRCtx_t#(8, 16)] action_narrow_map(Empty);
    function ActionValue#(BlueCSR_Rsp_t#(16)) read_fn();
        actionvalue
            return BlueCSR_Rsp_t { rdata: 'habcd, resp: CSR_OKAY };
        endactionvalue
    endfunction
    function Bool can_write(Bit#(16) data, Bit#(2) strb) = True;
    function ActionValue#(BlueCSRResponse_t) write_fn(Bit#(16) data, Bit#(2) strb);
        actionvalue
            return CSR_OKAY;
        endactionvalue
    endfunction
    csr_regmap_def("NarrowActionTest", "16-bit action access");
    csr_reg_def(0, "RW", "16-bit access");
    csr_reg_act_rw(0, Bit#(8)'('hab), 8, True,
        BlueCSR_Rsp_t { rdata: 0, resp: CSR_SLVERR }, read_fn,
        can_write, CSR_SLVERR, write_fn, "DATA", "Data", "Upper byte metadata.");
endmodule

(* synthesize *)
module [Module] mkTestBlueCSRAct(Empty);
    ReadOnly#(Bool) i_unbuffered <- mkActionTest(False);
    ReadOnly#(Bool) i_buffered   <- mkActionTest(True);
    BlueCSRAccess_ifc#(8, 16, 0, Empty) i_narrow <- create_blue_csr(action_narrow_map, False);
    Reg#(UInt#(16)) rg_cycles <- mkReg(0);

    let {_, entries} <- getCollection(action_test_map);
    let validation = validate_blue_csr_entries(entries);
    let fields = List::concat(List::map(get_regfield_def, entries));
    if(!validation.valid) errorM(validation.errors);
    if(length(fields) != 3 || fields[0].access_type != CSR_RO || fields[0].width != 8 || fields[0].bit_offset != 8 ||
       fields[1].access_type != CSR_WO || fields[1].width != 2 ||
       fields[2].access_type != CSR_RW || fields[2].reset_value != "0x12345678") begin
        errorM("Action helper metadata does not match the declared fields.");
    end

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 1000) begin
            $display("FAIL: action helper test timed out");
            $finish(1);
        end
    endrule
    rule r_finish (i_unbuffered && i_buffered);
        $display("PASS: action RO/WO/RW readiness, errors, strobes, permissions, metadata and response stalls");
        $finish(0);
    endrule
endmodule

endpackage
