module Decoder

using ..HpackTypes
using ..Tables
using ..Primitives: decode_integer, decode_string
using ..Exc: HPACKError, HPACKBoundsError


export hpack_decode_headers, decode_indexed_header, decode_literal_incremental_new, decode_literal_incremental_indexed, decode_literal_never_indexed_new, decode_literal_never_indexed_indexed, decode_literal_without_indexing_indexed, decode_literal_without_indexing_new, decode_table_size_update, decode_string, get_header_by_index, reset_decoder!, set_max_table_size!

const HPACK_STATIC_TABLE_SIZE = 61 # RFC 7541 Appendix B

"""
    hpack_decode_headers(decoder::HPACKDecoder, data::AbstractVector{UInt8}) -> Vector{Pair{String, String}}

Decode a compressed HPACK header block into a list of header name-value pairs.

# Arguments
- `decoder::HPACKDecoder`: The decoder state.
- `data::AbstractVector{UInt8}`: The compressed header block.

# Returns
- `Vector{Pair{String, String}}`: Decoded headers.

# Usage
```julia
decoder = HPACKDecoder()
headers = hpack_decode_headers(decoder, encoded_data)
```
"""
function hpack_decode_headers(decoder::HPACKDecoder, data::AbstractVector{UInt8})
    headers = Pair{String, String}[]
    sizehint!(headers, 32)
    pos = 1
    total_size = 0
    while pos <= length(data)
        byte = data[pos]
        
        # ΝΕΑ ΣΗΜΑΙΑ (FLAG)
        header_added = false
        
        if (byte & 0x80) == 0x80
            header, pos = decode_indexed_header(decoder, data, pos)
            push!(headers, header)
            header_added = true
        elseif (byte & 0xC0) == 0x40
            if (byte & 0x3F) == 0
                header, pos = decode_literal_incremental_new(decoder, data, pos)
            else
                header, pos = decode_literal_incremental_indexed(decoder, data, pos)
            end
            push!(headers, header)
            add!(decoder.dynamic_table, header.first, header.second)
            header_added = true
        elseif (byte & 0xE0) == 0x20
            # Αυτή η περίπτωση δεν προσθέτει κεφαλίδα
            pos = decode_table_size_update(decoder, data, pos)
        elseif (byte & 0xF0) == 0x10
            if (byte & 0x0F) == 0
                header, pos = decode_literal_never_indexed_new(decoder, data, pos)
            else
                header, pos = decode_literal_never_indexed_indexed(decoder, data, pos)
            end
            push!(headers, header)
            header_added = true
        elseif (byte & 0xF0) == 0x00
            if (byte & 0x0F) == 0
                header, pos = decode_literal_without_indexing_new(decoder, data, pos)
            else
                header, pos = decode_literal_without_indexing_indexed(decoder, data, pos)
            end
            push!(headers, header)
            header_added = true
        else
            throw(HPACKError("Unknown HPACK representation starting with byte: $(string(byte, base=16))"))
        end

        # ΕΛΕΓΧΟΣ ΤΗΣ ΣΗΜΑΙΑΣ ΠΡΙΝ ΤΟΝ ΥΠΟΛΟΓΙΣΜΟ
        if header_added
            # Αυτός ο έλεγχος γίνεται μόνο αν προστέθηκε κεφαλίδα
            last_header = last(headers)
            # Προσοχή: το last(headers) μπορεί να επιστρέψει nothing από το get_header_by_index
            if !isnothing(last_header) && !isnothing(last_header.first)
                total_size += sizeof(last_header.first) + sizeof(last_header.second)
                if total_size > decoder.max_header_list_size
                    throw(HPACKError("Header list size exceeds SETTINGS_MAX_HEADER_LIST_SIZE"))
                end
            end
        end
    end
    # Φιλτράρουμε πιθανά `nothing` που μπορεί να προέκυψαν από σφάλματα
    return filter(h -> !isnothing(h) && !isnothing(h.first), headers)
end

