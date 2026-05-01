package BlueCSRExport;

import List :: *;
import ModuleCollect :: *;

import BlueCSR :: *;
import BlueCSRValidation :: *;

module [Module] doc_blue_csr#(BlueCSRCtx_t#(aw, dw, i) ctx)(RegMapDoc_t#(dw));

    let {coll_device_ifc, c} <- getCollection(ctx);
    let validation = validate_blue_csr_entries(c);
    let regdefs     = List::concat(List::map(get_reg_def, c));
    let regiondefs  = List::concat(List::map(get_reg_region_def, c));
    let regfields   = List::concat(List::map(get_regfield_def, c));

    if (!validation.valid) begin
        errorM(validation.errors);
    end

    function String repeatString(String value, Integer count);
        if (count <= 0) return "";
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

    function Integer regOffsetWidth(RegDef_t regdef);
        return stringLength(integerToHex(regdef.offset));
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

    function String doc_reg(RegDef_t regdef);
        Integer reg_offset_width        = List::foldr(max, 0, List::map(regOffsetWidth, regdefs));
        Integer reg_identifier_width    = List::foldr(max, 0, List::map(regIdentifierWidth, regdefs));
        Integer field_identifier_width  = List::foldr(max, 0, List::map(fieldIdentifierWidth, regfields));
        Integer field_bits_width        = List::foldr(max, 0, List::map(fieldBitsWidth, regfields));
        Integer field_reset_width       = List::foldr(max, 0, List::map(fieldResetWidth, regfields));
        String field_doc = "";
        for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
            let rf = regfields[fi];
            if (rf.offset == regdef.offset) begin
                String bits = fieldBits(rf);
                String reset = fieldReset(rf);
                field_doc = field_doc + "\n  "
                    + padRight(rf.identifier, field_identifier_width)
                    + "  "
                    + padRight(bits, field_bits_width)
                    + "  "
                    + padRight(reset, field_reset_width)
                    + "  "
                    + rf.description;
            end
        end
        return padLeft(integerToHex(regdef.offset), reg_offset_width)
            + "  "
            + padRight(regdef.identifier, reg_identifier_width)
            + "  "
            + regdef.description
            + field_doc;
    endfunction

    function String doc_region(RegRegionDef_t regiondef);
        return "REGION " + integerToHex(regiondef.offset) + ":" + integerToHex(regiondef.offset + regiondef.length - 1) + " " + regiondef.identifier + " " + regiondef.description;
    endfunction

    String reg_doc = List::foldl(strConcat, "", List::map(strConcat("\n"), List::map(doc_reg, regdefs)));
    String region_doc = List::foldl(strConcat, "", List::map(strConcat("\n"), List::map(doc_region, regiondefs)));
    String map_doc = validation.map_name + " " + validation.map_description;

    return RegMapDoc_t {
        reg_defs: validation.valid ? map_doc + reg_doc + region_doc : validation.errors
    };

endmodule

