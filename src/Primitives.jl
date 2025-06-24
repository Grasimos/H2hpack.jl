module Primitives

using ..HpackTypes
using ..Exc
using ..Huffman
using ..Validation

export encode_integer, decode_integer, encode_string, decode_string, validate_hpack_string, BitBuffer, write_bits!, read_bits, get_bytes, huffman_encode, huffman_decode

"""
    encode_integer(value::Integer, prefix_bits::Int)

Encode an integer using HPACK integer representation with the specified prefix bits.

# Arguments
- `value`: The integer value to encode (must be non-negative)
- `prefix_bits`: Number of bits available in the prefix (1-8)

# Returns
- `Vector{UInt8}`: Encoded bytes

# Examples
```julia
encode_integer(10, 5)  # [0x0a]
encode_integer(1337, 5)  # [0x1f, 0x9a, 0x0a]
```
"""
function encode_integer(value::Integer, prefix_bits::Int)
    @assert 1 <= prefix_bits <= 8 "prefix_bits must be between 1 and 8"
    @assert value >= 0 "value must be non-negative"
    max_prefix_value = (1 << prefix_bits) - 1
    result = UInt8[]
    if value < max_prefix_value
        push!(result, UInt8(value))
    else
        push!(result, UInt8(max_prefix_value))
        value -= max_prefix_value
        while value >= 128
            push!(result, UInt8((value % 128) | 0x80))
            value ÷= 128
        end
        push!(result, UInt8(value))
    end
    return result
end

"""
    decode_integer(data::AbstractVector{UInt8}, offset::Int, prefix_bits::Int, mask::UInt8=UInt8(0))

Decode an integer from HPACK integer representation.

# Arguments
- `data`: Byte array containing the encoded data
- `offset`: Starting position in the data array (1-based)
- `prefix_bits`: Number of bits used for the prefix (1-8)
- `mask`: Mask to apply to the first byte before decoding (default: 0x00)

# Returns
- `(value::Int, new_offset::Int)`: Decoded value and position after the integer

# Examples
```julia
data = [0x0a, 0x1f, 0x9a, 0x0a]
decode_integer(data, 1, 5)  # (10, 2)
decode_integer(data, 2, 5)  # (1337, 5)
```
"""
function decode_integer(data::AbstractVector{UInt8}, offset::Int, prefix_bits::Int, mask::UInt8=UInt8(0))
    @assert 1 <= prefix_bits <= 8 "prefix_bits must be between 1 and 8"
    @assert 1 <= offset <= length(data) "offset out of bounds"
    max_prefix_value = (1 << prefix_bits) - 1
    prefix_mask = UInt8(max_prefix_value)
    first_byte = data[offset] & (~mask)
    value = Int(first_byte & prefix_mask)
    current_offset = offset + 1
    if value < max_prefix_value
        return (value, current_offset)
    end
    multiplier = 1
    while current_offset <= length(data)
        byte = data[current_offset]
        current_offset += 1
        byte_value = Int(byte & 0x7f)
        value += byte_value * multiplier
        if value < 0
            throw(ArgumentError("Integer overflow during HPACK integer decoding"))
        end
        if (byte & 0x80) == 0
            break
        end
        multiplier *= 128
        if multiplier > (1 << 28)
            throw(ArgumentError("HPACK integer encoding uses too many continuation bytes"))
        end
    end
    return (value, current_offset)
end

"""
    encode_string(s::AbstractString, use_huffman::Bool=true)

Encode a string using HPACK string representation. Uses Huffman encoding if `use_huffman` is true and beneficial.

# Examples
```julia
encode_string("hello", true)
encode_string("world", false)
```
"""
function encode_string(s::AbstractString, use_huffman::Bool=true)
    if use_huffman && should_huffman_encode(s)
        encoded_str = huffman_encode(s)
        len_bytes = encode_integer(length(encoded_str), 7)
        len_bytes[1] |= 0x80
        out = Vector{UInt8}(undef, length(len_bytes) + length(encoded_str))
        copyto!(out, 1, len_bytes, 1, length(len_bytes))
        copyto!(out, length(len_bytes)+1, encoded_str, 1, length(encoded_str))
        return out
    else
        str_bytes = codeunits(s)
        len_bytes = encode_integer(length(str_bytes), 7)
        out = Vector{UInt8}(undef, length(len_bytes) + length(str_bytes))
        copyto!(out, 1, len_bytes, 1, length(len_bytes))
        copyto!(out, length(len_bytes)+1, str_bytes, 1, length(str_bytes))
        return out
    end
end

