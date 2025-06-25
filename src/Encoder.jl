module Encoder

using ..HpackTypes, ..Validation
using ..HpackTypes: HPACKEncodingOptions
using ..Tables: find_index, find_name_index, add!, max_size, size
using ..Primitives: encode_integer, encode_string
using ..Huffman: huffman_encode, huffman_encoded_length # Χρειαζόμαστε το huffman_encoded_length
using ..Exc: HPACKError, HPACKBoundsError



export hpack_encode_headers, encode_indexed_header, encode_literal_with_incremental_indexing, encode_literal_without_indexing, encode_literal_never_indexed, encode_table_size_update, is_sensitive_header, determine_encoding_strategy, encode_headers, update_table_size!, reset_encoder!

"""
    hpack_encode_headers(encoder::HPACKEncoder, headers)

Encode a list of headers using HPACK and return the encoded byte vector.

# Arguments
- `encoder::HPACKEncoder`: The encoder state.
- `headers`: Can be a vector of pairs, a vector of tuples, or a dictionary.

# Returns
- `Vector{UInt8}`: Encoded HPACK block.

# Usage
```julia
encoder = HPACKEncoder()
headers = ["content-type" => "text/html", "accept" => "*/*"]
encoded = hpack_encode_headers(encoder, headers)
```
"""
function hpack_encode_headers(encoder::HPACKEncoder, headers::Vector{Tuple{String,String}})
    hpack_encode_headers(encoder, [Pair(name, value) for (name, value) in headers])
end

function hpack_encode_headers(encoder::HPACKEncoder, headers::Vector{<:Pair})
    io = IOBuffer()

    # Build the dynamic table dictionary ONCE.
    dyn_dict = Dict{Pair{String, String}, Int}()
    for (i, entry) in enumerate(encoder.table.dynamic_table.entries)
        dyn_dict[entry.name => entry.value] = i
    end

    for header in headers
        name = header.first
        value = header.second
        encode_header(io, encoder, name, value, dyn_dict)
    end

    return take!(io)
end

function hpack_encode_headers(encoder::HPACKEncoder, headers::Dict{String,String})
    header_pairs = [name => value for (name, value) in headers]
    return hpack_encode_headers(encoder, header_pairs)
end

function hpack_encode_headers(encoder::HPACKEncoder, headers::Pair{String,String}...)
    return hpack_encode_headers(encoder, collect(headers))
end

"""
    encode_indexed_header(index::UInt64)

Encode an indexed header field representation (RFC 7541, Section 6.1).

# Arguments
- `index::UInt64`: The index in the header table.

# Returns
- `Vector{UInt8}`: Encoded bytes.

# Usage
```julia
bytes = encode_indexed_header(1)
```
"""
function encode_indexed_header(io::IO, index::UInt64)
    # Η encode_integer γράφει απευθείας, αλλά πρέπει να θέσουμε το πρώτο bit
    iob = IOBuffer()
    encode_integer(iob, index, 7)
    bytes = take!(iob)
    bytes[1] |= 0x80
    write(io, bytes)
end

"""
    encode_literal_with_incremental_indexing(name_index::UInt64, value::String, huffman::Bool)
    encode_literal_with_incremental_indexing(name::String, value::String, huffman::Bool)

Encode a literal header field with incremental indexing (RFC 7541, Section 6.2.1).

# Arguments
- `name_index::UInt64` or `name::String`: Header name or its index.
- `value::String`: Header value.
- `huffman::Bool`: Whether to use Huffman encoding.

# Returns
- `Vector{UInt8}`: Encoded bytes.

# Usage
```julia
bytes = encode_literal_with_incremental_indexing(1, "value", true)
bytes = encode_literal_with_incremental_indexing("custom-header", "value", false)
```
"""
function encode_literal_with_incremental_indexing(io::IO, name_index::UInt64, value::String, encoder::HPACKEncoder)
    iob = IOBuffer()
    encode_integer(iob, name_index, 6)
    bytes = take!(iob)
    bytes[1] |= 0x40
    write(io, bytes)
    encode_string(io, value, encoder.huffman_enabled, encoder.options)
end

function encode_literal_with_incremental_indexing(io::IO, name::String, value::String, encoder::HPACKEncoder)
    write(io, 0x40) # Pattern 01000000 for new name
    encode_string(io, name, encoder.huffman_enabled, encoder.options)
    encode_string(io, value, encoder.huffman_enabled, encoder.options)
