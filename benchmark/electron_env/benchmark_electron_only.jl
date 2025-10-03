#!/usr/bin/env julia
"""
Electron.jl Performance Benchmark

Benchmarks Electron.jl performance in isolation with its latest dependencies.
Results can be compared with ElectronCall.jl benchmark results.

Usage:
    julia --project=. benchmark_electron_only.jl [options]

Options:
    --quick            Run quick benchmarks (fewer iterations)
    --verbose          Show detailed output
    --threads N        Set number of threads for concurrency tests
"""

using Statistics
using Printf
using Electron

# Benchmark configuration
struct BenchmarkConfig
    iterations::Int
    warmup_iterations::Int
    js_operations_per_test::Int
    concurrent_tasks::Int
    verbose::Bool
end

function parse_args()
    config = BenchmarkConfig(10, 2, 20, 5, false)

    for arg in ARGS
        if arg == "--quick"
            config = BenchmarkConfig(5, 1, 10, 3, config.verbose)
        elseif arg == "--verbose"
            config = BenchmarkConfig(
                config.iterations,
                config.warmup_iterations,
                config.js_operations_per_test,
                config.concurrent_tasks,
                true,
            )
        elseif startswith(arg, "--threads=")
            n_threads = parse(Int, split(arg, "=")[2])
            ENV["JULIA_NUM_THREADS"] = string(n_threads)
        end
    end

    return config
end

# Utility functions
macro time_it(expr)
    quote
        GC.gc()  # Force garbage collection before timing
        local start_time = time_ns()
        local result = $(esc(expr))
        local end_time = time_ns()
        local elapsed = (end_time - start_time) / 1e6  # Convert to milliseconds
        (result, elapsed)
    end
end

function format_time(ms::Float64)
    if ms < 1.0
        return @sprintf("%.3f μs", ms * 1000)
    elseif ms < 1000.0
        return @sprintf("%.2f ms", ms)
    else
        return @sprintf("%.2f s", ms / 1000)
    end
end

# Benchmark results storage
mutable struct BenchmarkResults
    library::String
    startup_time::Vector{Float64}
    window_creation_time::Vector{Float64}
    js_execution_time::Vector{Float64}
    js_throughput::Vector{Float64}
    cleanup_time::Vector{Float64}
    memory_usage::Int64
    error_rate::Float64
end

BenchmarkResults(lib::String) = BenchmarkResults(
    lib,
    Float64[],
    Float64[],
    Float64[],
    Float64[],
    Float64[],
    0,
    0.0,
)

function print_summary(results::BenchmarkResults, config::BenchmarkConfig)
    println("\n" * "="^60)
    println("$(results.library) BENCHMARK RESULTS")
    println("="^60)

    if !isempty(results.startup_time)
        avg_startup = mean(results.startup_time)
        std_startup = std(results.startup_time)
        println(
            @sprintf(
                "Application Startup:    %s ± %s",
                format_time(avg_startup),
                format_time(std_startup)
            )
        )
    end

    if !isempty(results.window_creation_time)
        avg_window = mean(results.window_creation_time)
        std_window = std(results.window_creation_time)
        println(
            @sprintf(
                "Window Creation:        %s ± %s",
                format_time(avg_window),
                format_time(std_window)
            )
        )
    end

    if !isempty(results.js_execution_time)
        avg_js = mean(results.js_execution_time)
        std_js = std(results.js_execution_time)
        println(
            @sprintf(
                "JS Execution (single):  %s ± %s",
                format_time(avg_js),
                format_time(std_js)
            )
        )
    end

    if !isempty(results.js_throughput)
        avg_throughput = mean(results.js_throughput)
        std_throughput = std(results.js_throughput)
        println(
            @sprintf(
                "JS Throughput:          %.0f ± %.0f ops/sec",
                avg_throughput,
                std_throughput
            )
        )
    end

    if !isempty(results.cleanup_time)
        avg_cleanup = mean(results.cleanup_time)
        std_cleanup = std(results.cleanup_time)
        println(
            @sprintf(
                "Cleanup Time:           %s ± %s",
                format_time(avg_cleanup),
                format_time(std_cleanup)
            )
        )
    end

    if results.error_rate > 0
        println(@sprintf("Error Rate:             %.1f%%", results.error_rate * 100))
    end

    println("="^60)
end