"""
    decode_string(data::Vector{UInt8}, offset::Int)

Decode a string from HPACK string representation.

# Examples
```julia
data = encode_string("hello")
decode_string(data, 1)
```
"""
function decode_string(data::Vector{UInt8}, offset::Int)
    @assert 1 <= offset <= length(data) "offset out of bounds"
    huffman_encoded = (data[offset] & 0x80) != 0
    (str_length, length_end) = decode_integer(data, offset, 7)
    if length_end + str_length - 1 > length(data)
        throw(ArgumentError("Insufficient data for string of length $str_length"))
    end
    str_bytes = data[length_end : length_end + str_length - 1]
    new_offset = length_end + str_length
    if huffman_encoded
        decoded_string = huffman_decode(str_bytes)
    else
        # Avoid unnecessary copy if possible
        decoded_string = unsafe_string(pointer(str_bytes), length(str_bytes))
    end
    if !Validation.is_valid_header_value(decoded_string)
        throw(HPACKError("Invalid header value (control chars) in HPACK data"))
    end
    return (decoded_string, new_offset)
end

"""
    validate_hpack_string(s::AbstractString)

Validate that a string is suitable for HPACK encoding. Checks for null bytes, control characters, and reasonable length.

# Returns
- `Bool`: True if string is valid for HPACK

# Examples
```julia
validate_hpack_string("valid-header")  # true
validate_hpack_string("invalid\x00header")  # false
```
"""
function validate_hpack_string(s::AbstractString)
    if '\0' in s
        return false
    end
    for c in s
        if iscntrl(c) && c != '\t'
            return false
        end
    end
    if sizeof(s) > 8192
        return false
    end
    return true
end

"""
    BitBuffer

A buffer for bit-level operations used in HPACK encoding/decoding. Useful for Huffman coding operations.

# Usage
```julia
buf = BitBuffer()
```
"""
mutable struct BitBuffer
    data::Vector{UInt8}
    bit_offset::Int
    BitBuffer() = new(UInt8[], 0)
end

"""
    write_bits!(buffer::BitBuffer, value::UInt32, num_bits::Int)

Write the specified number of bits from value to the buffer.

# Usage
```julia
write_bits!(buf, 0x1f, 5)
```
"""
function write_bits!(buffer::BitBuffer, value::UInt32, num_bits::Int)
    @assert 0 <= num_bits <= 32 "num_bits must be between 0 and 32"
    if num_bits == 0
        return
    end
    if isempty(buffer.data) || buffer.bit_offset == 8
        push!(buffer.data, 0x00)
        buffer.bit_offset = 0
    end
    remaining_bits = num_bits
    while remaining_bits > 0
        available_bits = 8 - buffer.bit_offset
        bits_to_write = min(remaining_bits, available_bits)
        shift = remaining_bits - bits_to_write
        bits = (value >> shift) & ((1 << bits_to_write) - 1)
        bits <<= (available_bits - bits_to_write)
        buffer.data[end] |= UInt8(bits)
        buffer.bit_offset += bits_to_write
        remaining_bits -= bits_to_write
        if buffer.bit_offset == 8
            if remaining_bits > 0
                push!(buffer.data, 0x00)
                buffer.bit_offset = 0
            end
        end
    end
end

"""
    read_bits(buffer::BitBuffer, num_bits::Int) -> UInt32

Read the specified number of bits from the buffer. Returns the bits as a UInt32 value.

# Usage
```julia
val = read_bits(buf, 5)
```
"""
function read_bits(buffer::BitBuffer, num_bits::Int)
    @assert 0 <= num_bits <= 32 "num_bits must be between 0 and 32"
    if num_bits == 0
        return UInt32(0)
    end
    result = UInt32(0)
    remaining_bits = num_bits
    byte_index = 1
    bit_pos = 0
    while remaining_bits > 0 && byte_index <= length(buffer.data)
        available_bits = 8 - bit_pos
        bits_to_read = min(remaining_bits, available_bits)
        mask = (1 << bits_to_read) - 1
        shift = available_bits - bits_to_read
        bits = (buffer.data[byte_index] >> shift) & mask
        result = (result << bits_to_read) | UInt32(bits)
        bit_pos += bits_to_read
        remaining_bits -= bits_to_read
        if bit_pos == 8
            byte_index += 1
            bit_pos = 0
        end
    end
    return result
end

"""
    get_bytes(buffer::BitBuffer) -> Vector{UInt8}

Get the current bytes from the bit buffer. If there are remaining bits in the last byte, they are included.

# Usage
```julia
bytes = get_bytes(buf)
```
"""
function get_bytes(buffer::BitBuffer)
    return copy(buffer.data)
end

end