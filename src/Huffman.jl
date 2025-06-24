module Huffman

using ..HpackTypes
using ..Exc

export HuffmanEncoder, HuffmanDecoder, HuffmanNode, HUFFMAN_ENCODER, HUFFMAN_DECODER, HUFFMAN_TABLE, huffman_encode, huffman_decode, huffman_encoded_length, should_huffman_encode, is_leaf

"""
    HuffmanNode

Node in the Huffman decoding tree.
"""
mutable struct HuffmanNode 
    symbol::Union{UInt8, Nothing} 
    left::Union{HuffmanNode, Nothing}   
    right::Union{HuffmanNode, Nothing}  
    HuffmanNode(symbol::UInt8) = new(symbol, nothing, nothing)
    HuffmanNode() = new(nothing, nothing, nothing) 
end

"""
    is_leaf(node::HuffmanNode) -> Bool

Return `true` if the given HuffmanNode is a leaf node (contains a symbol).

# Usage
```julia
is_leaf(node)
```
"""
is_leaf(node::HuffmanNode) = node.symbol !== nothing

"""
    build_encoding_table() -> (Vector{UInt32}, Vector{UInt8})

Build the Huffman encoding tables (codes and lengths) from the HPACK Huffman table.

# Usage
```julia
codes, lengths = build_encoding_table()
```
"""
function build_encoding_table()
    codes = Vector{UInt32}(undef, 256)
    lengths = Vector{UInt8}(undef, 256)
    for i in 1:256
        code, length = HUFFMAN_TABLE[i]
        codes[i] = UInt32(code)
        lengths[i] = UInt8(length)
    end
    return codes, lengths
end

