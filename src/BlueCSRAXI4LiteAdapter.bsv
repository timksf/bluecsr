package BlueCSRAXI4LiteAdapter;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;

import BlueAXI :: *;
import BlueCSRCore :: *;

interface BlueCSR_AXI4Lite_ifc#(numeric type aw, numeric type dw, numeric type ni);
    interface AXI4_Lite_Slave_Rd_Fab#(aw, dw) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(aw, dw) s_wr;
    (* always_ready *)
    method Vector#(ni, Bool) irqs;
endinterface

function BlueCSRProt_t axi_lite_to_bluecsr_prot(AXI4_Lite_Prot prot);
    Bit#(3) prot_bits = pack(prot);
    return (prot_bits[1] == 1'b1) ? CSR_INSECURE : CSR_SECURE;
endfunction

function AXI4_Lite_Response bluecsr_to_axi_lite_resp(BlueCSRResponse_t resp);
    return case (resp)
        CSR_OKAY: OKAY;
        CSR_EXOKAY: EXOKAY;
        CSR_SLVERR: SLVERR;
        CSR_DECERR: DECERR;
    endcase;
endfunction

/*
 * One transaction is in flight at a time; reads win over writes
 *
 * AR, AW and W each own a one-entry holding register, so READY only depends
 * on adapter state. A buffer value of 0 lets an idle adapter pass a request
 * from the bus straight to the CSR core; the response is then valid in the
 * next cycle. A value above 0 always registers the request first, which cuts
 * the bus-to-decode path and adds one cycle. Responses are always registered.
 *
 * The CSR core may decode fewer address bits (caw) than the bus carries (aw).
 * Upper address bits are dropped, so the register map repeats every 2^caw
 * bytes and the interconnect has to decode them.
 */
module mkBlueCSRAXI4LiteAdapter#(BlueCSR_ifc#(caw, dw, ni) csr, Integer axi4_rd_buffer, Integer axi4_wr_buffer)(BlueCSR_AXI4Lite_ifc#(aw, dw, ni))
    provisos(
        Add#(caw, unused_addr_bits, aw)
    );

    let reset_asserted <- isResetAsserted();

    Bool rd_direct = axi4_rd_buffer == 0;
    Bool wr_direct = axi4_wr_buffer == 0;

    Wire#(Bool)                      w_arvalid <- mkBypassWire;
    Wire#(Bit#(caw))                 w_araddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)            w_arprot  <- mkBypassWire;
    Wire#(Bool)                      w_rready  <- mkBypassWire;
    Wire#(Bool)                      w_awvalid <- mkBypassWire;
    Wire#(Bit#(caw))                 w_awaddr  <- mkBypassWire;
    Wire#(AXI4_Lite_Prot)            w_awprot  <- mkBypassWire;
    Wire#(Bool)                      w_wvalid  <- mkBypassWire;
    Wire#(Bit#(dw))                  w_wdata   <- mkBypassWire;
    Wire#(Bit#(TDiv#(dw, 8)))        w_wstrb   <- mkBypassWire;
    Wire#(Bool)                      w_bready  <- mkBypassWire;

    Reg#(Bool)                       rg_ar_full <- mkReg(False);
    Reg#(Bit#(caw))                  rg_ar_addr <- mkRegU;
    Reg#(AXI4_Lite_Prot)             rg_ar_prot <- mkRegU;
    Reg#(Bool)                       rg_aw_full <- mkReg(False);
    Reg#(Bit#(caw))                  rg_aw_addr <- mkRegU;
    Reg#(AXI4_Lite_Prot)             rg_aw_prot <- mkRegU;
    Reg#(Bool)                       rg_w_full  <- mkReg(False);
    Reg#(Bit#(dw))                   rg_w_data  <- mkRegU;
    Reg#(Bit#(TDiv#(dw, 8)))         rg_w_strb  <- mkRegU;

    //set when a request enters the CSR core, cleared by the R or B handshake
    Reg#(Bool)                       rg_busy     <- mkReg(False);
    Reg#(Bool)                       rg_rsp_wr   <- mkRegU;
    Reg#(Bool)                       rg_rsp_full <- mkReg(False);
    Reg#(Bit#(dw))                   rg_rdata    <- mkRegU;
    Reg#(BlueCSRResponse_t)          rg_resp     <- mkRegU;

    PulseWire pw_issue_rd <- mkPulseWire;
    PulseWire pw_issue_wr <- mkPulseWire;
    PulseWire pw_complete <- mkPulseWire;

    Bool ar_ready = !reset_asserted && !rg_ar_full;
    Bool aw_ready = !reset_asserted && !rg_aw_full;
    Bool w_ready  = !reset_asserted && !rg_w_full;
    Bool rvalid   = !reset_asserted && rg_rsp_full && !rg_rsp_wr;
    Bool bvalid   = !reset_asserted && rg_rsp_full && rg_rsp_wr;

    Bool ar_fire = ar_ready && w_arvalid;
    Bool aw_fire = aw_ready && w_awvalid;
    Bool w_fire  = w_ready  && w_wvalid;

    Bool rd_avail = rg_ar_full || (rd_direct && ar_fire);
    Bool aw_avail = rg_aw_full || (wr_direct && aw_fire);
    Bool w_avail  = rg_w_full  || (wr_direct && w_fire);

    Bool issue_rd = !rg_busy && rd_avail;
    Bool issue_wr = !rg_busy && !rd_avail && aw_avail && w_avail;

    rule r_issue if(issue_rd || issue_wr);
        BlueCSR_Req_t#(caw, dw) req = ?;
        if(issue_rd) begin
            req = BlueCSR_Req_t {
                wr:    False,
                addr:  rg_ar_full ? rg_ar_addr : w_araddr,
                wdata: ?,
                wstrb: ?,
                prot:  axi_lite_to_bluecsr_prot(rg_ar_full ? rg_ar_prot : w_arprot)
            };
            pw_issue_rd.send;
        end else begin
            req = BlueCSR_Req_t {
                wr:    True,
                addr:  rg_aw_full ? rg_aw_addr : w_awaddr,
                wdata: rg_w_full ? rg_w_data : w_wdata,
                wstrb: rg_w_full ? rg_w_strb : w_wstrb,
                prot:  axi_lite_to_bluecsr_prot(rg_aw_full ? rg_aw_prot : w_awprot)
            };
            pw_issue_wr.send;
        end
        csr.request.put(req);
        rg_rsp_wr <= !issue_rd;
    endrule

    //store accepted requests that did not go straight to the CSR core
    rule r_hold;
        if(rg_ar_full) begin
            if(pw_issue_rd) rg_ar_full <= False;
        end else if(ar_fire && !pw_issue_rd) begin
            rg_ar_full <= True;
            rg_ar_addr <= w_araddr;
            rg_ar_prot <= w_arprot;
        end

        if(rg_aw_full) begin
            if(pw_issue_wr) rg_aw_full <= False;
        end else if(aw_fire && !pw_issue_wr) begin
            rg_aw_full <= True;
            rg_aw_addr <= w_awaddr;
            rg_aw_prot <= w_awprot;
        end

        if(rg_w_full) begin
            if(pw_issue_wr) rg_w_full <= False;
        end else if(w_fire && !pw_issue_wr) begin
            rg_w_full <= True;
            rg_w_data <= w_wdata;
            rg_w_strb <= w_wstrb;
        end
    endrule

    rule r_response(!rg_rsp_full);
        let rsp <- csr.response.get;
        rg_rdata    <= rsp.rdata;
        rg_resp     <= rsp.resp;
        rg_rsp_full <= True;
    endrule

    rule r_complete((rvalid && w_rready) || (bvalid && w_bready));
        rg_rsp_full <= False;
        pw_complete.send;
    endrule

    rule r_busy;
        if(pw_issue_rd || pw_issue_wr)
            rg_busy <= True;
        else if(pw_complete)
            rg_busy <= False;
    endrule

    interface AXI4_Lite_Slave_Rd_Fab s_rd;
        method arready  = ar_ready;
        method parvalid = w_arvalid._write;
        method Action paraddr(Bit#(aw) a);
            w_araddr <= truncate(a);
        endmethod
        method parprot  = w_arprot._write;
        method rvalid   = rvalid;
        method prready  = w_rready._write;
        method rdata    = rg_rdata;
        method rresp    = bluecsr_to_axi_lite_resp(rg_resp);
    endinterface

    interface AXI4_Lite_Slave_Wr_Fab s_wr;
        method awready  = aw_ready;
        method pawvalid = w_awvalid._write;
        method Action pawaddr(Bit#(aw) a);
            w_awaddr <= truncate(a);
        endmethod
        method pawprot  = w_awprot._write;
        method wready   = w_ready;
        method pwvalid  = w_wvalid._write;
        method pwdata   = w_wdata._write;
        method pwstrb   = w_wstrb._write;
        method bvalid   = bvalid;
        method pbready  = w_bready._write;
        method bresp    = bluecsr_to_axi_lite_resp(rg_resp);
    endinterface

    method irqs = csr.irqs;
endmodule

endpackage
