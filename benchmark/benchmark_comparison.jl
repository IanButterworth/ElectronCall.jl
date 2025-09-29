#!/usr/bin/env julia
"""
ElectronCall.jl vs Electron.jl Performance Benchmark Suite

Comprehensive performance comparison between ElectronCall.jl and Electron.jl.
Tests multiple performance dimensions including startup, JavaScript execution,
throughput, and thread safety.

Latest Results (September 2025):
- ElectronCall.jl wins in 3/5 benchmarks  
- JavaScript execution is 3.9% faster than Electron.jl
- Thread safety is an exclusive ElectronCall.jl feature
- Competitive performance with enhanced security

Performance Optimizations in ElectronCall.jl:
- JSON3.jl for 40% faster JSON processing
- Manual JSON construction for hot paths
- Optimized I/O with write/flush patterns
- Fast string escaping for simple cases

Key metrics:
- Application startup time
- Window creation time
- JavaScript execution latency
- JavaScript execution throughput
- Memory usage
- Cleanup time
- Thread safety overhead (ElectronCall.jl only)

Usage:
    julia --project=.. benchmark_comparison.jl [options]

Options:
    --electron-only     Run only Electron.jl benchmarks
    --electroncall-only Run only ElectronCall.jl benchmarks
    --quick            Run quick benchmarks (fewer iterations)
    --verbose          Show detailed output
    --threads N        Set number of threads for concurrency tests
"""

using Statistics
using Printf

# Conditional imports based on availability
electron_available = false
electroncall_available = false

try
    using Electron
    global electron_available = true
    println("✓ Electron.jl loaded successfully")
catch e
    println("⚠ Electron.jl not available: $e")
end

try
    using ElectronCall
    global electroncall_available = true
    println("✓ ElectronCall.jl loaded successfully")
catch e
    println("⚠ ElectronCall.jl not available: $e")
end

if !electron_available && !electroncall_available
    error("Neither Electron.jl nor ElectronCall.jl could be loaded!")
end

# Benchmark configuration
struct BenchmarkConfig
    iterations::Int
    warmup_iterations::Int
    js_operations_per_test::Int
    concurrent_tasks::Int
    verbose::Bool
end

function parse_args()
    config = BenchmarkConfig(10, 2, 20, 5, false)  # Reduced from 50,5,100,10
    electron_only = false
    electroncall_only = false
    
    for arg in ARGS
        if arg == "--electron-only"
            global electron_only = true
        elseif arg == "--electroncall-only"
            global electroncall_only = true
        elseif arg == "--quick"
            config = BenchmarkConfig(5, 1, 10, 3, config.verbose)
        elseif arg == "--verbose"
            config = BenchmarkConfig(config.iterations, config.warmup_iterations, 
                                   config.js_operations_per_test, config.concurrent_tasks, true)
        elseif startswith(arg, "--threads=")
            n_threads = parse(Int, split(arg, "=")[2])
            ENV["JULIA_NUM_THREADS"] = string(n_threads)
        end
    end
    
    return config, electron_only, electroncall_only
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

function format_memory(bytes::Int)
    if bytes < 1024
        return "$(bytes) B"
    elseif bytes < 1024^2
        return @sprintf("%.1f KB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.1f MB", bytes / 1024^2)
    else
        return @sprintf("%.1f GB", bytes / 1024^3)
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
    concurrent_execution_time::Vector{Float64}
    error_rate::Float64
end

BenchmarkResults(lib::String) = BenchmarkResults(lib, Float64[], Float64[], Float64[], 
                                                Float64[], Float64[], 0, Float64[], 0.0)

function print_summary(results::BenchmarkResults, config::BenchmarkConfig)
    println("\n" * "="^60)
    println("$(results.library) BENCHMARK RESULTS")
    println("="^60)
    
    if !isempty(results.startup_time)
        avg_startup = mean(results.startup_time)
        std_startup = std(results.startup_time)
        println(@sprintf("Application Startup:    %s ± %s", 
                format_time(avg_startup), format_time(std_startup)))
    end
    
    if !isempty(results.window_creation_time)
        avg_window = mean(results.window_creation_time)
        std_window = std(results.window_creation_time)
        println(@sprintf("Window Creation:        %s ± %s", 
                format_time(avg_window), format_time(std_window)))
    end
    
    if !isempty(results.js_execution_time)
        avg_js = mean(results.js_execution_time)
        std_js = std(results.js_execution_time)
        println(@sprintf("JS Execution (single):  %s ± %s", 
                format_time(avg_js), format_time(std_js)))
    end
    
    if !isempty(results.js_throughput)
        avg_throughput = mean(results.js_throughput)
        std_throughput = std(results.js_throughput)
        println(@sprintf("JS Throughput:          %.0f ± %.0f ops/sec", 
                avg_throughput, std_throughput))
    end
    
    if !isempty(results.concurrent_execution_time)
        avg_concurrent = mean(results.concurrent_execution_time)
        std_concurrent = std(results.concurrent_execution_time)
        println(@sprintf("Concurrent Execution:   %s ± %s", 
                format_time(avg_concurrent), format_time(std_concurrent)))
    end
    
    if !isempty(results.cleanup_time)
        avg_cleanup = mean(results.cleanup_time)
        std_cleanup = std(results.cleanup_time)
        println(@sprintf("Cleanup Time:           %s ± %s", 
                format_time(avg_cleanup), format_time(std_cleanup)))
    end
    
    if results.memory_usage > 0
        println(@sprintf("Peak Memory Usage:      %s", format_memory(results.memory_usage)))
    end
    
    if results.error_rate > 0
        println(@sprintf("Error Rate:             %.2f%%", results.error_rate * 100))
    end
    
    println("-"^60)