"""
    HUFFMAN_TABLE

HPACK Huffman table from RFC 7541 Appendix B. Each entry is a tuple `(code, length)` for symbols 0-255 plus EOS.
"""
const HUFFMAN_TABLE = [
    (0x1ff8, 13), (0x7fffd8, 23), (0xfffffe2, 28), (0xfffffe3, 28),
    (0xfffffe4, 28), (0xfffffe5, 28), (0xfffffe6, 28), (0xfffffe7, 28),
    (0xfffffe8, 28), (0xffffea, 24), (0x3ffffffc, 30), (0xfffffe9, 28),
    (0xfffffea, 28), (0x3ffffffd, 30), (0xfffffeb, 28), (0xfffffec, 28),
    (0xfffffed, 28), (0xfffffee, 28), (0xfffffef, 28), (0xffffff0, 28),
    (0xffffff1, 28), (0xffffff2, 28), (0x3ffffffe, 30), (0xffffff3, 28),
    (0xffffff4, 28), (0xffffff5, 28), (0xffffff6, 28), (0xffffff7, 28),
    (0xffffff8, 28), (0xffffff9, 28), (0xffffffa, 28), (0xffffffb, 28),
    (0x14, 6), (0x3f8, 10), (0x3f9, 10), (0xffa, 12),
    (0x1ff9, 13), (0x15, 6), (0xf8, 8), (0x7fa, 11),
    (0x3fa, 10), (0x3fb, 10), (0xf9, 8), (0x7fb, 11),
    (0xfa, 8), (0x16, 6), (0x17, 6), (0x18, 6),
    (0x0, 5), (0x1, 5), (0x2, 5), (0x19, 6),
    (0x1a, 6), (0x1b, 6), (0x1c, 6), (0x1d, 6),
    (0x1e, 6), (0x1f, 6), (0x5c, 7), (0xfb, 8),
    (0x7ffc, 15), (0x20, 6), (0xffb, 12), (0x3fc, 10),
    (0x1ffa, 13), (0x21, 6), (0x5d, 7), (0x5e, 7),
    (0x5f, 7), (0x60, 7), (0x61, 7), (0x62, 7),
    (0x63, 7), (0x64, 7), (0x65, 7), (0x66, 7),
    (0x67, 7), (0x68, 7), (0x69, 7), (0x6a, 7),
    (0x6b, 7), (0x6c, 7), (0x6d, 7), (0x6e, 7),
    (0x6f, 7), (0x70, 7), (0x71, 7), (0x72, 7),
    (0xfc, 8), (0x73, 7), (0xfd, 8), (0x1ffb, 13),
    (0x7fff0, 19), (0x1ffc, 13), (0x3ffc, 14), (0x22, 6),
    (0x7ffd, 15), (0x3, 5), (0x23, 6), (0x4, 5),
    (0x24, 6), (0x5, 5), (0x25, 6), (0x26, 6),
    (0x27, 6), (0x6, 5), (0x74, 7), (0x75, 7),
    (0x28, 6), (0x29, 6), (0x2a, 6), (0x7, 5),
    (0x2b, 6), (0x76, 7), (0x2c, 6), (0x8, 5),
    (0x9, 5), (0x2d, 6), (0x77, 7), (0x78, 7),
    (0x79, 7), (0x7a, 7), (0x7b, 7), (0x7ffe, 15),
    (0x7fc, 11), (0x3ffd, 14), (0x1ffd, 13), (0xffffffc, 28),
    (0xfffe6, 20), (0x3fffd2, 22), (0xfffe7, 20), (0xfffe8, 20),
    (0x3fffd3, 22), (0x3fffd4, 22), (0x3fffd5, 22), (0x7fffd9, 23),
    (0x3fffd6, 22), (0x7fffda, 23), (0x7fffdb, 23), (0x7fffdc, 23),
    (0x7fffdd, 23), (0x7fffde, 23), (0xffffeb, 24), (0x7fffdf, 23),
    (0xffffec, 24), (0xffffed, 24), (0x3fffd7, 22), (0x7fffe0, 23),
    (0xffffee, 24), (0x7fffe1, 23), (0x7fffe2, 23), (0x7fffe3, 23),
    (0x7fffe4, 23), (0x1fffdc, 21), (0x3fffd8, 22), (0x7fffe5, 23),
    (0x3fffd9, 22), (0x7fffe6, 23), (0x7fffe7, 23), (0xffffef, 24),
    (0x3fffda, 22), (0x1fffdd, 21), (0xfffe9, 20), (0x3fffdb, 22),
    (0x3fffdc, 22), (0x7fffe8, 23), (0x7fffe9, 23), (0x1fffde, 21),
    (0x7fffea, 23), (0x3fffdd, 22), (0x3fffde, 22), (0xfffff0, 24),
    (0x1fffdf, 21), (0x3fffdf, 22), (0x7fffeb, 23), (0x7fffec, 23),
    (0x1fffe0, 21), (0x1fffe1, 21), (0x3fffe0, 22), (0x1fffe2, 21),
    (0x7fffed, 23), (0x3fffe1, 22), (0x7fffee, 23), (0x7fffef, 23),
    (0xffea, 12), (0x3fffe2, 22), (0x3fffe3, 22), (0x3fffe4, 22),
    (0x7ffff0, 23), (0x3fffe5, 22), (0x3fffe6, 22), (0x7ffff1, 23),
    (0x3ffffe0, 26), (0x3ffffe1, 26), (0xfffea, 20), (0x1fffe3, 21),
    (0x3fffe7, 22), (0x7ffff2, 23), (0x3fffe8, 22), (0x1ffffec, 25),
    (0x3ffffe2, 26), (0x3ffffe3, 26), (0x3ffffe4, 26), (0x7ffffde, 27),
    (0x7ffffdf, 27), (0x3ffffe5, 26), (0xfffff1, 24), (0x1ffffed, 25),
    (0x1fffe4, 21), (0x3fffe9, 22), (0x3fffea, 22), (0x1ffffee, 25),
    (0x1ffffef, 25), (0xfffff2, 24), (0x3fffeb, 22), (0x3fffec, 22),
    (0x1ffffff0, 28), (0x1ffffff1, 28), (0x3ffffe6, 26), (0x7ffffe0, 27),
    (0x7ffffe1, 27), (0x3ffffe7, 26), (0x7ffffe2, 27), (0xfffff3, 24),
    (0x3fffed, 22), (0x1fffe5, 21), (0x3fffee, 22), (0x3fffef, 22),
    (0xfffeb, 20), (0xfffec, 20), (0x1fffe6, 21), (0x3ffff0, 22),
    (0x1fffe7, 21), (0x1fffe8, 21), (0x7ffff3, 23), (0x3ffff1, 22),
    (0x1fffe9, 21), (0x1fffea, 21), (0x1fffeb, 21), (0x7ffffe3, 27),
    (0x7ffffe4, 27), (0x7ffffe5, 27), (0xfffed, 20), (0xfffff4, 24),
    (0xfffff5, 24), (0x3ffffe8, 26), (0x3ffffe9, 26), (0xfffffea, 28),
    (0x3ffffffa, 30), (0xfffffeb, 28), (0x7ffffe6, 27), (0x3ffffffb, 30),
    (0xfffffec, 28), (0x3ffffffc, 30), (0xfffffed, 28), (0x3ffffffd, 30),
    # EOS symbol (256)
    (0x3ffffffe, 30)
]

"""
    build_decoding_tree() -> HuffmanNode

Build the Huffman decoding tree from the HPACK Huffman table.

# Usage
```julia
root = build_decoding_tree()
```
"""
function build_decoding_tree()
    root = HuffmanNode()
    for (symbol, (code, length)) in enumerate(HUFFMAN_TABLE[1:256])
        insert_symbol!(root, UInt8(symbol - 1), UInt32(code), UInt8(length))
    end
    return root
end

"""
    insert_symbol!(root::HuffmanNode, symbol::UInt8, code::UInt32, length::UInt8)

Insert a symbol into the Huffman decoding tree.

# Usage
```julia
insert_symbol!(root, symbol, code, length)
```
"""
function insert_symbol!(root::HuffmanNode, symbol::UInt8, code::UInt32, length::UInt8)
    node = root
    for i in (length-1):-1:0
        bit = (code >> i) & 1
        if bit == 0
            if node.left === nothing
                if i == 0
                    node.left = HuffmanNode(symbol)
                else
                    node.left = HuffmanNode()
                end
            end
            node = node.left
        else
            if node.right === nothing
                if i == 0
                    node.right = HuffmanNode(symbol)
                else
                    node.right = HuffmanNode()
                end
            end
            node = node.right
        end
    end
