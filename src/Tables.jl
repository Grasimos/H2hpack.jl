module Tables

using ..HpackTypes
using ..Exc

export IndexingTable, HeaderEntry, add!, find_index, find_name_index, resize!, size, max_size, STATIC_TABLE

const MAX_HEADER_TABLE_SIZE = typemax(UInt32)

"""
    STATIC_TABLE

The static table for HPACK header compression (RFC 7541 Appendix B).

# Usage
```julia
entry = STATIC_TABLE[1]
```
"""
const STATIC_TABLE = StaticTable()

Base.length(st::StaticTable) = length(st.entries)
Base.getindex(st::StaticTable, i::Integer) = st.entries[i]
Base.length(dt::DynamicTable) = length(dt.entries)
Base.isempty(dt::DynamicTable) = isempty(dt.entries)
Base.getindex(dt::DynamicTable, i::Integer) = dt.entries[i]

"""
    resize!(dt::DynamicTable, new_max_size::UInt32)

Resize the dynamic table to a new maximum size. Evicts entries if necessary to fit within the new size limit.

# Usage
```julia
resize!(dt, UInt32(2048))
```
"""
function Base.resize!(dt::DynamicTable, new_max_size::UInt32)
    if new_max_size > MAX_HEADER_TABLE_SIZE
        throw(HPACKOverflowError("Tried to set table size above MAX_HEADER_TABLE_SIZE ($MAX_HEADER_TABLE_SIZE)"))
    end
    dt.max_size = new_max_size
    _evict_to_fit!(dt, UInt32(0))
    return dt
end

function _evict_to_fit!(dt::DynamicTable, additional_size::UInt32)
    while dt.current_size + additional_size > dt.max_size && !isempty(dt.entries)
        removed = pop!(dt.entries)
        dt.current_size -= removed.size
    end
end

"""
    add!(dt::DynamicTable, entry::HeaderEntry)

Add a new entry to the dynamic table. The entry is added at the beginning (index 1) and older entries may be evicted.

# Usage
```julia
add!(dt, HeaderEntry("name", "value"))
```
"""
function add!(dt::DynamicTable, entry::HeaderEntry)
    if entry.size > dt.max_size
        empty!(dt.entries)
        dt.current_size = 0
        return dt
    end
    if entry.size > MAX_HEADER_TABLE_SIZE
        throw(HPACKOverflowError("Entry size $entry.size exceeds MAX_HEADER_TABLE_SIZE ($MAX_HEADER_TABLE_SIZE)"))
    end
    while dt.current_size + entry.size > dt.max_size && !isempty(dt.entries)
        removed = pop!(dt.entries)
        dt.current_size -= removed.size
    end
    pushfirst!(dt.entries, entry)
    dt.current_size += entry.size
    return dt
end

"""
    add!(dt::DynamicTable, name::String, value::String)

Add a new header entry to the dynamic table.

# Usage
```julia
add!(dt, "name", "value")
```
"""
function add!(dt::DynamicTable, name::String, value::String)
    entry = HeaderEntry(name, value)
    if entry.size > dt.max_size
        empty!(dt.entries)
        dt.current_size = 0
        return dt
    end
    if entry.size > MAX_HEADER_TABLE_SIZE
        throw(HPACKOverflowError("Entry size $entry.size exceeds MAX_HEADER_TABLE_SIZE ($MAX_HEADER_TABLE_SIZE)"))
    end
    while dt.current_size + entry.size > dt.max_size && !isempty(dt.entries)
        removed = pop!(dt.entries)
        dt.current_size -= removed.size
    end
    pushfirst!(dt.entries, entry)
    dt.current_size += entry.size
    return dt
end

"""
    empty!(dt::DynamicTable)

Clear all entries from the dynamic table.

# Usage
```julia
empty!(dt)
```
"""
function Base.empty!(dt::DynamicTable)
    empty!(dt.entries)
    dt.current_size = 0
    return dt
end

"""
    getindex(it::IndexingTable, index::Integer)

Get an entry by index from the combined table.
- Index 1-61: Static table entries
- Index 62+: Dynamic table entries (62 is the most recent)

# Usage
```julia
entry = it[1]
```
"""
function Base.getindex(it::IndexingTable, index::Integer)
    if index <= 0
        throw(HPACKBoundsError(it, index))
    elseif index <= length(it.static_table)
        return it.static_table[index]
    else
        dynamic_index = index - length(it.static_table)
        if dynamic_index > length(it.dynamic_table)
            throw(HPACKBoundsError(it, index))
        end
        return it.dynamic_table[dynamic_index]
    end