end

"""
    encode_literal_without_indexing(name_index::UInt64, value::String, huffman::Bool)
    encode_literal_without_indexing(name::String, value::String, huffman::Bool)

Encode a literal header field without indexing (RFC 7541, Section 6.2.2).

# Arguments
- `name_index::UInt64` or `name::String`: Header name or its index.
- `value::String`: Header value.
- `huffman::Bool`: Whether to use Huffman encoding.

# Returns
- `Vector{UInt8}`: Encoded bytes.

# Usage
```julia
bytes = encode_literal_without_indexing(1, "value", true)
bytes = encode_literal_without_indexing("custom-header", "value", false)
```
"""
function encode_literal_without_indexing(io::IO, name_index::UInt64, value::String, encoder::HPACKEncoder)
    iob = IOBuffer()
    encode_integer(iob, name_index, 4)
    bytes = take!(iob)
    # Pattern 0000xxxx, no extra bits needed
    write(io, bytes)
    encode_string(io, value, encoder.huffman_enabled, encoder.options)
end

function encode_literal_without_indexing(io::IO, name::String, value::String, encoder::HPACKEncoder)
    write(io, 0x00) # Pattern 00000000 for new name
    encode_string(io, name, encoder.huffman_enabled, encoder.options)
    encode_string(io, value, encoder.huffman_enabled, encoder.options)
end

"""
    encode_literal_never_indexed(name_index::UInt64, value::String, huffman::Bool)
    encode_literal_never_indexed(name::String, value::String, huffman::Bool)

Encode a literal header field that must never be indexed (RFC 7541, Section 6.2.3).

# Arguments
- `name_index::UInt64` or `name::String`: Header name or its index.
- `value::String`: Header value.
- `huffman::Bool`: Whether to use Huffman encoding.

# Returns
- `Vector{UInt8}`: Encoded bytes.

# Usage
```julia
bytes = encode_literal_never_indexed(1, "value", true)
bytes = encode_literal_never_indexed("authorization", "secret", false)
```
"""
function encode_literal_never_indexed(io::IO, name_index::UInt64, value::String, encoder::HPACKEncoder)
    iob = IOBuffer()
    encode_integer(iob, name_index, 4)
    bytes = take!(iob)
    bytes[1] |= 0x10 # Pattern 0001xxxx
    write(io, bytes)
    encode_string(io, value, encoder.huffman_enabled, encoder.options)
end

function encode_literal_never_indexed(io::IO, name::String, value::String, encoder::HPACKEncoder)
    write(io, 0x10) # Pattern 00010000 for new name
    encode_string(io, name, encoder.huffman_enabled, encoder.options)
    encode_string(io, value, encoder.huffman_enabled, encoder.options)
end

"""
    encode_table_size_update(max_size::UInt32)

Encode a dynamic table size update instruction (RFC 7541, Section 6.3).

# Arguments
- `max_size::UInt32`: New maximum size for the dynamic table.

# Returns
- `Vector{UInt8}`: Encoded bytes.

# Usage
```julia
bytes = encode_table_size_update(UInt32(4096))
```
"""
function encode_table_size_update(max_size::UInt32)
    encoded = encode_integer(UInt64(max_size), 5)
    encoded[1] |= 0x20  # Set pattern bits 001
    return encoded
end

"""
    is_sensitive_header(name::String)

Check if a header should never be indexed for security reasons.

# Arguments
- `name::String`: Header name.

# Returns
- `Bool`: True if the header is sensitive.

# Usage
```julia
is_sensitive = is_sensitive_header("authorization")
```
"""
function is_sensitive_header(name::String)
    sensitive_headers = Set([
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie"
    ])
    return lowercase(name) in sensitive_headers
end

