# ⚠️ Educational Use Warning

**This HPACK module has made for educational purposes.**

- If you use this code in production, you must ensure strict compliance with the HPACK and HTTP/2 

**Author's intent:** This module is designed as a reference implementation and as a foundation for a full HTTP/2 protocol stack in Julia. Use with care in production environments.

---

# H2hpack.jl

[![Build Status](https://github.com/grasimos/Hpack.jl/workflows/CI/badge.svg)](https://github.com/yourusername/H2hpack.jl/actions)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A pure Julia implementation of [HPACK](https://datatracker.ietf.org/doc/html/rfc7541) (HTTP/2 Header Compression), suitable for use in HTTP/2 clients, servers, and proxies.

## Features
- Full HPACK (RFC 7541) header compression and decompression
- Dynamic/static header tables with RFC-compliant size limits
- Huffman encoding/decoding
- Custom error types for robust error handling
- Context and statistics management for advanced use
- **User-configurable header name/value size limits**
- **Efficient encoding using IOBuffer** for high performance and low memory overhead
- Comprehensive test suite and usage examples

## Installation

```julia
pkg> add H2hpack
```

## Basic Usage

```julia
using H2hpack

# Stateless encoding/decoding
headers = ["content-type" => "text/html", "accept" => "*/*"]
encoded = encode(headers)  # encode(headers; huffman=true)
decoded = decode(encoded)

# Stateful encoding/decoding (with context)
encoder = HPACKEncoder()
decoder = HPACKDecoder()
encoded = encode_headers(encoder, headers)  # encode_headers(encoder, headers::Vector{Pair{String,String}})
decoded = decode_headers(decoder, encoded)

# Custom header string size limit (e.g. 16 KB)
encoder = HPACKEncoder(max_header_string_size=16384)
```

## Advanced Usage

```julia
using H2hpack
ctx = hpack_context(max_table_size=4096, huffman_enabled=true)
stats = get_stats(ctx)
reset_stats!(ctx)
```

See `docs/usage.md` for more detailed examples.

## API Overview

- `encode(headers; huffman=true)`: Stateless header encoding (accepts `Vector{Pair{String,String}}` or `Dict{String,String}}`)
- `decode(data)`: Stateless header decoding
- `HPACKEncoder`, `HPACKDecoder`: Stateful encoders/decoders
- `encode_headers(encoder, headers::Vector{Pair{String,String}})`: Stateful encoding (now requires explicit header vector)
- `decode_headers(decoder, data::Vector{UInt8})`: Stateful decoding
- `hpack_context(; max_table_size=4096, huffman_enabled=true)`: Context creation
- `hpack_stats(; kwargs...)`: Stats object
- `get_stats(ctx)`, `reset_stats!(ctx)`: Context/statistics
- `encode_integer(io::IO, value, prefix_bits)`, `decode_integer(data, pos, prefix_bits)`: HPACK primitives (IOBuffer-based)
- `encode_string(io::IO, s, use_huffman, options)`, `decode_string(data, pos)`: String primitives
- `huffman_encode(s)`, `huffman_decode(data)`: Huffman coding
- `add!`, `find_index`, `find_name_index`, `resize!`, `size`, `max_size`: Table operations
- `is_valid_header_name`, `is_valid_header_value`: Validation

## Documentation

- All public functions and types are documented with Julia docstrings and usage examples reflecting the latest method signatures and IOBuffer-based API.
- See `docs/usage.md` for practical code samples using the current API.
- For RFC details, see [RFC 7541](https://datatracker.ietf.org/doc/html/rfc7541).

## Testing

Run the test suite with:

```julia
using Pkg; Pkg.test("H2hpack")
```

## Benchmark Results

**Machine:** macOS (x86_64-apple-darwin24.0.0), Intel(R) Core(TM) i5-4278U CPU @ 2.60GHz, 4 cores, Julia 1.11.5

### 1000 headers
- Encode (cold): 2.852 ms, size: 8490 bytes
- Decode (cold): 0.307 ms

### 50000 headers
- Encode (cold): 203.5 ms, size: 625236 bytes
- Decode (cold): 23.75 ms
- Encode (warm): 202.33 ms
- Decode (warm): 22.26 ms

*Benchmarks run with single-threaded Julia, BenchmarkTools.jl, on a modern laptop CPU. Actual performance may vary depending on hardware and Julia version.*

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Author

Gerasimos Panou 