end

"""
    find_index(it::IndexingTable, name::String, value::String = "")

Find the index of a header entry in the table. Returns the index if found, or 0 if not found. If value is empty, returns the index of the first entry with matching name.

# Usage
```julia
idx = find_index(it, "content-type", "text/html")
```
"""
function find_index(it::IndexingTable, name::String, value::String = "")
    # Fast path: build a Dict for dynamic table if large
    if length(it.dynamic_table.entries) > 32
        dyn_dict = Dict{Tuple{String,String},Int}()
        for (i, entry) in enumerate(it.dynamic_table.entries)
            dyn_dict[(entry.name, entry.value)] = i
        end
        if value == ""
            # Name-only search
            for (i, entry) in enumerate(it.static_table.entries)
                if entry.name == name
                    return i
                end
            end
            for ((n, _), i) in dyn_dict
                if n == name
                    return length(it.static_table) + i
                end
            end
        else
            for (i, entry) in enumerate(it.static_table.entries)
                if entry.name == name && entry.value == value
                    return i
                end
            end
            idx = get(dyn_dict, (name, value), nothing)
            if idx !== nothing
                return length(it.static_table) + idx
            end
        end
        return 0
    end
    # Fallback: original linear search for small tables
    for (i, entry) in enumerate(it.static_table.entries)
        if entry.name == name
            if value == "" || entry.value == value
                return i
            end
        end
    end
    for (i, entry) in enumerate(it.dynamic_table.entries)
        if entry.name == name
            if value == "" || entry.value == value
                return length(it.static_table) + i
            end
        end
    end
    return 0
end

"""
    find_name_index(it::IndexingTable, name::String)

Find the index of the first entry with matching name (regardless of value). Returns the index if found, or 0 if not found.

# Usage
```julia
idx = find_name_index(it, "content-type")
```
"""
function find_name_index(it::IndexingTable, name::String)
    return find_index(it, name, "")
end

"""
    add!(it::IndexingTable, name::String, value::String)

Add a new entry to the dynamic table portion of the indexing table.

# Usage
```julia
add!(it, "name", "value")
```
"""
function add!(it::IndexingTable, name::String, value::String)
    add!(it.dynamic_table, name, value)
end

"""
    add!(it::IndexingTable, entry::HeaderEntry)

Add a new entry to the dynamic table portion of the indexing table.

# Usage
```julia
add!(it, HeaderEntry("name", "value"))
```
"""
function add!(it::IndexingTable, entry::HeaderEntry)
    add!(it.dynamic_table, entry)
end

"""
    resize!(it::IndexingTable, new_max_size::UInt32)

Resize the dynamic table portion of the indexing table.

# Usage
```julia
resize!(it, UInt32(4096))
```
"""
function Base.resize!(it::IndexingTable, new_max_size::UInt32)
    if new_max_size > MAX_HEADER_TABLE_SIZE
        throw(HPACKOverflowError("Tried to set table size above MAX_HEADER_TABLE_SIZE ($MAX_HEADER_TABLE_SIZE)"))
    end
    resize!(it.dynamic_table, new_max_size)
end

"""
    size(it::IndexingTable)

Return the current size of the dynamic table.

# Usage
```julia
sz = size(it)
```
"""
function Base.size(it::IndexingTable)
    return it.dynamic_table.current_size
end

"""
    max_size(it::IndexingTable)

Return the maximum size of the dynamic table.

# Usage
```julia
mx = max_size(it)
```
"""
function max_size(it::IndexingTable)
    return it.dynamic_table.max_size
end

function Base.show(io::IO, entry::HeaderEntry)
    print(io, "HeaderEntry(\"$(entry.name)\", \"$(entry.value)\", $(entry.size))")
end

function Base.show(io::IO, dt::DynamicTable)
    print(io, "DynamicTable($(length(dt.entries)) entries, $(dt.current_size)/$(dt.max_size) bytes)")
end

function Base.show(io::IO, it::IndexingTable)
    static_count = length(it.static_table)
    dynamic_count = length(it.dynamic_table)
    print(io, "IndexingTable(static: $static_count, dynamic: $dynamic_count)")
end

end