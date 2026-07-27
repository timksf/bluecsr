package BlueCSRAPBAdapter;

import GetPut :: *;
import Vector :: *;

import BlueFabric :: *;
import BlueCSRCore :: *;

(* always_enabled *)
interface BlueCSR_APB_ifc#(numeric type aw, numeric type dw, numeric type user_w, numeric type ni);
    interface ApbSlaveFabric_ifc#(aw, dw, user_w) s_apb;
    method Vector#(ni, Bool) irqs;
endinterface

function BlueCSRProt_t apb_to_bluecsr_prot(Bit#(3) protection);
    return (protection[1] == 1'b1) ? CSR_INSECURE : CSR_SECURE;
endfunction

function Bool bluecsr_to_apb_error(BlueCSRResponse_t response);
    return (response == CSR_SLVERR || response == CSR_DECERR);
endfunction

module mkBlueCSRAPBAdapter#(BlueCSR_ifc#(aw, dw, ni) csr, Bool pipeline_request)(BlueCSR_APB_ifc#(aw, dw, user_w, ni));

    ApbSlave_ifc#(aw, dw, user_w) i_apb <- mkApbSlave(pipeline_request);
    Reg#(Bool) rg_pending <- mkReg(False);

    rule r_issue_request if(!rg_pending);
        let request <- i_apb.request.get;
        csr.request.put(BlueCSR_Req_t {
            wr:    request.write,
            addr:  request.address,
            wdata: request.write_data,
            wstrb: request.write_strobe,
            prot:  apb_to_bluecsr_prot(request.protection)
        });
        rg_pending <= True;
    endrule

    rule r_complete_request if(rg_pending);
        let response <- csr.response.get;
        i_apb.response.put(ApbResponse_t {
            read_data:     response.rdata,
            slave_error:   bluecsr_to_apb_error(response.resp),
            read_user:     0,
            response_user: 0
        });
        rg_pending <= False;
    endrule

    interface s_apb = i_apb.fabric;
    method irqs = csr.irqs;
endmodule

endpackage
