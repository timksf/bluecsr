package BlueCSRAxiLiteAdapter;

import GetPut :: *;

import BlueAXI :: *;
import BlueCSR :: *;

typedef enum {
    CSR_AXI_LITE_IDLE,
    CSR_AXI_LITE_READ_ISSUED,
    CSR_AXI_LITE_WRITE_ISSUED
} BlueCSRAxiLiteState_t deriving(Bits, Eq, FShow);

interface BlueCSRAxiLite_ifc#(numeric type aw, numeric type dw);
    interface AXI4_Lite_Slave_Rd_Fab#(aw, dw) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(aw, dw) s_wr;
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

function Action drive_bluecsr_idle(BlueCSR_ifc#(aw, dw) csr);
    action
        csr.valid(0);
        csr.wr(0);
        csr.addr(0);
        csr.wdata(0);
        csr.wstrb(0);
        csr.prot(CSR_SECURE);
    endaction
endfunction

// BlueCSR returns its response in the cycle after the request has been driven.
// We only accept a new read or write when that AXI-Lite response channel is empty,
// so the wrapper FIFO can hold the response and no extra pending state is needed.
(* descending_urgency = "capture_read, capture_write, start_write, start_read" *)
module mkBlueCSRAxiLiteAdapter#(
    BlueCSR_ifc#(aw, dw) csr,
    Integer read_slave_buffer,
    Integer write_slave_buffer
)(BlueCSRAxiLite_ifc#(aw, dw));

    AXI4_Lite_Slave_Rd#(aw, dw) read_slave <- mkAXI4_Lite_Slave_Rd(read_slave_buffer);
    AXI4_Lite_Slave_Wr#(aw, dw) write_slave <- mkAXI4_Lite_Slave_Wr(write_slave_buffer);

    Reg#(BlueCSRAxiLiteState_t) rg_state <- mkReg(CSR_AXI_LITE_IDLE);

    rule start_read ((rg_state == CSR_AXI_LITE_IDLE) && (csr.ready == 1'b1) && !read_slave.fab.rvalid);
        let req <- read_slave.request.get();

        csr.valid(1);
        csr.wr(0);
        csr.addr(req.addr);
        csr.wdata(0);
        csr.wstrb(0);
        csr.prot(axi_lite_to_bluecsr_prot(req.prot));

        rg_state <= CSR_AXI_LITE_READ_ISSUED;
    endrule

    rule capture_read (rg_state == CSR_AXI_LITE_READ_ISSUED);
        AXI4_Lite_Read_Rs_Pkg#(dw) resp = ?;
        resp.data = csr.rdata;
        resp.resp = bluecsr_to_axi_lite_resp(csr.resp);

        read_slave.response.put(resp);
        drive_bluecsr_idle(csr);
        rg_state <= CSR_AXI_LITE_IDLE;
    endrule

    rule start_write ((rg_state == CSR_AXI_LITE_IDLE) && (csr.ready == 1'b1) && !write_slave.fab.bvalid);
        let req <- write_slave.request.get();

        csr.valid(1);
        csr.wr(1);
        csr.addr(req.addr);
        csr.wdata(req.data);
        csr.wstrb(req.strb);
        csr.prot(axi_lite_to_bluecsr_prot(req.prot));

        rg_state <= CSR_AXI_LITE_WRITE_ISSUED;
    endrule

    rule capture_write (rg_state == CSR_AXI_LITE_WRITE_ISSUED);
        AXI4_Lite_Write_Rs_Pkg resp = ?;
        resp.resp = bluecsr_to_axi_lite_resp(csr.resp);

        write_slave.response.put(resp);
        drive_bluecsr_idle(csr);
        rg_state <= CSR_AXI_LITE_IDLE;
    endrule

    interface s_rd = read_slave.fab;
    interface s_wr = write_slave.fab;
endmodule

endpackage