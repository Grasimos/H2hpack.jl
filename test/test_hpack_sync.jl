using Test
using Http2Hpack

function test_hpack_sync()
    println("\n--- HPACK Dynamic Table Sync Test ---")
    # Case 1: Static table only (should always succeed)
    static_headers = ["content-type" => "text/html", "accept" => "*/*"]
    encoder = HPACKEncoder()
    decoder = HPACKDecoder()
    encoded = encode_headers(encoder, static_headers)
    decoded = decode_headers(decoder, encoded)
    @test decoded == static_headers
    println("Static table test passed.")

    # Case 2: Dynamic table, same size, custom headers (should succeed)
    custom_headers = ["x-foo" => "bar", "x-bar" => "baz", "x-baz" => "qux"]
    encoder2 = HPACKEncoder(UInt32(4096))
    decoder2 = HPACKDecoder(UInt32(4096))
    encoded2 = encode_headers(encoder2, custom_headers)
    decoded2 = decode_headers(decoder2, encoded2)
    @test decoded2 == custom_headers
    println("Dynamic table (in sync) test passed.")

    # Case 3: Dynamic table, different sizes (should fail or mismatch)
    encoder3 = HPACKEncoder(UInt32(4096))
    decoder3 = HPACKDecoder(UInt32(2048))
    encoded3 = encode_headers(encoder3, custom_headers)
    try
        decoded3 = decode_headers(decoder3, encoded3)
        println("[WARNING] Decoded with mismatched table sizes: ", decoded3)
    catch e
        println("[EXPECTED] Error with mismatched table sizes: ", e)
    end

    # Case 4: Corrupted input (should fail gracefully)
    corrupted = copy(encoded2)
    corrupted[1] = 0xff  # Invalid index
    try
        decode_headers(decoder2, corrupted)
        println("[WARNING] Decoded corrupted input without error!")
    catch e
        println("[EXPECTED] Error with corrupted input: ", e)
    end

    # Case 5: Large repeated custom headers (dynamic table stress)
    repeated_headers = ["x-foo" => "bar", "x-bar" => "baz", "x-baz" => "qux"]
    repeated_headers = vcat([repeated_headers for _ in 1:100]...)
    encoder4 = HPACKEncoder(UInt32(32_768))
    decoder4 = HPACKDecoder(UInt32(32_768))
    encoded4 = encode_headers(encoder4, repeated_headers)
    decoded4 = decode_headers(decoder4, encoded4)
    @test decoded4 == repeated_headers
    println("Large dynamic table sync test passed.")

    println("All HPACK sync tests completed.")
end

test_hpack_sync()
