module HpackTypes

export HPACKEncodingOptions, HeaderSensitivity, HeaderEntry, StaticTable, DynamicTable, IndexingTable, HPACKDecoder, HPACKEncoder, HPACKStats, HPACKContext, check_table_size_sync

"""
    HeaderSensitivity

Enum for header sensitivity levels affecting indexing behavior.
- `INDEXED`: Can be indexed and stored in the dynamic table.
- `LITERAL_INDEXED`: Literal with incremental indexing.
- `LITERAL_NEVER`: Literal never indexed (sensitive headers).
- `LITERAL_NOT`: Literal without indexing (this request only).
"""
@enum HeaderSensitivity begin
    INDEXED = 1
    LITERAL_INDEXED = 2
    LITERAL_NEVER = 3
    LITERAL_NOT = 4
end

"""
    HeaderEntry

Represents a single header entry in the HPACK table.

# Fields
- `name::String`: Header name
- `value::String`: Header value
- `size::UInt32`: Size in octets (name + value + 32)
"""
struct HeaderEntry
    name::String
    value::String
    size::UInt32
    function HeaderEntry(name::String, value::String)
        size = UInt32(length(name) + length(value) + 32)
        new(name, value, size)
    end
end

Base.:(==)(a::HeaderEntry, b::HeaderEntry) = a.name == b.name && a.value == b.value

"""
    StaticTable

The static table as defined in RFC 7541 Appendix B.
Contains pre-defined header entries with indices 1-61.

# Fields
- `entries::Vector{HeaderEntry}`: Vector of predefined header entries
"""
struct StaticTable
    entries::Vector{HeaderEntry}
    function StaticTable()
        entries = HeaderEntry[
            HeaderEntry(":authority", ""),
            HeaderEntry(":method", "GET"),
            HeaderEntry(":method", "POST"),
            HeaderEntry(":path", "/"),
            HeaderEntry(":path", "/index.html"),
            HeaderEntry(":scheme", "http"),
            HeaderEntry(":scheme", "https"),
            HeaderEntry(":status", "200"),
            HeaderEntry(":status", "204"),
            HeaderEntry(":status", "206"),
            HeaderEntry(":status", "304"),
            HeaderEntry(":status", "400"),
            HeaderEntry(":status", "404"),
            HeaderEntry(":status", "500"),
            HeaderEntry("accept-charset", ""),
            HeaderEntry("accept-encoding", "gzip, deflate"),
            HeaderEntry("accept-language", ""),
            HeaderEntry("accept-ranges", ""),
            HeaderEntry("accept", ""),
            HeaderEntry("access-control-allow-origin", ""),
            HeaderEntry("age", ""),
            HeaderEntry("allow", ""),
            HeaderEntry("authorization", ""),
            HeaderEntry("cache-control", ""),
            HeaderEntry("content-disposition", ""),
            HeaderEntry("content-encoding", ""),
            HeaderEntry("content-language", ""),
            HeaderEntry("content-length", ""),
            HeaderEntry("content-location", ""),
            HeaderEntry("content-range", ""),
            HeaderEntry("content-type", ""),
            HeaderEntry("cookie", ""),
            HeaderEntry("date", ""),
            HeaderEntry("etag", ""),
            HeaderEntry("expect", ""),
            HeaderEntry("expires", ""),
            HeaderEntry("from", ""),
            HeaderEntry("host", ""),
            HeaderEntry("if-match", ""),
            HeaderEntry("if-modified-since", ""),
            HeaderEntry("if-none-match", ""),
            HeaderEntry("if-range", ""),
            HeaderEntry("if-unmodified-since", ""),
            HeaderEntry("last-modified", ""),
            HeaderEntry("link", ""),
            HeaderEntry("location", ""),
            HeaderEntry("max-forwards", ""),
            HeaderEntry("proxy-authenticate", ""),
            HeaderEntry("proxy-authorization", ""),
            HeaderEntry("range", ""),
            HeaderEntry("referer", ""),
            HeaderEntry("refresh", ""),
            HeaderEntry("retry-after", ""),
            HeaderEntry("server", ""),
            HeaderEntry("set-cookie", ""),
            HeaderEntry("strict-transport-security", ""),
            HeaderEntry("transfer-encoding", ""),
            HeaderEntry("user-agent", ""),
            HeaderEntry("vary", ""),
            HeaderEntry("via", ""),
            HeaderEntry("www-authenticate", "")
        ]
        new(entries)
    end
end

"""
    DynamicTable

The dynamic table for HPACK header compression.
Implements a FIFO buffer with size-based eviction.

# Fields
- `entries::Vector{HeaderEntry}`: Vector of header entries
- `max_size::UInt32`: Maximum allowed size
- `current_size::UInt32`: Current table size
"""
mutable struct DynamicTable
    entries::Vector{HeaderEntry}
    max_size::UInt32
    current_size::UInt32
    function DynamicTable(max_size::UInt32 = UInt32(4096))
        new(HeaderEntry[], max_size, 0)
    end
end

"""
    IndexingTable

Combined indexing table that provides unified access to both static and dynamic tables.

# Fields
- `static_table::StaticTable`: Static table
- `dynamic_table::DynamicTable`: Dynamic table
"""
mutable struct IndexingTable
    static_table::StaticTable
    dynamic_table::DynamicTable
    function IndexingTable(max_dynamic_size::UInt32 = 4096)
        new(StaticTable(), DynamicTable(max_dynamic_size))
    end
