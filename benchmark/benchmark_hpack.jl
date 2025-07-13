push!(LOAD_PATH, "..")
using Http2Hpack
using BenchmarkTools

function benchmark_hpack(; nheaders=50000, ntrials=5)
    println("WARNING: This benchmark will allocate a very large header set (~production scale, $nheaders headers). This may use significant memory and take time.")
    encoder = HPACKEncoder()
    # Set max_header_list_size to 10_000_000 to allow very large header sets
    decoder = HPACKDecoder(UInt32(4096), 10_000_000)
    headers = ["h$(i)" => "v$(i)" for i in 1:nheaders]
    println("Benchmarking HPACK encode_headers for $nheaders headers (cold run)...")
    encode_time = @belapsed encode_headers($encoder, $headers)
    encoded = encode_headers(encoder, headers)
    println("Benchmark")
    try
        decode_time = @belapsed decode_headers($decoder, $encoded)
        println("Encode time: $(encode_time*1000) ms, size: $(length(encoded)) bytes")
        println("Decode time: $(decode_time*1000) ms")
    catch e
        println("[ERROR] Decoding failed: ", e)
    end
    GC.gc()  # Free memory after large test
    println()

    println("Pausing for 30 seconds to let the CPU cool down...")
    sleep(30)
    # Προσθέστε αυτές τις γραμμές για να καθαρίσετε τους πίνακες
    println("Resetting encoder and decoder state for warm run...")
    reset_encoder!(encoder)
    reset_decoder!(decoder)
    # Warm run: reuse encoder/decoder and data
    println("Benchmarking HPACK encode_headers for $nheaders headers (warm run)...")
    warm_encode_time = @belapsed encode_headers($encoder, $headers)
    warm_encoded = encode_headers(encoder, headers)
    println("Benchmarking HPACK decode_headers for $nheaders headers (warm run)...")
    try
        warm_decode_time = @belapsed decode_headers($decoder, $warm_encoded)
        println("Warm encode time: $(warm_encode_time*1000) ms, size: $(length(warm_encoded)) bytes")
        println("Warm decode time: $(warm_decode_time*1000) ms")
    catch e
        println("[ERROR] Warm decoding failed: ", e)
    end
    GC.gc()  # Free memory after warm test
    println()
    # Showcase compression: 10 known, repeated headers
    println("Showcasing HPACK compression with 10 repeated headers...")
    known_headers = ["content-type" => "text/html",
                    "content-length" => "1234",
                    "server" => "nginx",
                    "date" => "Tue, 24 Jun 2025 12:00:00 GMT",
                    "cache-control" => "no-cache",
                    "accept" => "*/*",
                    "user-agent" => "curl/7.79.1",
                    "accept-encoding" => "gzip, deflate",
                    "connection" => "keep-alive",
                    "host" => "example.com"]
    repeated_headers = vcat([known_headers for _ in 1:100]...)
    encoder2 = HPACKEncoder(UInt32(1_000_000))  # Much larger table
    decoder2 = HPACKDecoder(UInt32(1_000_000), 100_000)
    check_table_size_sync(encoder2, decoder2)
    # Use custom headers to exercise dynamic table
    custom_headers = ["x-custom-header$i" => "value$i" for i in 1:10]
    repeated_custom_headers = vcat([custom_headers for _ in 1:100]...)
    batch_size = 10
    nbatches = length(repeated_custom_headers) ÷ batch_size
    println("Showcasing HPACK dynamic table sync with $(nbatches) batches of $batch_size headers...")
    encoder2 = HPACKEncoder(UInt32(1_000_000))
    decoder2 = HPACKDecoder(UInt32(1_000_000), 100_000)
    check_table_size_sync(encoder2, decoder2)
    for batch in 1:nbatches
        batch_headers = repeated_custom_headers[(batch-1)*batch_size+1 : batch*batch_size]
        encoded = encode_headers(encoder2, batch_headers)
        # println("Batch $batch: Encoded size: $(length(encoded)) bytes")
        try
            decoded = decode_headers(decoder2, encoded)
            # println("Batch $batch: Decoded $(length(decoded)) headers, decoder dynamic table entries: ", length(decoder2.dynamic_table.entries))
        catch e
            println("[ERROR] Decoding failed in batch $batch: ", e)
            break
        end
    end
    println("Final encoder dynamic table entries: ", length(encoder2.table.dynamic_table.entries), ", size: ", encoder2.table.dynamic_table.current_size)
    println("Final decoder dynamic table entries: ", length(decoder2.dynamic_table.entries), ", size: ", decoder2.dynamic_table.current_size)
    GC.gc()  # Free memory after compression test

    # Showcase: start with a small dynamic table, then grow it and sync
    println("\nShowcasing dynamic table size growth and sync...")
    encoder3 = HPACKEncoder(UInt32(32))  # Very small table
    decoder3 = HPACKDecoder(UInt32(32), 100_000)
    check_table_size_sync(encoder3, decoder3)
    small_headers = ["x-small-header$i" => "v$i" for i in 1:4]
    println("Initial table size: 32 bytes")
    encoded_small = encode_headers(encoder3, small_headers)
    println("Encoded (small table) size: ", length(encoded_small), " bytes")
    decoded_small = decode_headers(decoder3, encoded_small)
    println("Decoded ", length(decoded_small), " headers, decoder dynamic table entries: ", length(decoder3.dynamic_table.entries))
    # Now grow the table
    new_size = UInt32(256)
    size_update_bytes = update_table_size!(encoder3, new_size)
    println("Growing table to $new_size bytes, emitting size update instruction of ", length(size_update_bytes), " bytes")
    decoder3.max_table_size = new_size  # For realism, but decoder will also process the update instruction
    # Send several batches after grow to show dynamic table filling
    for batch in 1:3
        large_headers = ["x-large-header$i" => "v$(batch)" for i in 1:10]
        encoded_large = vcat(batch == 1 ? size_update_bytes : UInt8[], encode_headers(encoder3, large_headers))
        println("Batch $batch after grow: Encoded size: ", length(encoded_large), " bytes")
        try
            decoded_large = decode_headers(decoder3, encoded_large)
            println("Batch $batch after grow: Decoded ", length(decoded_large), " headers, decoder dynamic table entries: ", length(decoder3.dynamic_table.entries))
        catch e
            println("[ERROR] Decoding failed in batch $batch after grow: ", e)
        end
    end
    println("Final encoder dynamic table entries: ", length(encoder3.table.dynamic_table.entries), ", size: ", encoder3.table.dynamic_table.current_size)
    println("Final decoder dynamic table entries: ", length(decoder3.dynamic_table.entries), ", size: ", decoder3.dynamic_table.current_size)
    GC.gc()  # Free memory after showcase
    nothing
end

function benchmark_hpack_1000()
    nheaders = 1000
    println("\n[1000 entries benchmark] Allocating $nheaders headers...")
    encoder = HPACKEncoder()
    decoder = HPACKDecoder(UInt32(4096), 10_000_000)
    headers = ["h$(i)" => "v$(i)" for i in 1:nheaders]
    println("Benchmarking HPACK encode_headers for $nheaders headers (cold run)...")
    encode_time = @belapsed encode_headers($encoder, $headers)
    encoded = encode_headers(encoder, headers)
    println("Encode time: $(encode_time*1000) ms, size: $(length(encoded)) bytes")
    try
        decode_time = @belapsed decode_headers($decoder, $encoded)
        println("Decode time: $(decode_time*1000) ms")
    catch e
        println("[ERROR] Decoding failed: ", e)
    end
    GC.gc()
    println("\n[1000 entries benchmark complete]")
end

if abspath(PROGRAM_FILE) == @__FILE__
    benchmark_hpack()
    benchmark_hpack_1000()
end
