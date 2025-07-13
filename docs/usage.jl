# HPACK.jl Usage Examples

using Http2Hpack

# --- Basic Header Encoding/Decoding ---
encoder = HPACKEncoder()
decoder = HPACKDecoder()
headers = ["content-type" => "text/html", "accept" => "*/*"]
encoded = encode_headers(encoder, headers)
decoded = decode_headers(decoder, encoded)
@show decoded

# --- Integer Encoding/Decoding ---
bytes = encode_integer(1337, 5)
val, _ = decode_integer(bytes, 1, 5)
@show bytes, val

# --- String Encoding/Decoding ---
str = "hello world"
encoded_str = encode_string(str, true)
decoded_str, _ = decode_string(encoded_str, 1)
@show decoded_str

# --- Huffman Coding ---
huff = huffman_encode("hpack")
plain = huffman_decode(huff)
@show huff, plain

# --- Dynamic Table Manipulation ---
using .Tables
dt = DynamicTable(UInt32(128))
add!(dt, "foo", "bar")
@show dt
empty!(dt)
@show dt

# --- Indexing Table ---
it = IndexingTable(UInt32(128))
add!(it, "x", "y")
idx = find_index(it, "x", "y")
@show idx

# --- Validation ---
@show is_valid_header_name("content-type")
@show is_valid_header_value("ok-value")
