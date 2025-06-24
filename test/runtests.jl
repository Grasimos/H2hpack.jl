using Test
using HPACK
using Random
using BenchmarkTools: @btime

@testset "HPACK Basic Types" begin
    entry = HeaderEntry("foo", "bar")
    @test entry.name == "foo"
    @test entry.value == "bar"
    @test entry.size == UInt32(length("foo") + length("bar") + 32)
end

@testset "Validation" begin
    @test is_valid_header_name("content-type")
    @test !is_valid_header_name("Content-Type")
    @test is_valid_header_value("abc123")
    @test !is_valid_header_value("abc\x01def")
end

@testset "Huffman Coding" begin
    s = "hello world"
    encoded = huffman_encode(s)
    decoded = huffman_decode(encoded)
    @test decoded == s
    @test should_huffman_encode(s)
    @test huffman_encoded_length(s) == length(huffman_encode(s))
end

@testset "Integer Encoding/Decoding" begin
    for val in [10, 127, 128, 255, 1337, 16384]
        for prefix in 1:8
            bytes = encode_integer(val, prefix)
            decoded, _ = decode_integer(bytes, 1, prefix)
            @test decoded == val
        end
    end
end

@testset "String Encoding/Decoding" begin
    for s in ["abc", "", "header-value", "\twith\ttabs"]
        bytes = encode_string(s, false)
        decoded, _ = decode_string(bytes, 1)
        @test decoded == s
        bytes_h = encode_string(s, true)
        decoded_h, _ = decode_string(bytes_h, 1)
        @test decoded_h == s
    end
end

@testset "Dynamic Table" begin
    using .HPACK.Tables
    dt = DynamicTable(UInt32(4096))
    add!(dt, "a", "1")
    add!(dt, "b", "2")
    @test length(dt) == 2
    empty!(dt)
    @test isempty(dt)
end

@testset "IndexingTable" begin
    using .Tables
    it = IndexingTable(UInt32(128))
    idx = find_index(it, ":method", "GET")
    @test idx > 0
    idx2 = find_name_index(it, ":method")
    @test idx2 > 0
    add!(it, "x", "y")
    @test size(it) > 0
end

@testset "HPACK Encode/Decode" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    headers = ["content-type" => "text/html", "accept" => "*/*"]
    encoded = encode_headers(encoder, headers)
    decoded = decode_headers(decoder, encoded)
    @test Set(decoded) == Set(headers)
end

@testset "Error Handling" begin
    @test_throws HPACKError encode_headers(HPACKEncoder(), ["Invalid Header" => "value\x01"])
    @test_throws HPACKError decode_headers(HPACKDecoder(), UInt8[0xff, 0xff, 0xff])
end

@testset "HPACK Context & Stats" begin
    ctx = hpack_context(max_table_size=256, huffman_enabled=false)
    @test ctx.max_dynamic_table_size == 256
    @test ctx.huffman_encoding_enabled == false
    @test ctx.current_dynamic_table_size == 0
    @test isa(get_stats(ctx), HPACKStats)
    # Simulate stat updates
    ctx.stats.headers_encoded = 5
    ctx.stats.bytes_before_compression = 100
    ctx.stats.bytes_after_compression = 60
    @test get_stats(ctx).headers_encoded == 5
    @test get_stats(ctx).bytes_before_compression == 100
    @test get_stats(ctx).bytes_after_compression == 60
    reset_stats!(ctx)
    @test get_stats(ctx).headers_encoded == 0
    @test get_stats(ctx).bytes_before_compression == 0
    @test get_stats(ctx).bytes_after_compression == 0
    # Test hpack_stats constructor
    stats = hpack_stats(headers_encoded=2, bytes_before_compression=50)
    @test stats.headers_encoded == 2
    @test stats.bytes_before_compression == 50
    @test stats.bytes_after_compression == 0
end

@testset "Stress Test: Large Header Set (Success)" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    decoder.max_header_list_size = 2^31  # allow very large header lists
    headers = ["header$(i)" => "value$(i)" for i in 1:10_000]
    encoded = encode_headers(encoder, headers)
    decoded = decode_headers(decoder, encoded)
    @test Set(decoded) == Set(headers)
end

@testset "Stress Test: Large Header Set (Error, 64KB default)" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    # Common practice: 64 KB (65536 bytes)
    decoder.max_header_list_size = 65536
    headers = ["header$(i)" => "value$(i)" for i in 1:10_000]
    encoded = encode_headers(encoder, headers)
    @test_throws HPACKError decode_headers(decoder, encoded)
end

@testset "Stress Test: Large Header Set (Success, 1 over limit)" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    headers = ["header$(i)" => "value$(i)" for i in 1:10_000]
    # Calculate encoded size and set max_header_list_size to just above it
    encoded = encode_headers(encoder, headers)
    decoder.max_header_list_size = sum(sizeof(h[1]) + sizeof(h[2]) for h in headers) + 1
    decoded = decode_headers(decoder, encoded)
    @test Set(decoded) == Set(headers)
end