# Electron.jl benchmarks
function benchmark_electron(config::BenchmarkConfig)
    println("\n🔬 Benchmarking Electron.jl...")
    results = BenchmarkResults("Electron.jl")

    # Warmup
    if config.verbose
        println("Warming up...")
    end

    for _ = 1:config.warmup_iterations
        try
            app = Electron.Application()
            win = Electron.Window(app)
            Electron.run(win, "1 + 1")
            close(win)
            close(app)
        catch e
            if config.verbose
                println("Warmup error: $e")
            end
        end
    end

    # Benchmark application startup
    if config.verbose
        println("Benchmarking application startup...")
    end

    for i = 1:config.iterations
        try
            _, elapsed = @time_it begin
                app = Electron.Application()
                app
            end
            push!(results.startup_time, elapsed)

            try
                close(app)
            catch
            end

            if config.verbose && i % 10 == 0
                println("  Startup iteration $i/$(config.iterations)")
            end
        catch e
            if config.verbose
                println("Startup benchmark error: $e")
            end
        end
    end

    # Benchmark window creation
    if config.verbose
        println("Benchmarking window creation...")
    end

    for i = 1:config.iterations
        try
            app = Electron.Application()
            _, elapsed = @time_it begin
                win = Electron.Window(app)
                win
            end
            push!(results.window_creation_time, elapsed)

            close(app)

            if config.verbose && i % 10 == 0
                println("  Window creation iteration $i/$(config.iterations)")
            end
        catch e
            if config.verbose
                println("Window creation benchmark error: $e")
            end
        end
    end

    # Benchmark JavaScript execution
    if config.verbose
        println("Benchmarking JavaScript execution...")
    end

    for i = 1:config.iterations
        app = nothing
        win = nothing
        try
            app = Electron.Application()
            win = Electron.Window(app)

            _, elapsed = @time_it begin
                Electron.run(win, "Math.PI * 2")
            end
            push!(results.js_execution_time, elapsed)

            if config.verbose && i % 10 == 0
                println("  JS execution iteration $i/$(config.iterations)")
            end
        catch e
            if config.verbose
                println("JS execution benchmark error: $e")
            end
        finally
            try
                win !== nothing && close(win)
                app !== nothing && close(app)
            catch
            end
        end
    end

    # Benchmark JavaScript throughput
    if config.verbose
        println("Benchmarking JavaScript throughput...")
    end

    for i = 1:config.iterations
        app = nothing
        win = nothing
        try
            app = Electron.Application()
            win = Electron.Window(app)

            _, elapsed = @time_it begin
                for j = 1:config.js_operations_per_test
                    Electron.run(win, "$(j) + 1")
                end
            end

            throughput = config.js_operations_per_test / (elapsed / 1000)  # ops per second
            push!(results.js_throughput, throughput)

            if config.verbose && i % 10 == 0
                println("  Throughput iteration $i/$(config.iterations)")
            end
        catch e
            if config.verbose
                println("Throughput benchmark error: $e")
            end
        finally
            try
                win !== nothing && close(win)
                app !== nothing && close(app)
            catch
            end
        end
    end

    # Benchmark cleanup
    if config.verbose
        println("Benchmarking cleanup...")
    end

    for i = 1:config.iterations
        app = nothing
        win = nothing
        try
            app = Electron.Application()
            win = Electron.Window(app)

            _, elapsed = @time_it begin
                close(win)
                close(app)
            end
            push!(results.cleanup_time, elapsed)

            if config.verbose && i % 10 == 0
                println("  Cleanup iteration $i/$(config.iterations)")
            end
        catch e
            if config.verbose
                println("Cleanup benchmark error: $e")
            end
        end
    end

    return results
end

function main()
    config = parse_args()

    println("🔬 Electron.jl Benchmark Suite")
    println("="^60)
    println("Configuration:")
    println("  Iterations: $(config.iterations)")
    println("  Warmup: $(config.warmup_iterations)")
    println("  JS ops per throughput test: $(config.js_operations_per_test)")
    println("  Concurrent tasks: $(config.concurrent_tasks)")
    println("  Threads available: $(Threads.nthreads())")
    println("  Verbose: $(config.verbose)")
    println()

    results = benchmark_electron(config)
    print_summary(results, config)

    println("\n✅ Electron.jl benchmark completed!")
end

# Handle script execution
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end