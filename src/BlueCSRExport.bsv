package BlueCSRExport;

import List :: *;
import ModuleCollect :: *;

import BlueCSRCore :: *;
import BlueCSRValidation :: *;

module [Module] doc_blue_csr#(BlueCSRCtx_t#(aw, dw, i) ctx)(RegMapDoc_t#(dw));

    let {_, c} <- getCollection(ctx);
    let validation  = validate_blue_csr_entries(c);
    let blockdefs   = List::concat(List::map(get_reg_block_def, c));
    let regdefs     = List::concat(List::map(get_reg_def, c));
    let regiondefs  = List::concat(List::map(get_reg_region_def, c));
    let regfields   = List::concat(List::map(get_regfield_def, c));

    if(!validation.valid) begin
        errorM(validation.errors);
    end

    function String repeatString(String value, Integer count);
        if(count <= 0) return "";
        else return value + repeatString(value, count - 1);
    endfunction

    function String repeatSpaces(Integer count);
        return repeatString(" ", count);
    endfunction

    function String padLeftWith(String value, Integer width, String fill);
        Integer padding = width - stringLength(value);
        return repeatString(fill, padding) + value;
    endfunction

    function String padRight(String value, Integer width);
        Integer padding = width - stringLength(value);
        return value + repeatSpaces(padding);
    endfunction

    function String padLeft(String value, Integer width);
        return padLeftWith(value, width, " ");
    endfunction

    function String padInteger(Integer value, Integer width);
        return padLeftWith(integerToString(value), width, "0");
    endfunction

    function String fieldBits(RegFieldDef_t rf);
        Integer msb = rf.bit_offset + rf.width - 1;
        return "[" + padInteger(msb, 2) + ":" + padInteger(rf.bit_offset, 2) + "]";
    endfunction

    function String fieldReset(RegFieldDef_t rf);
        return "reset=" + rf.reset_value;
    endfunction

    function String fieldAccess(RegFieldDef_t rf);
        case (rf.access_type)
            CSR_RW:  return "RW";
            CSR_RO:  return "RO";
            CSR_RC:  return "RC";
            CSR_WC:  return "WC";
            CSR_WS:  return "WS";
            CSR_WO:  return "WO";
            CSR_W1S: return "W1S";
            CSR_W1C: return "W1C";
        endcase
    endfunction

    function Integer regOffsetWidth(RegDef_t regdef);
        return stringLength(integerToHex(regdef.offset));
    endfunction

    function Integer regionAddressWidth(RegRegionDef_t regiondef);
        Integer end_offset = regiondef.offset + regiondef.length - 1;
        return max(stringLength(integerToHex(regiondef.offset)), stringLength(integerToHex(end_offset)));
    endfunction

    function Integer addressWidth();
        Integer reg_width    = List::foldr(max, 1, List::map(regOffsetWidth, regdefs));
        Integer region_width = List::foldr(max, 1, List::map(regionAddressWidth, regiondefs));
        return max(reg_width, region_width);
    endfunction

    function String formatAddress(Integer value);
        return "0x" + padLeftWith(integerToHex(value), addressWidth(), "0");
    endfunction

    function Integer regIdentifierWidth(RegDef_t regdef);
        return stringLength(regdef.identifier);
    endfunction

    function Integer fieldIdentifierWidth(RegFieldDef_t rf);
        return stringLength(rf.identifier);
    endfunction

    function Integer fieldBitsWidth(RegFieldDef_t rf);
        return stringLength(fieldBits(rf));
    endfunction

    function Integer fieldResetWidth(RegFieldDef_t rf);
        return stringLength(fieldReset(rf));
    endfunction

    function Integer fieldAccessWidth(RegFieldDef_t rf);
        return stringLength(fieldAccess(rf));
    endfunction

    function String doc_reg(RegDef_t regdef);
        Integer reg_identifier_width    = List::foldr(max, 0, List::map(regIdentifierWidth, regdefs));
        Integer field_identifier_width  = List::foldr(max, 0, List::map(fieldIdentifierWidth, regfields));
        Integer field_bits_width        = List::foldr(max, 0, List::map(fieldBitsWidth, regfields));
        Integer field_access_width      = List::foldr(max, 0, List::map(fieldAccessWidth, regfields));
        Integer field_reset_width       = List::foldr(max, 0, List::map(fieldResetWidth, regfields));
        String  field_doc               = "";
        for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
            let rf = regfields[fi];
            if(rf.offset == regdef.offset) begin
                String bits   = fieldBits(rf);
                String access = fieldAccess(rf);
                String reset  = fieldReset(rf);
                field_doc = field_doc + "\n  "
                    + padRight(rf.identifier, field_identifier_width)
                    + "  "
                    + padRight(bits, field_bits_width)
                    + "  "
                    + padRight(access, field_access_width)
                    + "  "
                    + padRight(reset, field_reset_width)
                    + "  "
                    + rf.description;
            end
        end
        return formatAddress(regdef.offset)
            + "  "
            + padRight(regdef.identifier, reg_identifier_width)
            + "  "
            + regdef.description
            + field_doc;
    endfunction

    function String doc_region(RegRegionDef_t regiondef);
        return "REGION "
            + formatAddress(regiondef.offset)
            + ":"
            + formatAddress(regiondef.offset + regiondef.length - 1)
            + " "
            + regiondef.identifier
            + " "
            + regiondef.description;
    endfunction

    function String doc_block(RegBlockDef_t block_def);
        return "BLOCK " + formatAddress(block_def.offset) + ":" + formatAddress(block_def.offset + block_def.length - 1) + " prefix=" + block_def.prefix + " " + block_def.name + " " + block_def.description;
    endfunction

    String block_doc  = List::foldl(strConcat, "", List::map(strConcat("\n\n"), List::map(doc_block, blockdefs)));
    String reg_doc    = List::foldl(strConcat, "", List::map(strConcat("\n\n"), List::map(doc_reg, regdefs)));
    String region_doc = List::foldl(strConcat, "", List::map(strConcat("\n\n"), List::map(doc_region, regiondefs)));
    String map_doc    = validation.map_name + " " + validation.map_description;

    return RegMapDoc_t {
        reg_defs: validation.valid ? map_doc + block_doc + reg_doc + region_doc : validation.errors
    };

