package BlueCSRSoC;

import DefaultValue  :: *;
import List          :: *;
import ModuleCollect :: *;
import Vector        :: *;

import AhbSlave               :: *;
import ApbSlave               :: *;
import Axi4Lite               :: *;
import BlueAddrMap            :: *;
import BlueCSRAHBAdapter      :: *;
import BlueCSRAPBAdapter      :: *;
import BlueCSRAXI4LiteAdapter :: *;
import BlueCSRCore            :: *;
import BlueCSRExport          :: *;

/* bus adapters */

//connects a CSR core to the bus port type of an address map, the port type selects the protocol
//instances pass the low caw address bits to the core, which the range check of the export relies on
typeclass BlueCSRAdapter#(type endpoint, numeric type caw, numeric type dw, type cfg)
        dependencies((endpoint, caw) determines (dw, cfg));
    module mkBlueCSRAdapter#(cfg c, BlueCSR_ifc#(caw, dw, ni) csr)(endpoint);
endtypeclass

typedef struct {
    Bool pipeline_request;    //registers the request, which cuts the bus path into the CSR core
} BlueCSRAPBAdapterCfg_t deriving(Bits, Eq, FShow);

instance DefaultValue#(BlueCSRAPBAdapterCfg_t);
    defaultValue = BlueCSRAPBAdapterCfg_t { pipeline_request: True };
endinstance

instance BlueCSRAdapter#(ApbSlaveFabric_ifc#(aw, dw, uw), caw, dw, BlueCSRAPBAdapterCfg_t)
    provisos(
        Add#(caw, 0, aw)
    );
    module mkBlueCSRAdapter#(BlueCSRAPBAdapterCfg_t c, BlueCSR_ifc#(caw, dw, ni) csr)(ApbSlaveFabric_ifc#(aw, dw, uw));
        BlueCSR_APB_ifc#(aw, dw, uw, ni) i_apb <- mkBlueCSRAPBAdapter(csr, c.pipeline_request);
        return i_apb.s_apb;
    endmodule
endinstance

typedef struct {
    Bool pipeline_request;    //registers the request, which cuts the bus path into the CSR core
} BlueCSRAHBAdapterCfg_t deriving(Bits, Eq, FShow);

instance DefaultValue#(BlueCSRAHBAdapterCfg_t);
    defaultValue = BlueCSRAHBAdapterCfg_t { pipeline_request: True };
endinstance

instance BlueCSRAdapter#(AhbSlaveFabric_ifc#(aw, dw), caw, dw, BlueCSRAHBAdapterCfg_t)
    provisos(
        Add#(caw, 0, aw)
    );
    module mkBlueCSRAdapter#(BlueCSRAHBAdapterCfg_t c, BlueCSR_ifc#(caw, dw, ni) csr)(AhbSlaveFabric_ifc#(aw, dw));
        BlueCSR_AHB_ifc#(aw, dw, ni) i_ahb <- mkBlueCSRAHBAdapter(csr, c.pipeline_request);
        return i_ahb.s_ahb;
    endmodule
endinstance

typedef struct {
    Integer rd_buffer;    //read request buffer depth, zero passes requests straight through
    Integer wr_buffer;    //write request buffer depth, zero passes requests straight through
} BlueCSRAXI4LiteAdapterCfg_t;

instance DefaultValue#(BlueCSRAXI4LiteAdapterCfg_t);
    defaultValue = BlueCSRAXI4LiteAdapterCfg_t {
        rd_buffer: 1,
        wr_buffer: 1
    };
endinstance

//the core may decode fewer address bits than the bus carries, its map then repeats every 2 ** caw bytes
instance BlueCSRAdapter#(Axi4LiteSlaveFab_ifc#(aw, dw), caw, dw, BlueCSRAXI4LiteAdapterCfg_t)
    provisos(
        Add#(caw, unused_addr_bits, aw)
    );
    module mkBlueCSRAdapter#(BlueCSRAXI4LiteAdapterCfg_t c, BlueCSR_ifc#(caw, dw, ni) csr)(Axi4LiteSlaveFab_ifc#(aw, dw));
        BlueCSR_AXI4Lite_ifc#(aw, dw, ni) i_axi <- mkBlueCSRAXI4LiteAdapter(csr, c.rd_buffer, c.wr_buffer);
        return axi4_lite_slave_fab(i_axi.s_rd, i_axi.s_wr);
    endmodule
endinstance

/* address map targets */

