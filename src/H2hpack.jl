module H2hpack

include("HpackTypes.jl"); using .HpackTypes
include("Validation.jl"); using .Validation
include("Exc.jl"); using .Exc
include("Huffman.jl"); using .Huffman
include("Primitives.jl"); using .Primitives
include("Tables.jl"); using .Tables
include("Encoder.jl"); using .Encoder
include("Decoder.jl"); using .Decoder


export HPACKEncodingOptions, HPACKEncoder, HPACKDecoder, HPACKError, HuffmanDecodingError, HPACKBoundsError, check_table_size_sync
export HeaderSensitivity, HeaderEntry, StaticTable, DynamicTable, IndexingTable, HPACKStats, HPACKContext
export encode_headers, decode_headers, reset_encoder!, reset_decoder!
export hpack_encode_headers, hpack_decode_headers, encode_indexed_header, encode_literal_with_incremental_indexing, encode_literal_without_indexing, encode_literal_never_indexed, encode_table_size_update, is_sensitive_header, determine_encoding_strategy, update_table_size!, set_max_table_size!, set_max_header_list_size!
export HuffmanEncoder, HuffmanDecoder, HuffmanNode, HUFFMAN_ENCODER, HUFFMAN_DECODER, HUFFMAN_TABLE, huffman_encode, huffman_decode, huffman_encoded_length, should_huffman_encode, is_leaf
export encode_integer, decode_integer, encode_string, decode_string, validate_hpack_string, BitBuffer, write_bits!, read_bits, get_bytes
export add!, find_index, find_name_index, resize!, size, max_size, STATIC_TABLE
export is_valid_header_name, is_valid_header_value
export hpack_context, hpack_stats, get_stats, reset_stats!



"""
    encode_headers(encoder::HPACKEncoder, headers) -> Vector{UInt8}
    
Encode a list of HTTP headers using HPACK compression.
The encoder's state (dynamic table) will be updated.
"""
function encode_headers(encoder::HPACKEncoder, headers::Vector{<:Pair})
    try
        # Η λογική είναι ήδη στο Encoder.jl, απλώς την καλούμε.
        return Encoder.hpack_encode_headers(encoder, headers)
    catch e
        rethrow(HPACKError("Header encoding failed: $e"))
    end
end


"""
    decode_headers(decoder::HPACKDecoder, data::Vector{UInt8}) -> Vector{Pair{String, String}}

Decode HPACK-compressed headers.
The decoder's state (dynamic table) will be updated.
"""
function decode_headers(decoder::HPACKDecoder, data::Vector{UInt8})
    try
        return Decoder.hpack_decode_headers(decoder, data)
    catch e
        rethrow(HPACKError("Header decoding failed: $e"))
    end
end


"""
    encode(headers; huffman=true)

Encode headers with a new encoder (stateless, for simple use).
"""
function encode(headers; huffman=true)
    encoder = HPACKEncoder(huffman_enabled=huffman)
    return encode_headers(encoder, headers)
end

"""
    decode(data)

Decode HPACK-compressed headers with a new decoder (stateless, for simple use).
"""
function decode(data)
    decoder = HPACKDecoder()
    return decode_headers(decoder, data)
end

"""
    hpack_context(; max_table_size=4096, huffman_enabled=true)

Create a new HPACKContext for advanced compression/decompression state management.
"""
function hpack_context(; max_table_size=4096, huffman_enabled=true)
    return HPACKContext(UInt32(max_table_size); huffman_enabled=huffman_enabled)
end

"""
    hpack_stats(; kwargs...)

Create a new HPACKStats object, optionally setting fields.
"""
function hpack_stats(; headers_encoded=0, bytes_before_compression=0, bytes_after_compression=0, headers_decoded=0, dynamic_table_insertions=0, dynamic_table_evictions=0, encoding_errors=0, decoding_errors=0)
    return HPACKStats(headers_encoded, bytes_before_compression, bytes_after_compression, headers_decoded, dynamic_table_insertions, dynamic_table_evictions, encoding_errors, decoding_errors)
end

"""
    get_stats(ctx::HPACKContext)

Return the HPACKStats object from a context.
"""
get_stats(ctx::HPACKContext) = ctx.stats

"""
    reset_stats!(ctx::HPACKContext)

Reset all statistics in the context to zero.
"""
function reset_stats!(ctx::HPACKContext)
    ctx.stats = HPACKStats()
    return ctx
end

end