module [Module] export_systemrdl_blue_csr#(BlueCSRCtx_t#(aw, dw, i) ctx, String output_path)(BlueCSRExport_ifc);

    let {coll_device_ifc, c} <- getCollection(ctx);
    let validation = validate_blue_csr_entries(c);
    let regdefs             = List::concat(List::map(get_reg_def, c));
    let regiondefs          = List::concat(List::map(get_reg_region_def, c));
    let regfields           = List::concat(List::map(get_regfield_def, c));
    let pure_reads          = List::concat(List::map(get_pure_read, c));
    let writes              = List::concat(List::map(get_write_op, c));
    let read_regions   = List::concat(List::map(get_read_region, c));
    let write_regions       = List::concat(List::map(get_write_region, c));

    Reg#(Bool) rg_done <- mkReg(False);
    Reg#(Bool) rg_success <- mkReg(False);
    Reg#(Bool) rg_started <- mkReg(False);

    function String integerToHexDigitS(Integer n) = charToString(integerToHexDigit(n));

    function String integerToHex(Integer n);
        if (n < 16) return integerToHexDigitS(n);
        else return strConcat(integerToHex(n / 16), integerToHexDigitS(n % 16));
    endfunction

    function Bool has_read_access(Integer offs);
        Bool found = False;
        for(Integer i = 0; i < length(pure_reads); i = i + 1) begin
            found = found || pure_reads[i].offs == offs;
        end
        return found;
    endfunction

    function Bool has_write_access(Integer offs);
        Bool found = False;
        for(Integer i = 0; i < length(writes); i = i + 1) begin
            found = found || writes[i].offs == offs;
        end
        return found;
    endfunction

    function Bool has_region_read_access(Integer offs, Integer len);
        Bool found = False;
        for(Integer i = 0; i < length(read_regions); i = i + 1) begin
            found = found || ((read_regions[i].offs == offs) && (read_regions[i].length == len));
        end
        return found;
    endfunction

    function Bool has_region_write_access(Integer offs, Integer len);
        Bool found = False;
        for(Integer i = 0; i < length(write_regions); i = i + 1) begin
            found = found || ((write_regions[i].offs == offs) && (write_regions[i].length == len));
        end
        return found;
    endfunction

    function String get_sw(Bool has_read, Bool has_write);
        if (has_read && has_write) return "rw";
        else if (has_read) return "r";
        else if (has_write) return "w";
        else return "r";
    endfunction

    rule r_export_once (!rg_started);
        rg_started <= True;

        if (!validation.valid) begin
            $display("%s", validation.errors);
            rg_done <= True;
            rg_success <= False;
        end
        else begin

            File fh <- $fopen(output_path, "w");
            if (fh == InvalidFile) begin
                $display("BlueCSR SystemRDL export failed: could not open %s", output_path);
                rg_done <= True;
                rg_success <= False;
            end
            else begin
                $fwrite(fh, "// Auto-generated by export_systemrdl_blue_csr\n");
                $fwrite(fh, "addrmap %s {\n", validation.map_name);
                if (validation.map_description != "") begin
                    $fwrite(fh, "  desc = \"%s\";\n", validation.map_description);
                end
                for(Integer ri = 0; ri < length(regiondefs); ri = ri + 1) begin
                    let region = regiondefs[ri];
                    String sw = get_sw(has_region_read_access(region.offset, region.length), has_region_write_access(region.offset, region.length));
                    Integer entries = region.length / valueOf(TDiv#(dw, 8));
                    $fwrite(fh, "  mem {\n");
                    $fwrite(fh, "    desc = \"%s\";\n", region.description);
                    $fwrite(fh, "    mementries = %0d;\n", entries);
                    $fwrite(fh, "    memwidth = %0d;\n", valueOf(dw));
                    $fwrite(fh, "    sw = %s;\n", sw);
                    $fwrite(fh, "  } external %s @ 0x%s;\n", region.identifier, integerToHex(region.offset));
                end
                for(Integer ri = 0; ri < length(regdefs); ri = ri + 1) begin
                    let rd = regdefs[ri];
                    Bool can_read = has_read_access(rd.offset);
                    Bool can_write = has_write_access(rd.offset);
                    String sw = get_sw(can_read, can_write);
                    Bool wrote_field = False;

                    $fwrite(fh, "  reg {\n");
                    $fwrite(fh, "    desc = \"%s\";\n", rd.description);

                    for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
                        let rf = regfields[fi];
                        if (rf.offset == rd.offset) begin
                            Integer msb = rf.bit_offset + rf.width - 1;
                            $fwrite(fh, "    field { sw = %s; desc = \"%s\"; } %s[%0d:%0d] = %s;\n", sw, rf.description, rf.identifier, msb, rf.bit_offset, rf.reset_value);
                            wrote_field = True;
                        end
                    end

                    if (!wrote_field) begin
                        $fwrite(fh, "    field { sw = %s; desc = \"No field metadata\"; } RESERVED[0:0];\n", sw);
                    end

                    $fwrite(fh, "  } %s @ 0x%s;\n", rd.identifier, integerToHex(rd.offset));
                end

                $fwrite(fh, "};\n");
                $fflush(fh);
                $fclose(fh);
                rg_done <= True;
                rg_success <= True;
                $display("BlueCSR SystemRDL export complete: %s", output_path);
            end
        end
    endrule

    method Bool done;
        return rg_done;
    endmethod

    method Bool success;
        return rg_success;
    endmethod

endmodule

endpackage