end
"""
    HPACKEncodingOptions

Παράμετροι για τη ρύθμιση της "έξυπνης" στρατηγικής κωδικοποίησης.
"""
struct HPACKEncodingOptions
    # Ονόματα κεφαλίδων των οποίων η ΤΙΜΗ δεν πρέπει ποτέ να μπει στον πίνακα
    # (π.χ. "etag", "if-none-match")
    never_index_value_for_names::Set{String}

    # Ελάχιστο ποσοστό εξοικονόμησης για να ενεργοποιηθεί η Huffman
    min_huffman_savings_percent::Int

    # Όριο για την "προαγωγή" μιας κεφαλίδας στον δυναμικό πίνακα.
    # Αν τη δούμε τόσες φορές, την προσθέτουμε.
    probation_threshold::Int

    function HPACKEncodingOptions(;
        never_index_value_for_names::Set{String} = Set(["etag", "if-none-match", "x-request-id", "x-trace-id"]),
        min_huffman_savings_percent::Int = 10,
        probation_threshold::Int = 2
    )
        new(never_index_value_for_names, min_huffman_savings_percent, probation_threshold)
    end
end

"""
    HPACKDecoder

HPACK decoder that maintains dynamic table state and decodes compressed header blocks.

# Fields
- `dynamic_table::DynamicTable`: Dynamic table for state
- `max_table_size::Int`: Maximum table size
- `max_header_list_size::Int`: Maximum header list size
"""
mutable struct HPACKDecoder
    dynamic_table::DynamicTable
    max_table_size::Int
    max_header_list_size::Int
    function HPACKDecoder(max_table_size::UInt32 = UInt32(4096), max_header_list_size::Int = 8192)
        new(DynamicTable(max_table_size), max_table_size, max_header_list_size)
    end
end

"""
    HPACKEncoder

HPACK encoder state maintaining the indexing table and encoding context.
"""
mutable struct HPACKEncoder
    table::IndexingTable
    huffman_enabled::Bool
    max_header_string_size::Int

    # ΝΕΑ ΠΕΔΙΑ ΓΙΑ ΒΕΛΤΙΣΤΟΠΟΙΗΣΗ
    options::HPACKEncodingOptions
    candidate_pool::Dict{Pair{String, String}, Int} # Μετρητής για υποψήφιες κεφαλίδες

    function HPACKEncoder(
        max_table_size::UInt32 = UInt32(4096),
        huffman_enabled::Bool = true;
        max_header_string_size::Int = 8192,
        options::HPACKEncodingOptions = HPACKEncodingOptions()
    )
        new(
            IndexingTable(max_table_size),
            huffman_enabled,
            max_header_string_size,
            options,
            Dict{Pair{String, String}, Int}() # Αρχικοποίηση του candidate pool
        )
    end
end

"""
    HPACKStats

Statistics for HPACK operations monitoring.

# Fields
- `headers_encoded::UInt64`: Number of headers encoded
- `bytes_before_compression::UInt64`: Bytes before compression
- `bytes_after_compression::UInt64`: Bytes after compression
- `headers_decoded::UInt64`: Number of headers decoded
- `dynamic_table_insertions::UInt64`: Dynamic table insertions
- `dynamic_table_evictions::UInt64`: Dynamic table evictions
- `encoding_errors::UInt64`: Encoding errors
- `decoding_errors::UInt64`: Decoding errors
"""
mutable struct HPACKStats
    headers_encoded::UInt64
    bytes_before_compression::UInt64
    bytes_after_compression::UInt64
    headers_decoded::UInt64
    dynamic_table_insertions::UInt64
    dynamic_table_evictions::UInt64
    encoding_errors::UInt64
    decoding_errors::UInt64
    HPACKStats() = new(0, 0, 0, 0, 0, 0, 0, 0)
    HPACKStats(headers_encoded::Integer, bytes_before_compression::Integer, bytes_after_compression::Integer, headers_decoded::Integer, dynamic_table_insertions::Integer, dynamic_table_evictions::Integer, encoding_errors::Integer, decoding_errors::Integer) =
    new(UInt64(headers_encoded), UInt64(bytes_before_compression), UInt64(bytes_after_compression), UInt64(headers_decoded), UInt64(dynamic_table_insertions), UInt64(dynamic_table_evictions), UInt64(encoding_errors), UInt64(decoding_errors))
end

"""
    HPACKContext

Main context for HPACK compression/decompression operations.
Maintains the dynamic table and encoding/decoding state.

# Fields
- `dynamic_table::DynamicTable`: Dynamic table for header compression
- `max_dynamic_table_size::UInt32`: Maximum dynamic table size (bytes)
- `current_dynamic_table_size::UInt32`: Current dynamic table size (bytes)
- `huffman_encoding_enabled::Bool`: Enable Huffman encoding
- `stats::HPACKStats`: Statistics for monitoring
"""
mutable struct HPACKContext
    dynamic_table::DynamicTable
    max_dynamic_table_size::UInt32
    current_dynamic_table_size::UInt32
    huffman_encoding_enabled::Bool
    stats::HPACKStats
    function HPACKContext(max_table_size::UInt32 = UInt32(4096); huffman_enabled::Bool = true)
        dynamic_table = DynamicTable(max_table_size)
        stats = HPACKStats()
        new(dynamic_table, max_table_size, 0, huffman_enabled, stats)
    end
end

function check_table_size_sync(encoder::HPACKEncoder, decoder::HPACKDecoder)
    if encoder.table.dynamic_table.max_size != decoder.max_table_size
        @warn "HPACK: Encoder and decoder dynamic table sizes differ! Encoder=$(encoder.table.dynamic_table.max_size), Decoder=$(decoder.max_table_size). This may cause sync errors."
    end
end

end