@testset "Edge Cases & Fuzzing" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    # Empty header value (allowed), but empty header name (should fail)
    @test_throws HPACKError encode_headers(encoder, ["" => "", "foo" => ""])
    # Header with only control chars (should fail)
    @test_throws HPACKError encode_headers(encoder, ["\x00\x01" => "\x02\x03"])
    # Header with unicode and emoji
    headers = ["x-emoji" => "\U1F600"]
    encoded = encode_headers(encoder, headers)
    decoded = decode_headers(decoder, encoded)
    @test Set(decoded) == Set(headers)
    # Header with null byte (should fail)
    @test_throws HPACKError encode_headers(encoder, ["nul\0" => "ok"])
    # Header with very large value (boundary)
    bigval = "a"^8192
    headers = ["big" => bigval]
    encoded = encode_headers(encoder, headers)
    # Should fail to decode if max_header_list_size is too small
    decoder.max_header_list_size = 100
    @test_throws HPACKError decode_headers(decoder, encoded)
    # Should succeed if limit is large enough
    decoder.max_header_list_size = sum(sizeof(h[1]) + sizeof(h[2]) for h in headers) + 1
    decoded = decode_headers(decoder, encoded)
    @test Set(decoded) == Set(headers)
    # Header with too large value (should fail)
    too_big = "b"^9000
    @test_throws HPACKError encode_headers(encoder, ["fail" => too_big])
    # Fuzz: random bytes as input to decoder
    for _ in 1:10
        data = rand(UInt8, rand(1:100))
        try
            decode_headers(decoder, data)
            # Acceptable: may or may not throw
        catch e
            @test e isa HPACKError || e isa ArgumentError
        end
    end
end

@testset "Security: Header Smuggling/Injection" begin
    encoder = HPACKEncoder()
    # Header with CRLF injection
    @test_throws HPACKError encode_headers(encoder, ["foo\r\nbar" => "baz"])
    # Header with suspicious unicode
    headers = ["x-inject" => "\u202Eevil"]
    encoded = encode_headers(encoder, headers)
    decoded = decode_headers(HPACKDecoder(), encoded)
    @test Set(decoded) == Set(headers)
end

@testset "Error Handling: Malformed Encodings" begin
    decoder = HPACKDecoder()
    # Truncated integer encoding
    data = encode_integer(1337, 5)[1:1]
    malformed = vcat(UInt8(0x80), data)
    @test_throws HPACKError decode_headers(decoder, malformed)
    # Truncated string encoding
    s = encode_string("foo", true)[1:2]
    malformed = vcat(UInt8(0x40), s)
    @test_throws HPACKError decode_headers(decoder, malformed)
    # Invalid table size update
    malformed = UInt8[0x3f, 0xff, 0xff, 0xff, 0xff]
    @test_throws HPACKError decode_headers(decoder, malformed)
end

@testset "Property-based: Random Header Roundtrip" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    for _ in 1:100
        n = rand(1:20)
        # Only generate valid header names (lowercase, no illegal chars)
        headers = ["h$(rand('a':'z', 5) |> String)" => randstring(rand(1:20)) for _ in 1:n]
        encoded = encode_headers(encoder, headers)
        decoded = decode_headers(decoder, encoded)
        @test Set(decoded) == Set(headers)
    end
end

@testset "Property-based: Invalid Header Names" begin
    encoder = HPACKEncoder()
    # Generate header names with uppercase or illegal chars
    for _ in 1:50
        # 50% chance uppercase, 50% chance illegal char
        if rand() < 0.5
            name = rand('A':'Z', 5) |> String
        else
            # Insert an illegal char (e.g. space, @, #, etc.)
            illegal = [' ', '@', '#', '$', '%', '^', '&', '*', '(', ')', '+', '=', '/', '\\', '|', '!', '?']
            pos = rand(1:5)
            arr = [rand('a':'z') for _ in 1:5]
            arr[pos] = rand(illegal)
            name = String(arr)
        end
        value = randstring(rand(1:20))
        @test_throws HPACKError encode_headers(encoder, [name => value])
    end
end

@testset "Cross-compatibility: RFC Example" begin
    # Example from RFC 7541 Appendix C (static table)
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    headers = [":method" => "GET", ":scheme" => "http", ":path" => "/", ":authority" => "www.example.com"]
    encoded = encode_headers(encoder, headers)
    decoded = decode_headers(decoder, encoded)
    @test Set(decoded) == Set(headers)
    # (For full cross-language, compare encoded to known-good bytes from another HPACK implementation)
end

@testset "Thread Safety/Concurrency" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    headers = ["foo" => "bar", "baz" => "qux"]
    results = Vector{Bool}(undef, 10)
    Threads.@threads for i in 1:10
        encoded = encode_headers(encoder, headers)
        decoded = decode_headers(decoder, encoded)
        results[i] = Set(decoded) == Set(headers)
    end
    @test all(results)
end

@testset "Performance Benchmark (Quick)" begin
    using BenchmarkTools
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    headers = ["h$(i)" => "v$(i)" for i in 1:1000]
    @info "Encode 1000 headers" @btime encode_headers($encoder, $headers)
    encoded = encode_headers(encoder, headers)
    @info "Decode 1000 headers" @btime decode_headers($decoder, $encoded)
end

@testset "Doctest Coverage" begin
    # This is a placeholder: run `using Documenter; doctest("HPACK")` in docs/ to check all docstring examples.
    @test true
end

@testset "API Surface Coverage" begin
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    # Try all public API with valid/invalid input
    @test encode_headers(encoder, ["foo" => "bar"]) isa Vector{UInt8}
    @test decode_headers(decoder, encode_headers(encoder, [":method" => "GET"])) isa Vector{Pair{String,String}}
    @test_throws HPACKError encode_headers(encoder, ["" => "bar"]) # invalid name
    @test_throws HPACKError decode_headers(decoder, UInt8[0xff, 0xff]) # invalid data
    # ...add more as needed
end

@testset "Fuzzing: Decoder Robustness" begin
    decoder = HPACKDecoder()
    for _ in 1:100
        data = rand(UInt8, rand(1:200))
        try
            decode_headers(decoder, data)
        catch e
            @test e isa HPACKError || e isa ArgumentError || e isa BoundsError
        end
    end
end
