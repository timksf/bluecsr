package BlueCSRFabricMap;

import Connectable :: *;
import List        :: *;
import Vector      :: *;

import AddrMapDecoder :: *;
import BlueAddrMap    :: *;

// Renderers receive the visible interval in the target's address space.
// address_offset converts a target address into its output address space.
typedef struct {
    function String _(String path,   Integer address_offset, Integer first, Integer limit) markdown;
    function String _(String indent, Integer address_offset, Integer first, Integer limit) systemrdl;
} FabricDocContent_t;

typedef struct {
    AddrMapRegion_t    window;
    Integer            target_offset;
    String             name;
    FabricDocContent_t content;
} FabricDocEntry_t;

typedef struct {
    String                 name;
    Integer                size;
    List#(FabricDocEntry_t) entries;
} FabricMapDoc_t;

typedef struct {
    endpoint           port;
    FabricDocContent_t content;
} FabricDocTarget_t#(type endpoint);

typedef AddrMapCtx_t#(aw, FabricDocTarget_t#(endpoint), ifc)
    FabricMapCtx_t#(numeric type aw, type endpoint, type ifc);

function String fabric_doc_empty(String label, Integer address_offset, Integer first, Integer limit) = "";
FabricDocContent_t empty_fabric_doc = FabricDocContent_t {
    markdown:  fabric_doc_empty,
    systemrdl: fabric_doc_empty
};

function Ordering fabric_doc_compare(FabricDocEntry_t a, FabricDocEntry_t b);
    if(a.window.is_default != b.window.is_default) return a.window.is_default ? GT : LT;
    else return compare(a.window.base, b.window.base);
endfunction

function String render_fabric_map_markdown(
    FabricMapDoc_t doc, String path, Integer address_offset, Integer first, Integer limit
);
    String title        = path == "" ? "# " + doc.name : "## " + path;
    String window_table = title + "\n\n| Base | End | Target |\n| --- | --- | --- |\n";
    String details      = "";
    for(Integer i = 0; i < List::length(doc.entries); i = i + 1) begin
        let entry  = doc.entries[i];
        let window = entry.window;

        String  target        = path == "" ? entry.name : path + "." + entry.name;
        Integer base          = max(first, window.base);
        Integer end_exclusive = min(limit, window.base + window.size);
        if(window.is_default)
            window_table = window_table + "| default | | " + target + " |\n";
        else if(base < end_exclusive) begin
            window_table = window_table + "| 0x" + addr_map_integer_to_hex(base + address_offset)
                + " | 0x" + addr_map_integer_to_hex(end_exclusive + address_offset - 1)
                + " | " + target + " |\n";
            let section = entry.content.markdown(target, address_offset + entry.target_offset,
                base - entry.target_offset, end_exclusive - entry.target_offset);
            if(section != "") details = details + "\n" + section;
        end
    end
    return window_table + details;
endfunction

function String doc_fabric_map_markdown(FabricMapDoc_t doc);
    return render_fabric_map_markdown(doc, "", 0, 0, doc.size);
endfunction

function String render_fabric_map_systemrdl(
    FabricMapDoc_t doc, String indent, Integer address_offset, Integer first, Integer limit
);
    String text = "";
    for(Integer i = 0; i < List::length(doc.entries); i = i + 1) begin
        let entry  = doc.entries[i];
        let window = entry.window;

        Integer base          = max(first, window.base);
        Integer end_exclusive = min(limit, window.base + window.size);
        if(!window.is_default && base < end_exclusive) begin
            // Child instances are relative to this addrmap, even when the bus
            // passes segment addresses through to the downstream endpoint.
            let body = entry.content.systemrdl(indent + "  ", entry.target_offset - base,
                base - entry.target_offset, end_exclusive - entry.target_offset);
            String placement = " \\" + entry.name + " @ 0x" + addr_map_integer_to_hex(base + address_offset) + ";\n";
            if(body != "")
                text = text + indent + "addrmap {\n" + body + indent + "}" + placement;
            else
                // Describe the aperture without inferring the endpoint's layout or access.
                text = text + indent + "external mem {\n"
                    + indent + "  desc = \"Fabric address window. Endpoint layout and access are unspecified.\";\n"
                    + indent + "  mementries = " + integerToString(end_exclusive - base) + ";\n"
                    + indent + "  memwidth = 8;\n" + indent + "  sw = na;\n"
                    + indent + "}" + placement;
        end
    end
    return text;
endfunction

function String doc_fabric_map_systemrdl(FabricMapDoc_t doc);
    return "addrmap soc {\n" + render_fabric_map_systemrdl(doc, "  ", 0, 0, doc.size) + "};\n";