//software view of a register map for the address map export, blocks count with their declared size
function AddrMapTargetDoc_t blue_csr_target_doc(Integer span, List#(RegMapEntry_t#(aw, dw)) entries);
    let     regdefs    = List::concat(List::map(get_reg_def, entries));
    let     regiondefs = List::concat(List::map(get_reg_region_def, entries));
    let     blockdefs  = List::concat(List::map(get_reg_block_def, entries));
    Integer first      = span;
    Integer limit      = 0;

    for(Integer i = 0; i < List::length(regdefs); i = i + 1) begin
        first = min(first, regdefs[i].offset);
        limit = max(limit, regdefs[i].offset + valueOf(TDiv#(dw, 8)));
    end
    for(Integer i = 0; i < List::length(regiondefs); i = i + 1) begin
        first = min(first, regiondefs[i].offset);
        limit = max(limit, regiondefs[i].offset + regiondefs[i].length);
    end
    for(Integer i = 0; i < List::length(blockdefs); i = i + 1) begin
        first = min(first, blockdefs[i].offset);
        limit = max(limit, blockdefs[i].offset + blockdefs[i].length);
    end

    return AddrMapTargetDoc_t {
        span:      span,
        first:     first,
        limit:     limit,
        systemrdl: render_blue_csr_systemrdl(entries)
    };
endfunction

interface BlueCSRTarget_ifc#(numeric type ni, type ifc);
    method Vector#(ni, Bool) irqs;
    interface ifc internal;
endinterface

/*
 * A register map as one address map target. The CSR core and the SystemRDL export use the same collected
 * definitions, so the export needs nothing beyond the map itself. The bus fails to build when the register
 * map does not fit the window.
 *
 * csr_addr_map_target picks the adapter from the bus port type and uses default configurations,
 * csr_addr_map_target_cfg takes both configurations. csr_addr_map_target_with takes the endpoint module
 * instead, e.g. for a cut or a clock crossing in front of the core. That module has to pass the low csr_aw
 * address bits to the core like the adapters do.
 */
module [AddrMapCtx_t#(bus_aw, endpoint)] csr_addr_map_target_with#(
    Integer base, Integer size, String name,
    BlueCSRCtx_t#(csr_aw, dw, ifc) ctx, BlueCSRCfg_t cfg,
    function Module#(endpoint) mk_endpoint(BlueCSR_ifc#(csr_aw, dw, ni) csr)
)(BlueCSRTarget_ifc#(ni, ifc));
    match {.device, .entries} <- liftModule(getCollection(ctx));

    BlueCSRAccess_ifc#(csr_aw, dw, ni, ifc) i_csr      <- liftModule(create_blue_csr_from_entries(device, entries, cfg));
    endpoint                                i_endpoint <- liftModule(mk_endpoint(i_csr.external));
    addr_map_target_doc(base, size, name, blue_csr_target_doc(2 ** valueOf(csr_aw), entries), i_endpoint);

    method    irqs     = i_csr.external.irqs;
    interface internal = i_csr.internal;
endmodule

module [AddrMapCtx_t#(bus_aw, endpoint)] csr_addr_map_target_cfg#(
    Integer base, Integer size, String name,
    BlueCSRCtx_t#(csr_aw, dw, ifc) ctx, BlueCSRCfg_t cfg, adapter_cfg acfg
)(BlueCSRTarget_ifc#(ni, ifc))
    provisos(
        BlueCSRAdapter#(endpoint, csr_aw, dw, adapter_cfg)
    );
    function Module#(endpoint) mk_endpoint(BlueCSR_ifc#(csr_aw, dw, ni) csr) = mkBlueCSRAdapter(acfg, csr);

    BlueCSRTarget_ifc#(ni, ifc) i_target <- csr_addr_map_target_with(base, size, name, ctx, cfg, mk_endpoint);
    return i_target;
endmodule

module [AddrMapCtx_t#(bus_aw, endpoint)] csr_addr_map_target#(
    Integer base, Integer size, String name, BlueCSRCtx_t#(csr_aw, dw, ifc) ctx
)(BlueCSRTarget_ifc#(ni, ifc))
    provisos(
        BlueCSRAdapter#(endpoint, csr_aw, dw, adapter_cfg),
        DefaultValue#(adapter_cfg)
    );
    BlueCSRTarget_ifc#(ni, ifc) i_target <- csr_addr_map_target_cfg(base, size, name, ctx, defaultValue, defaultValue);
    return i_target;
endmodule

endpackage
