# HPACK.jl Documentation

Welcome to the documentation for HPACK.jl, a pure Julia implementation of HTTP/2 header compression (RFC 7541).

- [Usage Examples](usage.md)
- [API Reference](api.md)

## Overview

HPACK.jl provides:
- Stateless and stateful header compression/decompression
- Full RFC 7541 compliance
- Huffman coding
- Dynamic/static table management
- Custom error types and validation
- Context and statistics for advanced use
- **User-configurable header name/value size limits** (see below)

### Configurable Header String Size Limit

You can set the maximum allowed header name/value size (in bytes) per encoder:

```julia
encoder = HPACKEncoder(max_header_string_size=16384)  # Allow up to 16 KB
```

## API Reference

```@docs
HPACK.encode
HPACK.decode
HPACK.encode_headers
HPACK.decode_headers
HPACK.HPACKEncoder
HPACK.HPACKDecoder
HPACK.update_table_size!
HPACK.reset_encoder!
HPACK.reset_decoder!
```