endfunction

module [FabricMapCtx_t#(aw, endpoint)] fabric_target#(
    Integer base, Integer size, String name, endpoint port
)(Empty);
    fabric_target_with_content(base, size, name, port, empty_fabric_doc);
endmodule

module [FabricMapCtx_t#(aw, endpoint)] fabric_target_with_content#(
    Integer base, Integer size, String name, endpoint port, FabricDocContent_t content
)(Empty);
    addr_map_target(base, size, name, FabricDocTarget_t { port: port, content: content });
endmodule

module [Module] collect_and_build_fabric#(
    AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg,
    FabricMapCtx_t#(aw, endpoint, ifc) ctx
)(Tuple2#(
    AddrMapBus_ifc#(n, endpoint, ifc),
    AddrMapCollected_t#(n, FabricDocTarget_t#(endpoint), ifc)
))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint)
    );

    AddrMapCollected_t#(n, FabricDocTarget_t#(endpoint), ifc) collected <- collect_addr_map(ctx);
    function endpoint get_port(FabricDocTarget_t#(endpoint) target) = target.port;

    AddrMapCollected_t#(n, endpoint, ifc) physical_map = AddrMapCollected_t {
        name    : collected.name,
        regions : collected.regions,
        names   : collected.names,
        targets : Vector::map(get_port, collected.targets),
        internal: collected.internal
    };
    AddrMapBus_ifc#(n, endpoint, ifc) i_bus <- mkAddrMapBus(cfg, physical_map);

    return tuple2(i_bus, collected);
endmodule

function FabricMapDoc_t describe_fabric(
    AddrMapCollected_t#(n, FabricDocTarget_t#(endpoint), ifc) collected,
    Integer address_space, Bool local_addr
);
    List#(FabricDocEntry_t) entries = Nil;
    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        let window = collected.regions[i];
        entries = Cons(FabricDocEntry_t {
            window       : window,
            target_offset: local_addr && !window.is_default ? window.base : 0,
            name         : collected.names[i],
            content      : collected.targets[i].content
        }, entries);
    end
    return FabricMapDoc_t {
        name   : collected.name,
        size   : address_space,
        entries: List::sortBy(fabric_doc_compare, entries)
    };
endfunction

module [Module] create_fabric#(
    AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg,
    FabricMapCtx_t#(aw, endpoint, ifc) ctx
)(AddrMapBus_ifc#(n, endpoint, ifc))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint)
    );

    match {.i_bus, .*} <- collect_and_build_fabric(cfg, ctx);
    return i_bus;
endmodule

module [Module] create_fabric_with_map#(
    AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg,
    FabricMapCtx_t#(aw, endpoint, ifc) ctx
)(Tuple2#(AddrMapBus_ifc#(n, endpoint, ifc), FabricMapDoc_t))
    provisos(
        AddrMapFabric#(endpoint, port, r, aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, endpoint)
    );

    match {.i_bus, .collected} <- collect_and_build_fabric(cfg, ctx);
    return tuple2(i_bus, describe_fabric(collected, 2 ** valueOf(aw), cfg.local_addr));
endmodule

module [FabricMapCtx_t#(aw, endpoint)] fabric_bridge#(
    Integer base, Integer size, String name,
    AddrMapBusCfg_t#(router_cfg, cut_cfg) cfg,
    FabricMapCtx_t#(sub_aw, sub_endpoint, ifc) sub
)(AddrMapSubBus_ifc#(n, ifc))
    provisos(
        AddrMapFabric#(sub_endpoint, port, r, sub_aw, router_cfg, cut_cfg),
        AddrMapCutCfg#(cut_cfg),
        Connectable#(port, sub_endpoint),
        AddrMapBridge#(endpoint, sub_endpoint)
    );

    match {.i_bus, .collected} <- liftModule(collect_and_build_fabric(cfg, sub));

    AddrMapBus_ifc#(n, sub_endpoint, ifc) i_child  =  i_bus;
    endpoint                              i_bridge <- liftModule(mkAddrMapBridge(i_child.up));

    // The downstream, static address map is consumed by the export renderers.
    let doc = describe_fabric(collected, 2 ** valueOf(sub_aw), cfg.local_addr);
    fabric_target_with_content(base, size, name, i_bridge, FabricDocContent_t {
        markdown:  render_fabric_map_markdown(doc),
        systemrdl: render_fabric_map_systemrdl(doc)
    });
    interface internal = i_child.internal;
endmodule

endpackage
