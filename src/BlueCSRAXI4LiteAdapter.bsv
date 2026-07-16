package BlueCSRAXI4LiteAdapter;

import GetPut :: *;

import BlueAXI :: *;
import BlueCSRCore :: *;

interface BlueCSR_AXI4Lite_ifc#(numeric type aw, numeric type dw, numeric type ni);
    interface AXI4_Lite_Slave_Rd_Fab#(aw, dw) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(aw, dw) s_wr;
    interface IRQLines_ifc#(ni) irqs;
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

module mkBlueCSRAXI4LiteAdapter#(BlueCSR_ifc#(aw, dw, ni) csr, Integer axi4_rd_buffer, Integer axi4_wr_buffer)(BlueCSR_AXI4Lite_ifc#(aw, dw, ni));

    AXI4_Lite_Slave_Rd#(aw, dw) axi4l_rd <- mkAXI4_Lite_Slave_Rd(axi4_rd_buffer);
    AXI4_Lite_Slave_Wr#(aw, dw) axi4l_wr <- mkAXI4_Lite_Slave_Wr(axi4_wr_buffer);

    Reg#(Bool) rg_rd_pending <- mkReg(False);
    Reg#(Bool) rg_wr_pending <- mkReg(False);

    //favor read requests for now
    (*descending_urgency="rread_req, rwrite_req"*)
    (*mutually_exclusive="rread_rsp, rwrite_rsp"*)

    rule rread_req if(!rg_rd_pending && !rg_wr_pending);
        let axi_req <- axi4l_rd.request.get;
        csr.request.put(
            BlueCSR_Req_t {
                wr:     False,
                addr:   axi_req.addr,
                wdata:  ?,
                wstrb:  ?,
                prot:   axi_lite_to_bluecsr_prot(axi_req.prot)
            }
        );
        rg_rd_pending <= True;
    endrule

    rule rread_rsp if(rg_rd_pending);
        let csr_rsp <- csr.response.get;
        axi4l_rd.response.put(
            AXI4_Lite_Read_Rs_Pkg {
                data: csr_rsp.rdata,
                resp: bluecsr_to_axi_lite_resp(csr_rsp.resp)
            }
        );
        rg_rd_pending <= False;
    endrule

    rule rwrite_req if(!rg_rd_pending && !rg_wr_pending);
        let axi_req <- axi4l_wr.request.get;
        csr.request.put(
            BlueCSR_Req_t {
                wr:     True,
                addr:   axi_req.addr,
                wdata:  axi_req.data,
                wstrb:  axi_req.strb,
                prot:   axi_lite_to_bluecsr_prot(axi_req.prot)
            }
        );
        rg_wr_pending <= True;
    endrule

    rule rwrite_rsp if(rg_wr_pending);
        let csr_rsp <- csr.response.get;
        axi4l_wr.response.put(
            AXI4_Lite_Write_Rs_Pkg {
                resp: bluecsr_to_axi_lite_resp(csr_rsp.resp)
            }
        );
        rg_wr_pending <= False;
    endrule


    interface s_rd = axi4l_rd.fab;
    interface s_wr = axi4l_wr.fab;
    interface irqs = csr.irqs;
endmodule

endpackage