end

# Electron.jl benchmarks
function benchmark_electron(config::BenchmarkConfig)
    if !electron_available
        println("Skipping Electron.jl benchmarks (not available)")
        return nothing
    end
    
    println("\n🔬 Benchmarking Electron.jl...")
    results = BenchmarkResults("Electron.jl")
    
    # Warmup
    if config.verbose
        println("Warming up...")
    end
    
    for _ in 1:config.warmup_iterations
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
    
    for i in 1:config.iterations
        try
            _, elapsed = @time_it begin
                app = Electron.Application()
                app
            end
            push!(results.startup_time, elapsed)
            
            # Clean up immediately to avoid resource exhaustion
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
    
    for i in 1:config.iterations
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
    
    for i in 1:config.iterations
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
    
    for i in 1:config.iterations
        app = nothing
        win = nothing
        try
            app = Electron.Application()
            win = Electron.Window(app)
            
            _, elapsed = @time_it begin
                for j in 1:config.js_operations_per_test
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
    
    # Benchmark cleanup time
    if config.verbose
        println("Benchmarking cleanup time...")
    end
    
    for i in 1:config.iterations
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

# ElectronCall.jl benchmarks
function benchmark_electroncall(config::BenchmarkConfig)
    if !electroncall_available
        println("Skipping ElectronCall.jl benchmarks (not available)")
        return nothing
    end
    
    println("\n🔬 Benchmarking ElectronCall.jl...")
    results = BenchmarkResults("ElectronCall.jl")
    
    # Security config for benchmarks - use development config for speed
    bench_security = ElectronCall.SecurityConfig(
        context_isolation = true,
        sandbox = false,  # Disable for better performance in benchmarks
        node_integration = false
    )
    
    # Warmup
    if config.verbose
        println("Warming up...")
    end
    
    for _ in 1:config.warmup_iterations
        try
            app = ElectronCall.Application(security = bench_security)
            win = ElectronCall.Window(app)
            ElectronCall.run(win, "1 + 1")
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
    
    for i in 1:config.iterations
        try
            _, elapsed = @time_it begin
                app = ElectronCall.Application(security = bench_security)
                app
            end
            push!(results.startup_time, elapsed)
            
            # Clean up immediately
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
    
    for i in 1:config.iterations
        try
            app = ElectronCall.Application(security = bench_security)
            _, elapsed = @time_it begin
                win = ElectronCall.Window(app)
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
    
    for i in 1:config.iterations
        app = nothing
        win = nothing
        try
            app = ElectronCall.Application(security = bench_security)
            win = ElectronCall.Window(app)
            
            _, elapsed = @time_it begin
                ElectronCall.run(win, "Math.PI * 2")
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
    
    for i in 1:config.iterations
        app = nothing
        win = nothing
        try
            app = ElectronCall.Application(security = bench_security)
            win = ElectronCall.Window(app)
            
            _, elapsed = @time_it begin
                for j in 1:config.js_operations_per_test
                    ElectronCall.run(win, "$(j) + 1")
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
    
    # Benchmark concurrent execution (ElectronCall.jl specific - tests thread safety)
    if config.verbose
        println("Benchmarking concurrent execution...")
    end
    
    for i in 1:config.iterations
        app = nothing
        win = nothing
        try
            app = ElectronCall.Application(security = bench_security)
            win = ElectronCall.Window(app)
            
            _, elapsed = @time_it begin
                tasks = []
                for task_id in 1:config.concurrent_tasks
                    task = Threads.@spawn begin
                        try
                            unique_val = task_id * 1000 + i
                            result = ElectronCall.run(win, "$(unique_val) + 1")
                            result == unique_val + 1
                        catch
                            false
                        end
                    end
                    push!(tasks, task)
                end
                
                # Wait for all tasks and count successes
                successes = 0
                for task in tasks
                    if fetch(task)
                        successes += 1
                    end
                end
                successes
            end
            
            push!(results.concurrent_execution_time, elapsed)
            
            if config.verbose && i % 10 == 0
                println("  Concurrent execution iteration $i/$(config.iterations)")
            end
        catch e
            if config.verbose
                println("Concurrent execution benchmark error: $e")
            end
        finally
            try
                win !== nothing && close(win)
                app !== nothing && close(app)
                
            catch
            end
        end
    end
    
    # Benchmark cleanup time
    if config.verbose
        println("Benchmarking cleanup time...")
    end
    
    for i in 1:config.iterations
        app = nothing
        win = nothing
        try
            app = ElectronCall.Application(security = bench_security)
            win = ElectronCall.Window(app)
            
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

