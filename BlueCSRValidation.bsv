package BlueCSRValidation;

import List :: *;
import ModuleCollect :: *;

import BlueCSR :: *;

function RegMapValidation_t validate_blue_csr_entries(List#(RegMapEntry_t#(aw, dw)) c);
    let regmap_defs         = List::concat(List::map(get_regmap_def, c));
    let regdefs             = List::concat(List::map(get_reg_def, c));
    let regiondefs          = List::concat(List::map(get_reg_region_def, c));
    let access_policies     = List::concat(List::map(get_access_policy_def, c));
    let regfields           = List::concat(List::map(get_regfield_def, c));
    let pure_reads          = List::concat(List::map(get_pure_read, c));
    let writes              = List::concat(List::map(get_write_op, c));
    let read_regions        = List::concat(List::map(get_read_region, c));
    let write_regions       = List::concat(List::map(get_write_region, c));

    Integer word_bytes = valueOf(TDiv#(dw, 8));

    String errors = "";
    String map_name = "BlueCSR";
    String map_description = "";

    if(length(regmap_defs) == 0) begin
        errors = append_newline(errors, "BlueCSR validation failed: exactly one csr_regmap_def is required, found none.");
    end
    else if(length(regmap_defs) > 1) begin
        errors = append_newline(errors, "BlueCSR validation failed: exactly one csr_regmap_def is required, found " + integerToString(length(regmap_defs)) + ".");
    end
    else begin
        map_name = regmap_defs[0].name;
        map_description = regmap_defs[0].description;
    end

    for(Integer ri = 0; ri < length(regdefs); ri = ri + 1) begin
        let rd = regdefs[ri];
        if(count_regdefs_at(regdefs, rd.offset) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: register offset 0x" + integerToString(rd.offset) + " is defined multiple times.");
        end
    end

    for(Integer ri = 0; ri < length(regiondefs); ri = ri + 1) begin
        let region = regiondefs[ri];
        if(count_regions_exact(regiondefs, region.offset, region.length) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: region " + region.identifier + " is defined multiple times.");
        end
        if(region.length <= 0) begin
            errors = append_newline(errors, "BlueCSR validation failed: region " + region.identifier + " has non-positive length.");
        end
        if((region.offset % word_bytes) != 0) begin
            errors = append_newline(errors, "BlueCSR validation failed: region " + region.identifier + " offset is not aligned to the CSR word size.");
        end
        if((region.length % word_bytes) != 0) begin
            errors = append_newline(errors, "BlueCSR validation failed: region " + region.identifier + " length is not an integer number of CSR words.");
        end
        for(Integer rj = ri + 1; rj < length(regiondefs); rj = rj + 1) begin
            let other = regiondefs[rj];
            if(byte_ranges_overlap(region.offset, region.length, other.offset, other.length)) begin
                errors = append_newline(errors, "BlueCSR validation failed: regions " + region.identifier + " and " + other.identifier + " overlap.");
            end
        end
        for(Integer rj = 0; rj < length(regdefs); rj = rj + 1) begin
            let regdef = regdefs[rj];
            if(byte_ranges_overlap(region.offset, region.length, regdef.offset, valueOf(TDiv#(dw, 8)))) begin
                errors = append_newline(errors, "BlueCSR validation failed: region " + region.identifier + " overlaps register " + regdef.identifier + ".");
            end
        end
    end

    for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
        let rf = regfields[fi];
        Integer regdef_count = count_regdefs_at(regdefs, rf.offset);
        if(regdef_count == 0) begin
            errors = append_newline(errors, "BlueCSR validation failed: field " + rf.identifier + " at offset 0x" + integerToString(rf.offset) + " has no parent csr_reg_def.");
        end
        else if(regdef_count > 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: field " + rf.identifier + " at offset 0x" + integerToString(rf.offset) + " matches multiple csr_reg_def entries.");
        end

        if(rf.bit_offset < 0) begin
            errors = append_newline(errors, "BlueCSR validation failed: field " + rf.identifier + " has negative bit offset.");
        end
        if(rf.width <= 0) begin
            errors = append_newline(errors, "BlueCSR validation failed: field " + rf.identifier + " has non-positive width.");
        end
        if((rf.bit_offset + rf.width) > valueOf(dw)) begin
            errors = append_newline(errors, "BlueCSR validation failed: field " + rf.identifier + " exceeds register width " + integerToString(valueOf(dw)) + ".");
        end

        for(Integer fj = fi + 1; fj < length(regfields); fj = fj + 1) begin
            let other = regfields[fj];
            if((rf.offset == other.offset) && field_ranges_overlap(rf, other)) begin
                errors = append_newline(errors, "BlueCSR validation failed: fields " + rf.identifier + " and " + other.identifier + " overlap in register offset 0x" + integerToString(rf.offset) + ".");
            end
        end
    end

    for(Integer i = 0; i < length(pure_reads); i = i + 1) begin
        if(count_regdefs_at(regdefs, pure_reads[i].offs) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: pure read at offset 0x" + integerToString(pure_reads[i].offs) + " does not resolve to exactly one csr_reg_def.");
        end
    end

    for(Integer i = 0; i < length(writes); i = i + 1) begin
        if(count_regdefs_at(regdefs, writes[i].offs) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: write op at offset 0x" + integerToString(writes[i].offs) + " does not resolve to exactly one csr_reg_def.");
        end
    end

    for(Integer i = 0; i < length(read_regions); i = i + 1) begin
        if(count_regions_exact(regiondefs, read_regions[i].offs, read_regions[i].length) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: pure read region at offset 0x" + integerToString(read_regions[i].offs) + " does not resolve to exactly one csr_region_def.");
        end
    end

    for(Integer i = 0; i < length(write_regions); i = i + 1) begin
        if(count_regions_exact(regiondefs, write_regions[i].offs, write_regions[i].length) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: write region at offset 0x" + integerToString(write_regions[i].offs) + " does not resolve to exactly one csr_region_def.");
        end
    end

    for(Integer i = 0; i < length(regiondefs); i = i + 1) begin
        let region = regiondefs[i];
        Bool has_read = False;
        Bool has_write = False;
        for(Integer j = 0; j < length(read_regions); j = j + 1) begin
            has_read = has_read || ((read_regions[j].offs == region.offset) && (read_regions[j].length == region.length));
        end
        for(Integer j = 0; j < length(write_regions); j = j + 1) begin
            has_write = has_write || ((write_regions[j].offs == region.offset) && (write_regions[j].length == region.length));
        end
        if(!(has_read || has_write)) begin
            errors = append_newline(errors, "BlueCSR validation failed: region " + region.identifier + " has no bound read or write handler.");
        end
    end

    for(Integer i = 0; i < length(access_policies); i = i + 1) begin
        let ap = access_policies[i];
        Integer target_count = count_regdefs_at(regdefs, ap.offset);
        target_count = target_count + count_regions_exact(regiondefs, ap.offset, ap.length);
        if(count_access_policies_exact(access_policies, ap.offset, ap.length) != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: duplicate protection policy definitions at offset 0x" + integerToString(ap.offset) + ".");
        end
        if(target_count != 1) begin
            errors = append_newline(errors, "BlueCSR validation failed: protection policy at offset 0x" + integerToString(ap.offset) + " does not resolve to exactly one register or region.");
        end
    end

    return RegMapValidation_t {
        valid: errors == "",
        errors: errors,
        map_name: map_name,
        map_description: map_description
    };
endfunction

endpackage