endmodule

module [Module] doc_blue_csr_markdown#(BlueCSRCtx_t#(aw, dw, i) ctx)(RegMapDoc_t#(dw));

    let {_, c} <- getCollection(ctx);
    let validation  = validate_blue_csr_entries(c);
    let blockdefs   = List::concat(List::map(get_reg_block_def, c));
    let regdefs     = List::concat(List::map(get_reg_def, c));
    let regiondefs  = List::concat(List::map(get_reg_region_def, c));
    let regfields   = List::concat(List::map(get_regfield_def, c));

    if(!validation.valid) begin
        errorM(validation.errors);
    end

    function String repeatString(String value, Integer count);
        if(count <= 0) return "";
        else return value + repeatString(value, count - 1);
    endfunction

    function String padLeftWith(String value, Integer width, String fill);
        Integer padding = width - stringLength(value);
        return repeatString(fill, padding) + value;
    endfunction

    function String padInteger(Integer value, Integer width);
        return padLeftWith(integerToString(value), width, "0");
    endfunction

    function String fieldBits(RegFieldDef_t rf);
        Integer msb = rf.bit_offset + rf.width - 1;
        return "[" + padInteger(msb, 2) + ":" + padInteger(rf.bit_offset, 2) + "]";
    endfunction

    function String fieldAccess(RegFieldDef_t rf);
        case (rf.access_type)
            CSR_RW:  return "RW";
            CSR_RO:  return "RO";
            CSR_RC:  return "RC";
            CSR_WC:  return "WC";
            CSR_WS:  return "WS";
            CSR_WO:  return "WO";
            CSR_W1S: return "W1S";
            CSR_W1C: return "W1C";
        endcase
    endfunction

    function Integer regOffsetWidth(RegDef_t regdef);
        return stringLength(integerToHex(regdef.offset));
    endfunction

    function Integer regionAddressWidth(RegRegionDef_t regiondef);
        Integer end_offset = regiondef.offset + regiondef.length - 1;
        return max(stringLength(integerToHex(regiondef.offset)), stringLength(integerToHex(end_offset)));
    endfunction

    function Integer addressWidth();
        Integer reg_width    = List::foldr(max, 1, List::map(regOffsetWidth, regdefs));
        Integer region_width = List::foldr(max, 1, List::map(regionAddressWidth, regiondefs));
        return max(reg_width, region_width);
    endfunction

    function String formatAddress(Integer value);
        return "0x" + padLeftWith(integerToHex(value), addressWidth(), "0");
    endfunction

    function String markdownHeader();
        return "| Address | Register | Register Description | Field | Bits | Access | Reset | Field Description |\n"
            + "| --- | --- | --- | --- | --- | --- | --- | --- |\n";
    endfunction

    function String fieldRow(RegDef_t regdef, RegFieldDef_t rf, Bool include_reg);
        return "| "
            + (include_reg ? formatAddress(regdef.offset) : "")
            + " | "
            + (include_reg ? regdef.identifier : "")
            + " | "
            + (include_reg ? regdef.description : "")
            + " | "
            + rf.identifier
            + " | "
            + fieldBits(rf)
            + " | "
            + fieldAccess(rf)
            + " | "
            + rf.reset_value
            + " | "
            + rf.description
            + " |\n";
    endfunction

    function String emptyRegRow(RegDef_t regdef);
        return "| "
            + formatAddress(regdef.offset)
            + " | "
            + regdef.identifier
            + " | "
            + regdef.description
            + " |  |  |  |  |  |\n";
    endfunction

    function String doc_reg(RegDef_t regdef);
        String rows        = "";
        Bool   found_field = False;
        for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
            let rf = regfields[fi];
            if(rf.offset == regdef.offset) begin
                rows = rows + fieldRow(regdef, rf, !found_field);
                found_field = True;
            end
        end
        return found_field ? rows : emptyRegRow(regdef);
    endfunction

    function String doc_region(RegRegionDef_t regiondef);
        return "| "
            + formatAddress(regiondef.offset)
            + ":"
            + formatAddress(regiondef.offset + regiondef.length - 1)
            + " | "
            + regiondef.identifier
            + " | "
            + regiondef.description
            + " |  |  |  |  |  |\n";
    endfunction

    function String doc_block(RegBlockDef_t block_def);
        return "| " + formatAddress(block_def.offset) + ":" + formatAddress(block_def.offset + block_def.length - 1) + " | " + block_def.prefix + " | " + block_def.name + " | " + block_def.description + " |\n";
    endfunction

    String block_doc  = List::isNull(blockdefs) ? "" : "| Block Address | Prefix | Name | Description |\n" + "| --- | --- | --- | --- |\n" + List::foldl(strConcat, "", List::map(doc_block, blockdefs)) + "\n";
    String reg_doc    = List::foldl(strConcat, "", List::map(doc_reg, regdefs));
    String region_doc = List::foldl(strConcat, "", List::map(doc_region, regiondefs));
    String map_doc    = validation.map_name + " " + validation.map_description;

    return RegMapDoc_t {
        reg_defs: validation.valid ? map_doc + "\n\n" + block_doc + markdownHeader() + reg_doc + region_doc : validation.errors
    };

