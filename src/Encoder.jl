module Encoder

using ..HpackTypes, ..Validation
using ..Tables: find_index, find_name_index, add!, max_size, size
using ..Primitives: encode_integer, encode_string
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

function hpack_encode_headers(encoder::HPACKEncoder, headers::Vector{Pair{String,String}})
    result = UInt8[]
    
    for (name, value) in headers
        encoded_header = encode_header(encoder, name, value)
        append!(result, encoded_header)
    end
    
    return result
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
function encode_indexed_header(index::UInt64)
    encoded = encode_integer(index, 7)
    encoded[1] |= 0x80  # Set high bit
    return encoded
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
function encode_literal_with_incremental_indexing(name_index::UInt64, value::String, huffman::Bool)
    # Encode the name index with 6-bit prefix
    index_encoded = encode_integer(name_index, 6)
    index_encoded[1] |= 0x40  # Set pattern bits 01
    
    # Encode the value
    value_encoded = encode_string(value, huffman)
    
    return vcat(index_encoded, value_encoded)
end

function encode_literal_with_incremental_indexing(name::String, value::String, huffman::Bool)
    result = UInt8[0x40]  # Pattern 01000000 (index 0)
    
    # Encode name as string
    name_encoded = encode_string(name, huffman)
    append!(result, name_encoded)
    
    # Encode value as string
    value_encoded = encode_string(value, huffman)
    append!(result, value_encoded)
    
    return result
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
function encode_literal_without_indexing(name_index::UInt64, value::String, huffman::Bool)
    # Encode the name index with 4-bit prefix
    index_encoded = encode_integer(name_index, 4)
    # Pattern is already 0000xxxx (no bits to set)
    
    # Encode the value
    value_encoded = encode_string(value, huffman)
    
    return vcat(index_encoded, value_encoded)
end

function encode_literal_without_indexing(name::String, value::String, huffman::Bool)
    result = UInt8[0x00]  # Pattern 00000000 (index 0)
    
    # Encode name as string
    name_encoded = encode_string(name, huffman)
    append!(result, name_encoded)
    
    # Encode value as string  
    value_encoded = encode_string(value, huffman)
    append!(result, value_encoded)
    
    return result
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
function encode_literal_never_indexed(name_index::UInt64, value::String, huffman::Bool)
    # Encode the name index with 4-bit prefix
    index_encoded = encode_integer(name_index, 4)
    index_encoded[1] |= 0x10  # Set pattern bits 0001
    
    # Encode the value
    value_encoded = encode_string(value, huffman)
    
    return vcat(index_encoded, value_encoded)
end

function encode_literal_never_indexed(name::String, value::String, huffman::Bool)
    result = UInt8[0x10]  # Pattern 00010000 (index 0, never indexed)
    
    # Encode name as string
    name_encoded = encode_string(name, huffman)
    append!(result, name_encoded)
    
    # Encode value as string
    value_encoded = encode_string(value, huffman)
    append!(result, value_encoded)
    
    return result
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
    encode_header(encoder::HPACKEncoder, name::String, value::String)

Encode a single header field and update the encoder state.
Returns the encoded bytes.

# Usage
```julia
bytes = encode_header(encoder, "content-type", "text/html")
```
"""
function encode_header(encoder::HPACKEncoder, name::String, value::String)
    # Validate header name and value
    if !is_valid_header_name(name)
        throw(HPACKError("Invalid header name: $name"))
    end
    if !Validation.is_valid_header_value(value)
        throw(HPACKError("Invalid header value for $name"))
    end
    # Enforce user-configurable HPACK string size limits
    if sizeof(name) > encoder.max_header_string_size
        throw(HPACKError("Header name too large (max $(encoder.max_header_string_size) bytes): $name"))
    end
    if sizeof(value) > encoder.max_header_string_size
        throw(HPACKError("Header value too large (max $(encoder.max_header_string_size) bytes) for $name"))
    end

    strategy, index = determine_encoding_strategy(encoder, name, value)

    if strategy == HpackTypes.LITERAL_NEVER
        # Never indexed (sensitive): pattern 0001xxxx, never add to dynamic table
        if index > 0
            return encode_literal_never_indexed(UInt64(index), value, encoder.huffman_enabled)
        else
            return encode_literal_never_indexed(name, value, encoder.huffman_enabled)
        end
    elseif strategy == HpackTypes.INDEXED
        return encode_indexed_header(UInt64(index))
    elseif strategy == HpackTypes.LITERAL_INDEXED
        if index > 0
            encoded = encode_literal_with_incremental_indexing(UInt64(index), value, encoder.huffman_enabled)
        else
            encoded = encode_literal_with_incremental_indexing(name, value, encoder.huffman_enabled)
        end
        # Add to dynamic table
        add!(encoder.table, name, value)
        return encoded
    else # LITERAL_NOT
        if index > 0
            return encode_literal_without_indexing(UInt64(index), value, encoder.huffman_enabled)
        else
            return encode_literal_without_indexing(name, value, encoder.huffman_enabled)
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

Reset the encoder state (clear dynamic table).

# Usage
```julia
reset_encoder!(encoder)
```
"""
function reset_encoder!(encoder::HPACKEncoder)
    empty!(encoder.table.dynamic_table)
    return encoder
end

function Base.show(io::IO, encoder::HPACKEncoder)
    table_info = "$(length(encoder.table.dynamic_table.entries)) entries"
    size_info = "$(size(encoder.table))/$(max_size(encoder.table)) bytes"
    huffman_info = encoder.huffman_enabled ? "Huffman enabled" : "Huffman disabled"
    print(io, "HPACKEncoder($table_info, $size_info, $huffman_info)")
end

end