"""
    decode_indexed_header(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode an indexed header field representation.

# Usage
```julia
header, new_pos = decode_indexed_header(decoder, data, pos)
```
"""
function decode_indexed_header(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    index, new_pos = decode_integer(data, pos, 7)
    if index == 0
        throw(HPACKError("Invalid index 0 in indexed header field"))
    end
    name, value = get_header_by_index(decoder, index)
    return (name => value), new_pos
end

"""
    decode_literal_incremental_new(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode a literal header field with incremental indexing and new name.

# Usage
```julia
header, new_pos = decode_literal_incremental_new(decoder, data, pos)
```
"""
function decode_literal_incremental_new(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    if (data[pos] & 0x3F) != 0
        throw(HPACKError("Invalid literal header with incremental indexing - new name"))
    end
    pos += 1
    name, pos = decode_string(data, pos)
    value, pos = decode_string(data, pos)
    return (name => value), pos
end

"""
    decode_literal_incremental_indexed(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode a literal header field with incremental indexing and indexed name.

# Usage
```julia
header, new_pos = decode_literal_incremental_indexed(decoder, data, pos)
```
"""
function decode_literal_incremental_indexed(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    index, pos = decode_integer(data, pos, 6)
    if index == 0
        throw(HPACKError("Invalid index 0 in literal header field"))
    end
    name, _ = get_header_by_index(decoder, index)
    value, pos = decode_string(data, pos)
    return (name => value), pos
end

"""
    decode_literal_never_indexed_new(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode a literal header field that should never be indexed with new name.

# Usage
```julia
header, new_pos = decode_literal_never_indexed_new(decoder, data, pos)
```
"""
function decode_literal_never_indexed_new(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    if (data[pos] & 0x0F) != 0
        throw(HPACKError("Invalid literal header never indexed - new name"))
    end
    pos += 1
    name, pos = decode_string(data, pos)
    value, pos = decode_string(data, pos)
    return (name => value), pos
end

"""
    decode_literal_never_indexed_indexed(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode a literal header field that should never be indexed with indexed name.

# Usage
```julia
header, new_pos = decode_literal_never_indexed_indexed(decoder, data, pos)
```
"""
function decode_literal_never_indexed_indexed(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    index, pos = decode_integer(data, pos, 4)
    if index == 0
        throw(HPACKError("Invalid index 0 in literal header field"))
    end
    name, _ = get_header_by_index(decoder, index)
    value, pos = decode_string(data, pos)
    return (name => value), pos
end

"""
    decode_literal_without_indexing_indexed(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode a literal header field without indexing with indexed name.

# Usage
```julia
header, new_pos = decode_literal_without_indexing_indexed(decoder, data, pos)
```
"""
function decode_literal_without_indexing_indexed(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    index, pos = decode_integer(data, pos, 4)
    if index == 0
        throw(HPACKError("Invalid index 0 in literal header field"))
    end
    name, _ = get_header_by_index(decoder, index)
    value, pos = decode_string(data, pos)
    return (name => value), pos
end

"""
    decode_literal_without_indexing_new(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> (Pair{String, String}, Int)

Decode a literal header field without indexing with new name.

# Usage
```julia
header, new_pos = decode_literal_without_indexing_new(decoder, data, pos)
```
"""
function decode_literal_without_indexing_new(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    pos += 1
    name, pos = decode_string(data, pos)
    value, pos = decode_string(data, pos)
    return (name => value), pos
end

"""
    decode_table_size_update(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int) -> Int

Decode a dynamic table size update.

# Usage
```julia
new_pos = decode_table_size_update(decoder, data, pos)
```
"""
function decode_table_size_update(decoder::HPACKDecoder, data::AbstractVector{UInt8}, pos::Int)
    new_size, new_pos = decode_integer(data, pos, 5)
    if new_size > decoder.max_table_size
        throw(HPACKError("Dynamic table size update exceeds maximum size"))
    end
    resize!(decoder.dynamic_table, UInt32(new_size))
    return new_pos
end

"""
    get_header_by_index(decoder::HPACKDecoder, index::Int) -> (String, String)

Get a header name-value pair by index from static or dynamic table.

# Usage
```julia
name, value = get_header_by_index(decoder, 1)
```
"""
function get_header_by_index(decoder::HPACKDecoder, index::Int)
    try
        if index <= 0
            throw(HPACKError("Invalid index 0 in header field"))
        end
        if index <= HPACK_STATIC_TABLE_SIZE
            entry = Tables.STATIC_TABLE[index]
            return entry.name, entry.value
        else
            dynamic_index = index - HPACK_STATIC_TABLE_SIZE
            if dynamic_index <= length(decoder.dynamic_table.entries)
                entry = decoder.dynamic_table.entries[dynamic_index]
                return entry.name, entry.value
            else
                throw(HPACKError("Index $index out of range"))
            end
        end
    catch e
        if isa(e, HPACKBoundsError) || isa(e, BoundsError)
            @warn "HPACK: Skipping header due to out-of-range index $index" exception=e
            return nothing  # Skip this header
        else
            rethrow(e)
        end
    end
end

"""
    reset_decoder!(decoder::HPACKDecoder)

Reset the decoder to initial state, clearing the dynamic table.

# Usage
```julia
reset_decoder!(decoder)
```
"""
function reset_decoder!(decoder::HPACKDecoder)
    empty!(decoder.dynamic_table)
end

"""
    set_max_table_size!(decoder::HPACKDecoder, size::Int)

Set the maximum dynamic table size and resize if necessary.

# Usage
```julia
set_max_table_size!(decoder, 4096)
```
"""
function set_max_table_size!(decoder::HPACKDecoder, size::Int)
    decoder.max_table_size = size
    resize!(decoder.dynamic_table, UInt32(size))
end

end