endmodule

//addrmap body of a register map, offset is added to every address so a fabric can nest it
function String render_blue_csr_systemrdl(List#(RegMapEntry_t#(aw, dw)) c, String indent, Integer offset);
    let validation     = validate_blue_csr_entries(c);
    let regdefs        = List::concat(List::map(get_reg_def, c));
    let regiondefs     = List::concat(List::map(get_reg_region_def, c));
    let regfields      = List::concat(List::map(get_regfield_def, c));
    let pure_reads     = List::concat(List::map(get_pure_read, c));
    let action_reads   = List::concat(List::map(get_action_read, c));
    let writes         = List::concat(List::map(get_write_op, c));
    let action_writes  = List::concat(List::map(get_action_write, c));
    let read_regions   = List::concat(List::map(get_read_region, c));
    let write_regions  = List::concat(List::map(get_write_region, c));
    let server_regions = List::concat(List::map(get_server_region, c));
    let read_triggers  = List::concat(List::map(get_read_trigger, c));
    let write_triggers = List::concat(List::map(get_write_trigger, c));

    function Bool has_read_access(Integer offs);
        Bool found = False;
        for(Integer i = 0; i < length(pure_reads); i = i + 1) begin
            found = found || pure_reads[i].offset == offs;
        end
        for(Integer i = 0; i < length(action_reads); i = i + 1) begin
            found = found || action_reads[i].offset == offs;
        end
        for(Integer i = 0; i < length(read_triggers); i = i + 1) begin
            found = found || read_triggers[i].offset == offs;
        end
        return found;
    endfunction

    function Bool has_write_access(Integer offs);
        Bool found = False;
        for(Integer i = 0; i < length(writes); i = i + 1) begin
            found = found || writes[i].offset == offs;
        end
        for(Integer i = 0; i < length(action_writes); i = i + 1) begin
            found = found || action_writes[i].offset == offs;
        end
        for(Integer i = 0; i < length(write_triggers); i = i + 1) begin
            found = found || write_triggers[i].offset == offs;
        end
        return found;
    endfunction

    function Bool has_region_read_access(Integer offs, Integer len);
        Bool found = False;
        for(Integer i = 0; i < length(read_regions); i = i + 1) begin
            found = found || ((read_regions[i].offset == offs) && (read_regions[i].length == len));
        end
        for(Integer i = 0; i < length(server_regions); i = i + 1) begin
            found = found || ((server_regions[i].offset == offs) && (server_regions[i].length == len));
        end
        return found;
    endfunction

    function Bool has_region_write_access(Integer offs, Integer len);
        Bool found = False;
        for(Integer i = 0; i < length(write_regions); i = i + 1) begin
            found = found || ((write_regions[i].offset == offs) && (write_regions[i].length == len));
        end
        for(Integer i = 0; i < length(server_regions); i = i + 1) begin
            found = found || ((server_regions[i].offset == offs) && (server_regions[i].length == len));
        end
        return found;
    endfunction

    function String get_sw(Bool has_read, Bool has_write);
        if(has_read && has_write) return "rw";
        else if(has_read) return "r";
        else if(has_write) return "w";
        else return "na";
    endfunction

    //quotes and backslashes in descriptions must be escaped in SystemRDL strings
    function String rdl_string(String value);
        function List#(Char) escape_char(Char ch) = (ch == "\"" || ch == "\\") ? Cons("\\", Cons(ch, Nil)) : Cons(ch, Nil);
        return charListToString(List::concat(List::map(escape_char, stringToCharList(value))));
    endfunction

    function String get_field_properties(BlueCSRAccess_t access_type);
        case (access_type)
            CSR_RW:  return "sw = rw;";
            CSR_RO:  return "sw = r;";
            CSR_RC:  return "sw = r;";
            CSR_WC:  return "sw = rw; onwrite = wclr;";
            CSR_WS:  return "sw = rw; onwrite = wset;";
            CSR_WO:  return "sw = w;";
            CSR_W1S: return "sw = rw; onwrite = woset;";
            CSR_W1C: return "sw = rw; onwrite = woclr;";
        endcase
    endfunction

    function String address(Integer offs) = "0x" + integerToHex(offs + offset);

    String text = "";
    if(validation.map_description != "")
        text = indent + "desc = \"" + rdl_string(validation.map_description) + "\";\n";

    for(Integer ri = 0; ri < length(regiondefs); ri = ri + 1) begin
        let     region  = regiondefs[ri];
        String  sw      = get_sw(has_region_read_access(region.offset, region.length), has_region_write_access(region.offset, region.length));
        Integer entries = region.length / valueOf(TDiv#(dw, 8));
        text = text + indent + "mem {\n"
            + indent + "  desc = \"" + rdl_string(region.description) + "\";\n"
            + indent + "  mementries = " + integerToString(entries) + ";\n"
            + indent + "  memwidth = " + integerToString(valueOf(dw)) + ";\n"
            + indent + "  sw = " + sw + ";\n"
            + indent + "} external " + region.identifier + " @ " + address(region.offset) + ";\n";
    end

    for(Integer ri = 0; ri < length(regdefs); ri = ri + 1) begin
        let    rd        = regdefs[ri];
        Bool   can_read  = has_read_access(rd.offset);
        Bool   can_write = has_write_access(rd.offset);
        String sw        = get_sw(can_read, can_write);
        String fields    = "";

        for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
            let rf = regfields[fi];
            if(rf.offset == rd.offset) begin
                Integer msb = rf.bit_offset + rf.width - 1;
                fields = fields + indent + "  field { " + get_field_properties(rf.access_type) + " desc = \"" + rdl_string(rf.description) + "\"; } "
                    + rf.identifier + "[" + integerToString(msb) + ":" + integerToString(rf.bit_offset) + "] = " + rf.reset_value + ";\n";
            end
        end
        if(fields == "")
            fields = indent + "  field { sw = " + sw + "; desc = \"No field metadata\"; } RESERVED[" + integerToString(valueOf(dw) - 1) + ":0];\n";

        //SystemRDL rejects registers that software cannot access
        if(can_read || can_write)
            text = text + indent + "reg {\n"
                + indent + "  desc = \"" + rdl_string(rd.description) + "\";\n"
                + indent + "  regwidth = " + integerToString(valueOf(dw)) + ";\n"
                + fields
                + indent + "} " + rd.identifier + " @ " + address(rd.offset) + ";\n";
        else
            text = text + indent + "// " + rd.identifier + " @ " + address(rd.offset) + " omitted: no software access\n";
    end

    return text;
endfunction

module [Module] export_systemrdl_blue_csr#(BlueCSRCtx_t#(aw, dw, i) ctx, String output_path)(BlueCSRExport_ifc);

    let {_, c} <- getCollection(ctx);
    let validation = validate_blue_csr_entries(c);
    String text    = "// Auto-generated by export_systemrdl_blue_csr\naddrmap " + validation.map_name + " {\n" + render_blue_csr_systemrdl(c, "  ", 0) + "};\n";

    Reg#(Bool) rg_done    <- mkReg(False);
    Reg#(Bool) rg_success <- mkReg(False);

    rule r_export_once (!rg_done);
        rg_done <= True;

        if(!validation.valid) $display("%s", validation.errors);
        else begin
            File fh <- $fopen(output_path, "w");
            if(fh == InvalidFile) $display("BlueCSR SystemRDL export failed: could not open %s", output_path);
            else begin
                $fwrite(fh, "%s", text);
                $fclose(fh);
                rg_success <= True;
                $display("BlueCSR SystemRDL export complete: %s", output_path);
            end
        end
    endrule

    method done    = rg_done;
    method success = rg_success;

endmodule

endpackage
