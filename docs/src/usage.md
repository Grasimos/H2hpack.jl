# HPACK.jl Usage Examples

## Basic Header Encoding/Decoding

```julia
using HPACK

encoder = HPACKEncoder()
decoder = HPACKDecoder()
headers = ["content-type" => "text/html", "accept" => "*/*"]
encoded = encode_headers(encoder, headers)
decoded = decode_headers(decoder, encoded)
@show decoded
```

## Integer Encoding/Decoding

```julia
bytes = encode_integer(1337, 5)
val, _ = decode_integer(bytes, 1, 5)
@show bytes, val
```

## String Encoding/Decoding

```julia
str = "hello world"
encoded_str = encode_string(str, true)
decoded_str, _ = decode_string(encoded_str, 1)
@show decoded_str
```

## Huffman Coding

```julia
huff = huffman_encode("hpack")
plain = huffman_decode(huff)
@show huff, plain
```

## Dynamic Table Manipulation

```julia
using HPACK.Tables

dt = DynamicTable(UInt32(128))
add!(dt, "foo", "bar")
@show dt
empty!(dt)
@show dt
```

## Indexing Table

```julia
it = IndexingTable(UInt32(128))
add!(it, "x", "y")
idx = find_index(it, "x", "y")
@show idx
```

## Validation

```julia
@show is_valid_header_name("content-type")
@show is_valid_header_value("ok-value")
```
