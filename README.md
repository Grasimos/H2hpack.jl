# ⚠️ Educational Use Warning

**This HPACK module has made for educational purposes.**

- If you use this code in production, you must ensure strict compliance with the HPACK and HTTP/2 specifications, including:
  - Always synchronizing encoder and decoder dynamic table sizes and updates.
  - Never sharing encoder/decoder objects between connections.
  - Processing header blocks and table size updates in strict order.
  - Handling all error cases gracefully (never crash on malformed or out-of-bounds input).

**Author's intent:** This module is designed as a reference implementation and as a foundation for a full HTTP/2 protocol stack in Julia. Use with care in production environments.

---

# HPACK.jl

[![Build Status](https://github.com/grasimos/Hpack.jl/workflows/CI/badge.svg)](https://github.com/yourusername/Hpack.jl/actions)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A pure Julia implementation of [HPACK](https://datatracker.ietf.org/doc/html/rfc7541) (HTTP/2 Header Compression), suitable for use in HTTP/2 clients, servers, and proxies.

## Features
- Full HPACK (RFC 7541) header compression and decompression
- Dynamic/static header tables with RFC-compliant size limits
- Huffman encoding/decoding
- Custom error types for robust error handling
- Context and statistics management for advanced use
- **User-configurable header name/value size limits**
- Comprehensive test suite and usage examples

## Installation

```julia
pkg> add url="https://github.com/grasimos/HPACK.jl.git"
```

## Basic Usage

```julia
using HPACK

# Stateless encoding/decoding
headers = ["content-type" => "text/html", "accept" => "*/*"]
encoded = encode(headers)
decoded = decode(encoded)

# Stateful encoding/decoding (with context)
encoder = HPACKEncoder()
decoder = HPACKDecoder()
encoded = encode_headers(encoder, headers)
decoded = decode_headers(decoder, encoded)

# Custom header string size limit (e.g. 16 KB)
encoder = HPACKEncoder(max_header_string_size=16384)
```

## Advanced Usage

```julia
using HPACK
ctx = hpack_context(max_table_size=4096, huffman_enabled=true)
stats = get_stats(ctx)
reset_stats!(ctx)
```

See `docs/usage.md` for more detailed examples.

## API Overview

- `encode(headers; huffman=true)`: Stateless header encoding
- `decode(data)`: Stateless header decoding
- `HPACKEncoder`, `HPACKDecoder`: Stateful encoders/decoders
- `encode_headers`, `decode_headers`: Stateful operations
- `hpack_context`, `hpack_stats`, `get_stats`, `reset_stats!`: Context and statistics
- `encode_integer`, `decode_integer`, `encode_string`, `decode_string`: HPACK primitives
- `huffman_encode`, `huffman_decode`: Huffman coding
- `add!`, `find_index`, `find_name_index`, `resize!`, `size`, `max_size`: Table operations
- `is_valid_header_name`, `is_valid_header_value`: Validation

## Documentation

- All public functions and types are documented with Julia docstrings and usage examples.
- See `docs/usage.md` for practical code samples.
- For RFC details, see [RFC 7541](https://datatracker.ietf.org/doc/html/rfc7541).

## Testing

Run the test suite with:

```julia
using Pkg; Pkg.test("HPACK")
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Author

Gerasimos Panou <gerasimos.panou@gmail.com>