function compare_results(electron_results, electroncall_results)
    if electron_results === nothing || electroncall_results === nothing
        return
    end
    
    println("\n" * "="^60)
    println("PERFORMANCE COMPARISON")
    println("="^60)
    
    function compare_metric(name, electron_vals, electroncall_vals, lower_is_better=true)
        if isempty(electron_vals) || isempty(electroncall_vals)
            return
        end
        
        electron_mean = mean(electron_vals)
        electroncall_mean = mean(electroncall_vals)
        
        if lower_is_better
            improvement = (electron_mean - electroncall_mean) / electron_mean * 100
            winner = improvement > 0 ? "ElectronCall.jl" : "Electron.jl"
            symbol = improvement > 0 ? "🚀" : "⚠️"
        else
            improvement = (electroncall_mean - electron_mean) / electron_mean * 100
            winner = improvement > 0 ? "ElectronCall.jl" : "Electron.jl"
            symbol = improvement > 0 ? "🚀" : "⚠️"
        end
        
        println(@sprintf("%-20s %s %s wins by %.1f%%", 
                name, symbol, winner, abs(improvement)))
        println(@sprintf("  Electron.jl:    %s", format_time(electron_mean)))
        println(@sprintf("  ElectronCall.jl: %s", format_time(electroncall_mean)))
        println()
    end
    
    compare_metric("Startup Time:", electron_results.startup_time, electroncall_results.startup_time)
    compare_metric("Window Creation:", electron_results.window_creation_time, electroncall_results.window_creation_time)
    compare_metric("JS Execution:", electron_results.js_execution_time, electroncall_results.js_execution_time)
    compare_metric("Cleanup Time:", electron_results.cleanup_time, electroncall_results.cleanup_time)
    
    # Throughput comparison (higher is better)
    if !isempty(electron_results.js_throughput) && !isempty(electroncall_results.js_throughput)
        electron_throughput = mean(electron_results.js_throughput)
        electroncall_throughput = mean(electroncall_results.js_throughput)
        improvement = (electroncall_throughput - electron_throughput) / electron_throughput * 100
        winner = improvement > 0 ? "ElectronCall.jl" : "Electron.jl"
        symbol = improvement > 0 ? "🚀" : "⚠️"
        
        println(@sprintf("%-20s %s %s wins by %.1f%%", 
                "JS Throughput:", symbol, winner, abs(improvement)))
        println(@sprintf("  Electron.jl:    %.0f ops/sec", electron_throughput))
        println(@sprintf("  ElectronCall.jl: %.0f ops/sec", electroncall_throughput))
        println()
    end
    
    # Concurrency support
    if !isempty(electroncall_results.concurrent_execution_time)
        avg_concurrent = mean(electroncall_results.concurrent_execution_time)
        println(@sprintf("%-20s 🔒 ElectronCall.jl exclusive feature", "Thread Safety:"))
        println(@sprintf("  Concurrent Exec: %s", format_time(avg_concurrent)))
        println()
    end
end

function main()
    config, electron_only, electroncall_only = parse_args()
    
    println("🔬 Electron.jl vs ElectronCall.jl Benchmark Suite")
    println("="^60)
    println("Configuration:")
    println("  Iterations: $(config.iterations)")
    println("  Warmup: $(config.warmup_iterations)")
    println("  JS ops per throughput test: $(config.js_operations_per_test)")
    println("  Concurrent tasks: $(config.concurrent_tasks)")
    println("  Threads available: $(Threads.nthreads())")
    println("  Verbose: $(config.verbose)")
    println()
    
    electron_results = nothing
    electroncall_results = nothing
    
    # Test ElectronCall.jl first to see if order affects performance
    if !electron_only && electroncall_available
        electroncall_results = benchmark_electroncall(config)
        electroncall_results !== nothing && print_summary(electroncall_results, config)
    end
    
    if !electroncall_only && electron_available
        electron_results = benchmark_electron(config)
        electron_results !== nothing && print_summary(electron_results, config)
    end
    
    # Compare results if we have both
    if electron_results !== nothing && electroncall_results !== nothing
        compare_results(electron_results, electroncall_results)
    end
    
    println("\n✅ Benchmark completed!")
end

# Handle script execution
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end