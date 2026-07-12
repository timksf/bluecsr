package TestBlueCSRMux;

import StmtFSM :: *;
import Vector :: *;

import BlueCSR :: *;

module [BlueCSRCtx_t#(16, 32)] mux_child_ro(Empty);
    csr_regmap_def("muxChildRo", "Read-only mux child");
    csr_reg_def('h00, "ID", "Child identifier");
    csr_reg_rc('h00, Bit#(16)'('hCAFE), 0, "VALUE", "Value", "Constant child value.");
endmodule

module [BlueCSRCtx_t#(16, 32)] mux_child_rw(Empty);
    csr_regmap_def("muxChildRw", "Read-write mux child");
    csr_reg_def('h04, "DATA", "Child data");
    Reg#(Bit#(32)) _data <- csr_reg_rw('h04, 0, 0, "VALUE", "Value", "Read-write child value.");
endmodule

(* synthesize *)
module mkTestBlueCSRMux(Empty);
    let child_ro <- create_blue_csr(mux_child_ro, False);
    let child_rw <- create_blue_csr(mux_child_rw, False);
    let flat_ro <- create_blue_csr(mux_child_ro, False);

    Vector#(2, BlueCSRSubmap_t#(16)) submaps = newVector;
    submaps[0] = BlueCSRSubmap_t { base: 'h1000, mask: 'hFF00 };
    submaps[1] = BlueCSRSubmap_t { base: 'h2000, mask: 'hFF00 };
    Vector#(2, BlueCSR_ifc#(16, 32)) children = newVector;
    children[0] = child_ro.external;
    children[1] = child_rw.external;
    BlueCSR_ifc#(16, 32) csr <- mkBlueCSRMux(submaps, children);

    Reg#(UInt#(32)) cycle <- mkReg(0);
    Reg#(UInt#(32)) mux_response_cycle <- mkReg(0);
    Reg#(UInt#(32)) flat_response_cycle <- mkReg(0);
    Reg#(Bool) latency_request_sent <- mkReg(False);
    Reg#(Bool) mux_response_seen <- mkReg(False);
    Reg#(Bool) flat_response_seen <- mkReg(False);

    rule count_cycles;
        cycle <= cycle + 1;
    endrule

    rule issue_latency_requests (!latency_request_sent);
        issue_read(csr, 'h1000, CSR_SECURE);
        issue_read(flat_ro.external, 'h00, CSR_SECURE);
        latency_request_sent <= True;
    endrule

    rule receive_mux_latency (!mux_response_seen);
        let rsp <- accept_read_response(csr);
        if(tpl_1(rsp) != 'hCAFE || tpl_2(rsp) != CSR_OKAY) begin
            $display("Mux latency-check read mismatch");
            $finish(1);
        end
        mux_response_cycle <= cycle;
        mux_response_seen <= True;
    endrule

    rule receive_flat_latency (!flat_response_seen);
        let rsp <- accept_read_response(flat_ro.external);
        if(tpl_1(rsp) != 'hCAFE || tpl_2(rsp) != CSR_OKAY) begin
            $display("Flat latency-check read mismatch");
            $finish(1);
        end
        flat_response_cycle <= cycle;
        flat_response_seen <= True;
    endrule

    function Action expect_read(Bit#(32) expected_data, BlueCSRResponse_t expected_resp);
        action
            let rsp <- accept_read_response(csr);
            if(tpl_1(rsp) != expected_data || tpl_2(rsp) != expected_resp) begin
                $display("Mux read mismatch: expected %08x/%0d, got %08x/%0d", expected_data, expected_resp, tpl_1(rsp), tpl_2(rsp));
                $finish(1);
            end
        endaction
    endfunction

    Stmt test = seq
        await(mux_response_seen && flat_response_seen);
        action
            if(mux_response_cycle != flat_response_cycle) begin
                $display("Mux added latency: flat=%0d mux=%0d", flat_response_cycle, mux_response_cycle);
                $finish(1);
            end
        endaction

        issue_write(csr, 'h2004, 'h12345678, 4'b1111, CSR_INSECURE);
        expect_write_okay(csr);
        issue_read(csr, 'h2004, CSR_INSECURE);
        expect_read('h12345678, CSR_OKAY);

        issue_read(csr, 'h3000, CSR_INSECURE);
        expect_read(0, CSR_DECERR);

        $display("Finished BlueCSR mux TB");
        $finish(0);
    endseq;

    mkAutoFSM(test);
endmodule

endpackage
