package TestBlueCSRServer;

import BRAM :: *;
import ClientServer :: *;
import DefaultValue :: *;
import FIFOF :: *;
import GetPut :: *;
import List :: *;
import ModuleCollect :: *;
import StmtFSM :: *;

import BlueCSRCore :: *;
import BlueCSRValidation :: *;

interface ServerTest_ifc;
    method Action enable(Bool value);
endinterface

//three cycle server: echoes the local address and request fields, SLVERR for writes of 'hbad
module mkSlowServer(Server#(BlueCSR_Req_t#(16, 32), BlueCSR_Rsp_t#(32)));
    FIFOF#(BlueCSR_Req_t#(16, 32)) f_req   <- mkSizedFIFOF(1);
    FIFOF#(BlueCSR_Rsp_t#(32))     f_rsp   <- mkSizedFIFOF(1);
    Reg#(UInt#(2))                 rg_wait <- mkReg(0);

    rule r_serve;
        if(rg_wait == 2) begin
            let req = f_req.first;
            f_req.deq;
            f_rsp.enq(BlueCSR_Rsp_t { rdata: req.wr ? 0 : {16'h5e00, req.addr}, resp: req.wr && req.wdata == 'hbad ? CSR_SLVERR : CSR_OKAY });
            rg_wait <= 0;
        end
        else rg_wait <= rg_wait + 1;
    endrule

    interface request  = toPut(f_req);
    interface response = toGet(f_rsp);
endmodule

module [BlueCSRCtx_t#(16, 32)] server_test_map(ServerTest_ifc);
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = 64;
    cfg.latency    = 2;

    BRAM1Port#(UInt#(6), Bit#(16))                      i_ram     <- mkBRAM1Server(cfg);
    Server#(BlueCSR_Req_t#(16, 32), BlueCSR_Rsp_t#(32)) i_slow    <- mkSlowServer;
    Reg#(Bool)                                          rg_enable <- mkReg(True);

    csr_regmap_def("ServerTest", "Server backed regions");
    csr_reg_def('h00, "ID", "Identifier");
    csr_reg_rc('h00, Bit#(32)'('h12345678), 0, "VALUE", "Value", "Constant.");

    csr_region_bram('h100, 'h100, rg_enable, CSR_SLVERR, i_ram.portA, "RAM", "16 bit elements, one per word");
    csr_region_server('h200, 'h40, True, CSR_SLVERR, i_slow, "SLOW", "Echo server with three cycles latency");
    csr_region_prot('h200, 'h40, CSR_SEC_SECURE_ONLY, CSR_ALLOW_ALL);

    method Action enable(Bool value);
        rg_enable <= value;
    endmethod
endmodule

module [Module] mkServerTest#(Bool buffer_in)(ReadOnly#(Bool));
    BlueCSRAccess_ifc#(16, 32, 0, ServerTest_ifc) i_csr   <- create_blue_csr(server_test_map, buffer_in);
    Reg#(Bool)                                    rg_done <- mkReg(False);
    Reg#(UInt#(8))                                rg_i    <- mkReg(0);

    function Action request(Bool wr, Bit#(16) addr, Bit#(32) data, Bit#(4) strb, BlueCSRProt_t prot) =
        i_csr.external.request.put(BlueCSR_Req_t { wr: wr, addr: addr, wdata: data, wstrb: strb, prot: prot });

    function Action check_response(Bit#(32) data, BlueCSRResponse_t resp);
        action
            let rsp <- i_csr.external.response.get;
            if(rsp.rdata != data || rsp.resp != resp) begin
                $display("FAIL: buffer=%0d expected=%h/%h got=%h/%h", buffer_in, data, pack(resp), rsp.rdata, pack(rsp.resp));
                $finish(1);
            end
        endaction
    endfunction

    function Stmt access(Bool wr, Bit#(16) addr, Bit#(32) data, Bit#(4) strb, BlueCSRProt_t prot, Bit#(32) expected, BlueCSRResponse_t resp);
        return seq
            request(wr, addr, data, strb, prot);
            check_response(expected, resp);
        endseq;
    endfunction

    Stmt test = seq
        access(True,  'h104, 'habcd1234, 'hf, CSR_SECURE, 0, CSR_OKAY);
        access(False, 'h104, 0, 0, CSR_SECURE, 'h1234, CSR_OKAY);
        access(False, 'h000, 0, 0, CSR_SECURE, 'h12345678, CSR_OKAY);
        //partial element strobes are rejected, empty strobes are a no-op
        access(True,  'h104, 'h5555, 1, CSR_SECURE, 0, CSR_SLVERR);
        access(True,  'h104, 'h5555, 4, CSR_SECURE, 0, CSR_OKAY);
        access(False, 'h104, 0, 0, CSR_SECURE, 'h1234, CSR_OKAY);
        //unaligned accesses never reach the server
        access(False, 'h106, 0, 0, CSR_SECURE, 0, CSR_DECERR);
        //fill and read back the whole region
        for(rg_i <= 0; rg_i < 64; rg_i <= rg_i + 1)
            access(True, 'h100 + 4 * zeroExtend(pack(rg_i)), 'hfff0 ^ zeroExtend(pack(rg_i)), 3, CSR_SECURE, 0, CSR_OKAY);
        for(rg_i <= 0; rg_i < 64; rg_i <= rg_i + 1)
            access(False, 'h100 + 4 * zeroExtend(pack(rg_i)), 0, 0, CSR_SECURE, 'hfff0 ^ zeroExtend(pack(rg_i)), CSR_OKAY);
        i_csr.internal.enable(False);
        access(False, 'h104, 0, 0, CSR_SECURE, 0, CSR_SLVERR);
        access(True,  'h104, 1, 'hf, CSR_SECURE, 0, CSR_SLVERR);
        i_csr.internal.enable(True);
        access(False, 'h104, 0, 0, CSR_SECURE, 'hfff1, CSR_OKAY);
        //generic server: local address, errors and protection
        access(False, 'h23c, 0, 0, CSR_SECURE, 'h5e00003c, CSR_OKAY);
        access(True,  'h204, 'hbad, 'hf, CSR_SECURE, 0, CSR_SLVERR);
        access(False, 'h204, 0, 0, CSR_INSECURE, 0, CSR_DECERR);
        access(True,  'h204, 1, 'hf, CSR_INSECURE, 0, CSR_OKAY);
        //a stalled response holds later requests back and keeps order
        request(False, 'h208, 0, 0, CSR_SECURE);
        request(False, 'h000, 0, 0, CSR_SECURE);
        delay(10);
        check_response('h5e000008, CSR_OKAY);
        check_response('h12345678, CSR_OKAY);
        access(False, 'h400, 0, 0, CSR_SECURE, 0, CSR_DECERR);
        rg_done <= True;
    endseq;
    FSM        i_fsm      <- mkFSM(test);
    Reg#(Bool) rg_started <- mkReg(False);

    rule r_start (!rg_started);
        i_fsm.start;
        rg_started <= True;
    endrule

    method _read = rg_done;
endmodule

(* synthesize *)
module [Module] mkTestBlueCSRServer(Empty);
    ReadOnly#(Bool) i_unbuffered <- mkServerTest(False);
    ReadOnly#(Bool) i_buffered   <- mkServerTest(True);
    Reg#(UInt#(16)) rg_cycles    <- mkReg(0);

    let {_, entries} <- getCollection(server_test_map);
    let validation = validate_blue_csr_entries(entries);
    if(!validation.valid) errorM(validation.errors);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 5000) begin
            $display("FAIL: server region test timed out");
            $finish(1);
        end
    endrule
    rule r_finish (i_unbuffered && i_buffered);
        $display("PASS: server and BRAM regions: latency, ordering, strobes, readiness, alignment and permissions");
        $finish(0);
    endrule
endmodule

endpackage