end

"""
    huffman_encode(data::AbstractVector{UInt8}) -> Vector{UInt8}

Encode a byte array using HPACK Huffman coding.

# Usage
```julia
encoded = huffman_encode([0x61, 0x62, 0x63])
```
"""
function huffman_encode(data::AbstractVector{UInt8})
    if isempty(data)
        return UInt8[]
    end
    total_bits = 0
    for byte in data
        total_bits += HUFFMAN_ENCODER.lengths[byte + 1]
    end
    output_bytes = (total_bits + 7) ÷ 8
    result = zeros(UInt8, output_bytes)
    bit_pos = 0
    for byte in data
        code = HUFFMAN_ENCODER.codes[byte + 1]
        len = HUFFMAN_ENCODER.lengths[byte + 1]
        for i in (len-1):-1:0
            byte_idx = (bit_pos ÷ 8) + 1
            bit_in_byte_idx = 7 - (bit_pos % 8)
            if ((code >> i) & 1) == 1
                result[byte_idx] |= (1 << bit_in_byte_idx)
            end
            bit_pos += 1
        end
    end
    if bit_pos % 8 != 0
        byte_idx = (bit_pos ÷ 8) + 1
        result[byte_idx] |= (0xFF >> (bit_pos % 8))
    end
    return result
end

"""
    huffman_encode(s::AbstractString) -> Vector{UInt8}

Encode a string using HPACK Huffman coding.

# Usage
```julia
encoded = huffman_encode("abc")
```
"""
huffman_encode(s::AbstractString) = huffman_encode(Vector{UInt8}(s))

"""
    huffman_decode(data::AbstractVector{UInt8}) -> String

Decode Huffman-encoded data back to a string.

# Usage
```julia
decoded = huffman_decode(encoded)
```
"""
function huffman_decode(data::AbstractVector{UInt8})
    if isempty(data)
        return ""
    end
    result = UInt8[]
    node = HUFFMAN_DECODER.root
    for byte in data
        for bit_idx in 7:-1:0
            bit = (byte >> bit_idx) & 1
            if bit == 0
                node = node.left
            else
                node = node.right
            end
            if node === nothing
                throw(HuffmanDecodingError("Invalid Huffman code encountered"))
            end
            if is_leaf(node)
                push!(result, node.symbol)
                node = HUFFMAN_DECODER.root
            end
        end
    end
    return String(result)
end

"""
    huffman_encoded_length(data::AbstractVector{UInt8}) -> Int

Calculate the length of data after Huffman encoding (in bytes).

# Usage
```julia
len = huffman_encoded_length([0x61, 0x62, 0x63])
```
"""
function huffman_encoded_length(data::AbstractVector{UInt8})
    total_bits = 0
    for byte in data
        total_bits += HUFFMAN_ENCODER.lengths[byte + 1]
    end
    return (total_bits + 7) ÷ 8
end

"""
    huffman_encoded_length(s::AbstractString) -> Int

Calculate the length of a string after Huffman encoding (in bytes).

# Usage
```julia
len = huffman_encoded_length("abc")
```
"""
huffman_encoded_length(s::AbstractString) = huffman_encoded_length(Vector{UInt8}(s))

"""
    should_huffman_encode(data::AbstractVector{UInt8}) -> Bool

Return `true` if Huffman encoding would reduce the size of the data.

# Usage
```julia
should_huffman_encode([0x61, 0x62, 0x63])
```
"""
function should_huffman_encode(data::AbstractVector{UInt8})
    return huffman_encoded_length(data) < length(data)
end

"""
    should_huffman_encode(s::AbstractString) -> Bool

Return `true` if Huffman encoding would reduce the size of the string.

# Usage
```julia
should_huffman_encode("abc")
```
"""
should_huffman_encode(s::AbstractString) = should_huffman_encode(Vector{UInt8}(s))

"""
    HuffmanEncoder

Huffman encoder with precomputed encoding table for HPACK.

# Usage
```julia
encoder = HuffmanEncoder()
```
"""
struct HuffmanEncoder
    codes::Vector{UInt32}
    lengths::Vector{UInt8}
    function HuffmanEncoder()
        codes, lengths = build_encoding_table()
        new(codes, lengths)
    end
end

"""
    HuffmanDecoder

Huffman decoder with prebuilt decoding tree for HPACK.

# Usage
```julia
decoder = HuffmanDecoder()
```
"""
struct HuffmanDecoder
    root::HuffmanNode
    function HuffmanDecoder()
        root = build_decoding_tree()
        new(root)
    end
end

const HUFFMAN_ENCODER = HuffmanEncoder()
const HUFFMAN_DECODER = HuffmanDecoder()

end