#!/usr/bin/env python3
"""
Strip .debug_* and .rela.debug_* sections from an ELF relocatable (.o) file.

Unlike GNU objcopy 2.17, this script does NOT process or modify relocations,
so it won't corrupt relocation types it doesn't understand (e.g., type 42
R_X86_64_REX_GOTPCRELX).

It works by:
1. Reading the ELF header and section headers
2. Identifying .debug_* and .rela.debug_* sections
3. Copying non-debug section data to a new file
4. Rewriting section headers with updated offsets
5. Updating the ELF header with new section header offset
"""

import struct
import sys
import os

def read_elf_header(f):
    """Read ELF64 header."""
    f.seek(0)
    data = f.read(64)
    magic = data[0:4]
    assert magic == b'\x7fELF', "Not an ELF file"
    ei_class = data[4]
    assert ei_class == 2, "Not ELF64"
    ei_data = data[5]
    assert ei_data == 1, "Not little-endian"

    fmt = '<HHIQQQIHHHHHH'
    fields = struct.unpack_from(fmt, data, 16)
    return {
        'e_type': fields[0],
        'e_machine': fields[1],
        'e_version': fields[2],
        'e_entry': fields[3],
        'e_phoff': fields[4],
        'e_shoff': fields[5],
        'e_flags': fields[6],
        'e_ehsize': fields[7],
        'e_phentsize': fields[8],
        'e_phnum': fields[9],
        'e_shentsize': fields[10],
        'e_shnum': fields[11],
        'e_shstrndx': fields[12],
        'raw_ident': data[0:16],
    }

def read_section_headers(f, ehdr):
    """Read all section headers."""
    sections = []
    f.seek(ehdr['e_shoff'])
    for i in range(ehdr['e_shnum']):
        data = f.read(64)
        fmt = '<IIQQQQIIQQ'
        fields = struct.unpack(fmt, data)
        sections.append({
            'sh_name': fields[0],
            'sh_type': fields[1],
            'sh_flags': fields[2],
            'sh_addr': fields[3],
            'sh_offset': fields[4],
            'sh_size': fields[5],
            'sh_link': fields[6],
            'sh_info': fields[7],
            'sh_addralign': fields[8],
            'sh_entsize': fields[9],
            'index': i,
        })
    return sections

def get_section_name(f, sections, shstrndx, section):
    """Get section name from string table."""
    strtab = sections[shstrndx]
    f.seek(strtab['sh_offset'] + section['sh_name'])
    name = b''
    while True:
        c = f.read(1)
        if c == b'\x00' or c == b'':
            break
        name += c
    return name.decode('utf-8', errors='replace')

def is_debug_section(name):
    """Check if section is a debug section that should be stripped."""
    return name.startswith('.debug_') or name.startswith('.rela.debug_')

def align_offset(offset, alignment):
    """Align offset to given alignment."""
    if alignment <= 1:
        return offset
    return (offset + alignment - 1) & ~(alignment - 1)

def pack_section_header(sh):
    """Pack section header back to bytes."""
    return struct.pack('<IIQQQQIIQQ',
        sh['sh_name'], sh['sh_type'], sh['sh_flags'], sh['sh_addr'],
        sh['sh_offset'], sh['sh_size'], sh['sh_link'], sh['sh_info'],
        sh['sh_addralign'], sh['sh_entsize'])

