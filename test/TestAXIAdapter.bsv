package TestAXIAdapter;

import StmtFSM :: *;
import RegFile :: *;
import Connectable :: *;
import GetPut :: *;

import BlueAXI :: *;

import BlueCSR :: *;

import TestBlueCSR :: *;

module [Module] mkTestAXIAdapter(Empty);

    let cfg <- mk_config;
    let axi_cfg <- mkBlueCSRAXI4LiteAdapter(cfg.external, 1, 1);

    AXI4_Lite_Master_Rd#(32, 32) m_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) m_wr <- mkAXI4_Lite_Master_Wr(1);

    mkConnection(m_rd.fab, axi_cfg.s_rd);
    mkConnection(m_wr.fab, axi_cfg.s_wr);

    Stmt s = seq
        axi4_lite_read(m_rd, 'h00);
        action
            let r <- m_rd.response.get;
            if(r.data != 'h0DDA0ABC || r.resp != OKAY) begin
                $display("AXI adapter read mismatch: %08x/%0d", r.data, r.resp);
                $finish(1);
            end
        endaction

        axi4_lite_write(m_wr, 'h04, 'h1);
        action
            let r <- axi4_lite_write_response(m_wr);
            if(r != OKAY) begin
                $display("AXI adapter write response mismatch: %0d", r);
                $finish(1);
            end
        endaction

        axi4_lite_read(m_rd, 'h0C);
        action
            let r <- m_rd.response.get;
            if(r.resp != SLVERR) begin
                $display("AXI adapter did not propagate SLVERR: %0d", r.resp);
                $finish(1);
            end
        endaction

        axi4_lite_read(m_rd, 'h80);
        action
            let r <- m_rd.response.get;
            if(r.data != 0 || r.resp != DECERR) begin
                $display("AXI adapter decode response mismatch: %08x/%0d", r.data, r.resp);
                $finish(1);
            end
        endaction

        $display("Finished AXI adapter TB");
        $finish(0);
    endseq;

    mkAutoFSM(s);

endmodule

endpackage
