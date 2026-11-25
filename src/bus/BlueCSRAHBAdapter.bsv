package BlueCSRAHBAdapter;

import GetPut :: *;
import Vector :: *;

import Ahb         :: *;
import AhbSlave    :: *;
import BlueCSRCore :: *;

interface BlueCSR_AHB_ifc#(numeric type aw, numeric type dw, numeric type ni);
    interface AhbSlaveFabric_ifc#(aw, dw) s_ahb;
    method Vector#(ni, Bool) irqs;
endinterface

//AHB carries write data on the byte lanes of the addressed bytes, so the lanes follow from size and address
function Bit#(sw) ahb_to_bluecsr_strobe(Bit#(aw) address, AhbSize_t size);
    Integer  lanes = valueOf(sw);
    Bit#(sw) mask  = 0;
    for(Integer s = 0; s < 8; s = s + 1)
        if(pack(size) == fromInteger(s)) mask = fromInteger(2 ** min(2 ** s, lanes) - 1);
    return mask << (address & fromInteger(lanes - 1));
endfunction

//AHB-Lite has no security attribute, so every access counts as secure
module mkBlueCSRAHBAdapter#(BlueCSR_ifc#(aw, dw, ni) csr, Bool pipeline_request)(BlueCSR_AHB_ifc#(aw, dw, ni));

    AhbSlave_ifc#(aw, dw) i_ahb      <- mkAhbSlave(pipeline_request);
    Reg#(Bool)            rg_pending <- mkReg(False);

    rule r_issue_request if(!rg_pending);
        let request <- i_ahb.request.get;
        csr.request.put(BlueCSR_Req_t {
            wr:    request.write,
            addr:  request.address,
            wdata: request.write_data,
            wstrb: ahb_to_bluecsr_strobe(request.address, request.size),
            prot:  CSR_SECURE
        });
        rg_pending <= True;
    endrule

    rule r_complete_request if(rg_pending);
        let response <- csr.response.get;
        i_ahb.response.put(AhbResponse_t {
            read_data:   response.rdata,
            slave_error: response.resp == CSR_SLVERR || response.resp == CSR_DECERR
        });
        rg_pending <= False;
    endrule

    interface s_ahb = i_ahb.fabric;
    method irqs = csr.irqs;
endmodule

endpackage
