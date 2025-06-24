module Exc

export HPACKError, HuffmanDecodingError, HPACKBoundsError, HPACKOverflowError

"""
    HPACKError(msg::AbstractString)

Exception type for HPACK protocol errors (encoding/decoding, table bounds, etc).

# Usage
```julia
throw(HPACKError("Header list size exceeds SETTINGS_MAX_HEADER_LIST_SIZE"))
```
"""
struct HPACKError <: Exception
    msg::String
end

Base.showerror(io::IO, e::HPACKError) = print(io, "HPACKError: ", e.msg)

"""
    HuffmanDecodingError(msg::AbstractString)

Exception type for errors during Huffman decoding.

# Usage
```julia
throw(HuffmanDecodingError("Invalid Huffman code encountered"))
```
"""
struct HuffmanDecodingError <: Exception
    msg::String
end

Base.showerror(io::IO, e::HuffmanDecodingError) = print(io, "HuffmanDecodingError: ", e.msg)

"""
    HPACKBoundsError(table, index)

Exception type for out-of-bounds access in HPACK tables.

# Usage
```julia
throw(HPACKBoundsError(table, index))
```
"""
struct HPACKBoundsError <: Exception
    table
    index
end

Base.showerror(io::IO, e::HPACKBoundsError) = print(io, "HPACKBoundsError: index ", e.index, " out of bounds for table ", typeof(e.table))

"""
    HPACKOverflowError(msg::AbstractString)

Exception type for attempts to exceed the maximum allowed HPACK table size.

# Usage
```julia
throw(HPACKOverflowError("Tried to set table size above MAX_HEADER_TABLE_SIZE"))
```
"""
struct HPACKOverflowError <: Exception
    msg::String
end

Base.showerror(io::IO, e::HPACKOverflowError) = print(io, "HPACKOverflowError: ", e.msg)

end