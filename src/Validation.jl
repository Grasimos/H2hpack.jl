module Validation

export is_valid_header_name, is_valid_header_value 
"""
    is_valid_header_name(name::AbstractString) -> Bool

Return true if the header name is valid (lowercase, no illegal characters).
"""
function is_valid_header_name(name::AbstractString)
    isempty(name) && return false
    for c in name
        if !('a' <= c <= 'z' || c == '-' || c == '_' || '0' <= c <= '9' || c == ':')
            return false
        end
    end
    return true
end

"""
    is_valid_header_value(value::AbstractString) -> Bool

Return true if the header value is valid (no control chars except tab).
"""
function is_valid_header_value(value::AbstractString)
    for c in value
        if iscntrl(c) && c != '\t'
            return false
        end
    end
    return true
end

end