def pack_elf_header(ehdr):
    """Pack ELF header back to bytes."""
    return ehdr['raw_ident'] + struct.pack('<HHIQQQIHHHHHH',
        ehdr['e_type'], ehdr['e_machine'], ehdr['e_version'],
        ehdr['e_entry'], ehdr['e_phoff'], ehdr['e_shoff'],
        ehdr['e_flags'], ehdr['e_ehsize'], ehdr['e_phentsize'],
        ehdr['e_phnum'], ehdr['e_shentsize'], ehdr['e_shnum'],
        ehdr['e_shstrndx'])

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.o> <output.o>")
        sys.exit(1)

    infile = sys.argv[1]
    outfile = sys.argv[2]

    with open(infile, 'rb') as f:
        ehdr = read_elf_header(f)
        sections = read_section_headers(f, ehdr)

        # Get section names
        names = []
        for s in sections:
            name = get_section_name(f, sections, ehdr['e_shstrndx'], s)
            names.append(name)
            s['name'] = name

        # Identify sections to keep vs strip
        # We need to build a mapping from old index to new index
        # for updating sh_link and sh_info references
        keep_indices = []
        strip_indices = set()
        old_to_new = {}

        for i, s in enumerate(sections):
            if is_debug_section(s['name']):
                strip_indices.add(i)
                print(f"  Stripping: [{i:2d}] {s['name']} ({s['sh_size']} bytes)")
            else:
                old_to_new[i] = len(keep_indices)
                keep_indices.append(i)

        print(f"\nKeeping {len(keep_indices)}/{len(sections)} sections, "
              f"stripping {len(strip_indices)} debug sections")

        # Build new section list with remapped indices
        new_sections = []
        for new_idx, old_idx in enumerate(keep_indices):
            s = dict(sections[old_idx])  # copy
            # Remap sh_link if it points to a kept section
            if s['sh_link'] != 0:
                if s['sh_link'] in old_to_new:
                    s['sh_link'] = old_to_new[s['sh_link']]
                elif s['sh_link'] in strip_indices:
                    # This section references a stripped section
                    # For RELA sections targeting debug sections, we already strip them
                    # For other cases, zero out the link
                    s['sh_link'] = 0
            # Remap sh_info for RELA sections (sh_info = section index being relocated)
            if s['sh_type'] == 4 or s['sh_type'] == 9:  # SHT_RELA or SHT_REL
                if s['sh_info'] in old_to_new:
                    s['sh_info'] = old_to_new[s['sh_info']]
                elif s['sh_info'] in strip_indices:
                    s['sh_info'] = 0
            new_sections.append(s)

        # Precompute which sections are symtab (SHT_SYMTAB=2) so we can
        # rewrite st_shndx in symbol entries
        SHT_SYMTAB = 2
        SHN_UNDEF = 0
        SHN_LORESERVE = 0xff00
        SHN_ABS = 0xfff1
        SHN_COMMON = 0xfff2

        def remap_symtab(section_data, old_to_new, strip_indices):
            """Rewrite st_shndx in symbol table entries."""
            # ELF64 Sym: st_name(4) st_info(1) st_other(1) st_shndx(2) st_value(8) st_size(8) = 24 bytes
            entry_size = 24
            result = bytearray(section_data)
            count = len(result) // entry_size
            remapped = 0
            for i in range(count):
                off = i * entry_size + 6  # offset of st_shndx within entry
                shndx = struct.unpack_from('<H', result, off)[0]
                if shndx >= SHN_LORESERVE:
                    continue  # special index (ABS, COMMON, etc.)
                if shndx == SHN_UNDEF:
                    continue
                if shndx in old_to_new:
                    struct.pack_into('<H', result, off, old_to_new[shndx])
                    remapped += 1
                elif shndx in strip_indices:
                    # Symbol referenced a stripped debug section — set to ABS
                    struct.pack_into('<H', result, off, SHN_ABS)
                    remapped += 1
            print(f"  Remapped {remapped} symbol section indices")
            return bytes(result)

        # Now write the output file
        # Strategy: write ELF header (64 bytes), then each kept section's data
        # at properly aligned offsets, then section headers at the end

        with open(outfile, 'wb') as out:
            # Write placeholder ELF header (we'll rewrite it at the end)
            out.write(b'\x00' * 64)

            current_offset = 64

            # Write section data for each kept section
            for sec_idx, s in enumerate(new_sections):
                if s['sh_type'] == 0:  # SHT_NULL
                    s['sh_offset'] = 0
                    continue
                if s['sh_type'] == 8:  # SHT_NOBITS (.bss)
                    # NOBITS sections don't occupy file space, keep offset for ordering
                    s['sh_offset'] = current_offset
                    continue

                # Align
                align = s['sh_addralign']
                if align > 1:
                    aligned = align_offset(current_offset, align)
                    if aligned > current_offset:
                        out.write(b'\x00' * (aligned - current_offset))
                        current_offset = aligned

                # Read section data
                s['sh_offset'] = current_offset
                old_idx = keep_indices[sec_idx]
                f.seek(sections[old_idx]['sh_offset'])
                section_data = f.read(s['sh_size'])

                # If this is a symbol table, remap st_shndx
                if s['sh_type'] == SHT_SYMTAB:
                    section_data = remap_symtab(section_data, old_to_new, strip_indices)

                out.write(section_data)
                current_offset += len(section_data)

            # Align section headers to 8 bytes
            aligned = align_offset(current_offset, 8)
            if aligned > current_offset:
                out.write(b'\x00' * (aligned - current_offset))
                current_offset = aligned

            # Write section headers
            shoff = current_offset
            for s in new_sections:
                out.write(pack_section_header(s))
                current_offset += 64

            # Rewrite ELF header with updated values
            new_ehdr = dict(ehdr)
            new_ehdr['e_shoff'] = shoff
            new_ehdr['e_shnum'] = len(new_sections)
            # Remap e_shstrndx
            new_ehdr['e_shstrndx'] = old_to_new[ehdr['e_shstrndx']]

            out.seek(0)
            out.write(pack_elf_header(new_ehdr))

    in_size = os.path.getsize(infile)
    out_size = os.path.getsize(outfile)
    print(f"\n{infile}: {in_size:,} bytes")
    print(f"{outfile}: {out_size:,} bytes")
    print(f"Saved: {in_size - out_size:,} bytes ({100*(in_size-out_size)/in_size:.1f}%)")

if __name__ == '__main__':
    main()