"""
    determine_encoding_strategy(encoder::HPACKEncoder, name::String, value::String)

Determine the best encoding strategy for a header field.
Returns a tuple `(strategy, name_index)` where `strategy` is a `HeaderSensitivity` enum value.

# Usage
```julia
strategy, index = determine_encoding_strategy(encoder, "content-type", "text/html")
```
"""
function determine_encoding_strategy(encoder::HPACKEncoder, name::String, value::String)
    # Check if header is sensitive (never index)
    if is_sensitive_header(name)
        name_index = find_name_index(encoder.table, name)
        return (HpackTypes.LITERAL_NEVER, name_index)
    end

    # Try to find exact match (name and value)
    exact_index = find_index(encoder.table, name, value)
    if exact_index > 0
        return (HpackTypes.INDEXED, exact_index)
    end

    # For everything else, use incremental indexing to build up the table.
    # Find if the name exists to reuse its index.
    name_index = find_name_index(encoder.table, name)
    return (HpackTypes.LITERAL_INDEXED, name_index)
end

"""
    encode_header(io::IO, encoder::HPACKEncoder, name::String, value::String, dyn_dict, static_name_dict)

Encode a single header field and update the encoder state.
Returns the encoded bytes.

# Usage
```julia
bytes = encode_header(encoder, "content-type", "text/html")
```
"""
function encode_header(io::IO, encoder::HPACKEncoder, name::String, value::String, dyn_dict::Dict{Pair{String, String}, Int})
    # Basic validation
    if !is_valid_header_name(name) || !is_valid_header_value(value)
        throw(HPACKError("Invalid header name or value: $name: $value"))
    end
    if sizeof(name) > encoder.max_header_string_size || sizeof(value) > encoder.max_header_string_size
        throw(HPACKError("Header name or value too large"))
    end

    # --- Stratregy Decision ---

    # 1. Full match in dynamic or static table?
    idx = find_index(encoder.table, name, value, dyn_dict)
    if idx > 0
        encode_indexed_header(io, UInt64(idx))
        return
    end

    # 2. Heuristics: Should we AVOID indexing the value?
    is_sensitive = is_sensitive_header(name)
    if is_sensitive || (name in encoder.options.never_index_value_for_names)
        name_idx = find_name_index(encoder.table, name)
        if name_idx > 0
            encode_literal_never_indexed(io, UInt64(name_idx), value, encoder)
        else
            encode_literal_never_indexed(io, name, value, encoder)
        end
        return
    end

    # 3. Probation logic: Add to dynamic table only if seen enough times
    header_pair = name => value
    count = get!(encoder.candidate_pool, header_pair, 0) + 1
    encoder.candidate_pool[header_pair] = count

    name_idx = find_name_index(encoder.table, name)

    if count >= encoder.options.probation_threshold
        # PROMOTE: Header is frequent enough, add it to the dynamic table.
        if name_idx > 0
            encode_literal_with_incremental_indexing(io, UInt64(name_idx), value, encoder)
        else
            encode_literal_with_incremental_indexing(io, name, value, encoder)
        end
        add!(encoder.table, name, value)
    else
        # ON PROBATION: Don't add to dynamic table yet.
        if name_idx > 0
            encode_literal_without_indexing(io, UInt64(name_idx), value, encoder)
        else
            encode_literal_without_indexing(io, name, value, encoder)
        end
    end
end

"""
    update_table_size!(encoder::HPACKEncoder, max_size::UInt32)

Update the maximum size of the dynamic table. Returns the size update instruction bytes if needed.

# Usage
```julia
bytes = update_table_size!(encoder, UInt32(2048))
```
"""
function update_table_size!(encoder::HPACKEncoder, new_max_size::UInt32)
    current_max = max_size(encoder.table)
    if new_max_size != current_max
        resize!(encoder.table, new_max_size)
        return encode_table_size_update(new_max_size)
    end
    return UInt8[]
end

"""
    reset_encoder!(encoder::HPACKEncoder)

Reset the encoder state (clear dynamic table and candidate pool).

# Usage
```julia
reset_encoder!(encoder)
```
"""
function reset_encoder!(encoder::HPACKEncoder)
    empty!(encoder.table.dynamic_table)
    empty!(encoder.candidate_pool) # Καθαρίζουμε και το candidate pool
    return encoder
end

# Add a Base.show for pretty printing the new encoder
function Base.show(io::IO, encoder::HPACKEncoder)
    table_info = "$(length(encoder.table.dynamic_table.entries)) entries"
    size_info = "$(size(encoder.table))/$(max_size(encoder.table)) bytes"
    candidates = "$(length(encoder.candidate_pool)) candidates"
    print(io, "HPACKEncoder($table_info, $size_info, $candidates)")
end
end