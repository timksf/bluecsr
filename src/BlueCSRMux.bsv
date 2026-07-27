package BlueCSRMux;

import FIFOF :: *;
import GetPut :: *;
import List :: *;
import SpecialFIFOs :: *;
import Vector :: *;

import BlueCSRCore :: *;

typedef struct {
    Bit#(aw) base;
    Bit#(aw) mask;
} BlueCSRSubmap_t#(numeric type aw) deriving(Bits, Eq, FShow);

// Route one transaction at a time to a child CSR map. A child matches when
// (address & mask) == (base & mask), and receives an address relative to base.
// If windows overlap, the lowest vector index has priority. Requests and
// responses are routed directly. The response FIFO is fall-through: it stores
// a response only when the upstream consumer applies backpressure.
module mkBlueCSRMux#(Vector#(n, BlueCSRSubmap_t#(aw)) submaps, Vector#(n, BlueCSR_ifc#(aw, dw, ni)) children)(BlueCSR_ifc#(aw, dw, ni))
    provisos(Add#(1, n_minus_one, n));

    FIFOF#(BlueCSR_Rsp_t#(dw)) responses <- mkBypassFIFOF;
    Reg#(Bool) pending[2] <- mkCReg(2, False);

    function Bool submap_hit(BlueCSR_Req_t#(aw, dw) req, Integer index);
        let window = submaps[index];
        return (req.addr & window.mask) == (window.base & window.mask);
    endfunction

    Rules response_rules = emptyRules;
    for (Integer i = 0; i < valueOf(n); i = i + 1) begin
        response_rules = rJoinMutuallyExclusive(response_rules, rules
            rule route_child_response;
                let rsp <- children[i].response.get;
                responses.enq(rsp);
                pending[1] <= False;
            endrule
        endrules);
    end
    addRules(response_rules);

    interface Put request;
        method Action put(BlueCSR_Req_t#(aw, dw) req) if(!pending[0] && responses.notFull);
            action
                Bool mapped = False;
                Bool earlier_hit = False;
                for (Integer i = 0; i < valueOf(n); i = i + 1) begin
                    Bool hit = submap_hit(req, i);
                    if(hit && !earlier_hit) begin
                        let window = submaps[i];
                        let local_req = req;
                        local_req.addr = req.addr - window.base;
                        children[i].request.put(local_req);
                        mapped = True;
                    end
                    earlier_hit = earlier_hit || hit;
                end
                if(mapped) begin
                    pending[0] <= True;
                end
                else begin
                    responses.enq(BlueCSR_Rsp_t { rdata: 0, resp: CSR_DECERR });
                end
            endaction
        endmethod
    endinterface

    interface response = toGet(responses);

    method Vector#(ni, Bool) irqs;
        Vector#(ni, Bool) result = replicate(False);
        for (Integer i = 0; i < valueOf(n); i = i + 1) begin
            for (Integer j = 0; j < valueOf(ni); j = j + 1) begin
                result[j] = result[j] || children[i].irqs[j];
            end
        end
        return result;
    endmethod
endmodule

endpackage
