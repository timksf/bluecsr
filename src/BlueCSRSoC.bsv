package BlueCSRSoC;

import List          :: *;
import ModuleCollect :: *;
import Vector        :: *;

import BlueCSRCore      :: *;
import BlueCSRExport    :: *;
import BlueCSRFabricMap :: *;

function FabricDocContent_t blue_csr_fabric_doc(List#(RegMapEntry_t#(aw, dw)) entries);
    function String markdown(String path, Integer address_offset, Integer first, Integer limit);
        return "## " + path + "\n\n" + render_blue_csr_markdown(entries, address_offset, first, limit);
    endfunction

    return FabricDocContent_t {
        markdown:  markdown,
        systemrdl: render_blue_csr_systemrdl(entries)
    };
endfunction

interface BlueCSRFabricTarget_ifc#(numeric type ni, type ifc);
    method Vector#(ni, Bool) irqs;
    interface ifc internal;
endinterface

module [FabricMapCtx_t#(bus_aw, endpoint)] bluecsr_fabric_target#(
    Integer base, Integer size, String name,
    BlueCSRCtx_t#(csr_aw, dw, ifc) ctx, BlueCSRCfg_t cfg,
    function Module#(endpoint) mk_endpoint(BlueCSR_ifc#(csr_aw, dw, ni) csr)
)(BlueCSRFabricTarget_ifc#(ni, ifc));

    match {.device, .entries} <- liftModule(getCollection(ctx));

    BlueCSRAccess_ifc#(csr_aw, dw, ni, ifc) i_csr      <- liftModule(create_blue_csr_from_entries(device, entries, cfg));
    endpoint                                i_endpoint <- liftModule(mk_endpoint(i_csr.external));
    fabric_target_with_content(base, size, name, i_endpoint, blue_csr_fabric_doc(entries));

    method    irqs     = i_csr.external.irqs;
    interface internal = i_csr.internal;
endmodule

endpackage
