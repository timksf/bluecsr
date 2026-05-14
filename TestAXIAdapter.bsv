package TestAXIAdapter;

import StmtFSM :: *;
import RegFile :: *;
import Connectable :: *;

import BlueAXI :: *;

import BlueCSR :: *;

import TestBlueCSR :: *;

module [Module] mkTestAXIAdapter(Empty);

    let cfg <- mk_config;
    let axi_cfg <- mkBlueCSRAXI4LiteAdapter(cfg.external, 1, 1);

    AXI4_Lite_Master_Rd#(32, 32) m_rd <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(32, 32) m_wr <- mkAXI4_Lite_Master_Wr(1);

    Reg#(Bit#(32)) rg_addr <- mkReg(0);
    Reg#(Bit#(32)) rg_data <- mkReg(0);

    mkConnection(m_rd.fab, axi_cfg.s_rd);
    mkConnection(m_wr.fab, axi_cfg.s_wr);

    Stmt s = seq
        axi4_lite_read(m_rd, 'h00);
        action
            let r <- axi4_lite_read_response(m_rd);
            $display("Read %08x", r);
        endaction
    endseq;

    mkAutoFSM(s);

endmodule

endpackage