#!/usr/bin/env julia
"""
Benchmark Results Comparison Tool

Runs both Electron.jl and ElectronCall.jl benchmarks in separate environments
and compares the results.

Usage:
    julia compare_benchmarks.jl [options]

Options:
    --quick            Run quick benchmarks (fewer iterations)
    --verbose          Show detailed output
    --electron-only    Run only Electron.jl benchmarks
    --electroncall-only Run only ElectronCall.jl benchmarks
"""

using Printf

function run_electron_benchmark(args...)
    println("🔬 Running Electron.jl benchmark in isolated environment...")
    electron_cmd = `julia --project=benchmark/electron_env benchmark/electron_env/benchmark_electron_only.jl $args`
    
    try
        run(electron_cmd)
        return true
    catch e
        println("❌ Electron.jl benchmark failed: $e")
        return false
    end
end

function run_electroncall_benchmark(args...)
    println("🔬 Running ElectronCall.jl benchmark in isolated environment...")
    electroncall_cmd = `julia --project=benchmark/electroncall_env benchmark/electroncall_env/benchmark_electroncall_only.jl $args`
    
    try
        run(electroncall_cmd)
        return true
    catch e
        println("❌ ElectronCall.jl benchmark failed: $e")
        return false
    end
end

function setup_environments()
    println("📦 Setting up benchmark environments...")
    
    # Setup Electron.jl environment
    println("  Setting up Electron.jl environment...")
    try
        run(`julia --project=benchmark/electron_env -e "using Pkg; Pkg.instantiate()"`)
        println("  ✅ Electron.jl environment ready")
    catch e
        println("  ❌ Failed to setup Electron.jl environment: $e")
        return false
    end
    
    # Setup ElectronCall.jl environment (use dev version from current directory)
    println("  Setting up ElectronCall.jl environment...")
    try
        run(`julia --project=benchmark/electroncall_env -e "using Pkg; Pkg.develop(path=\".\"); Pkg.instantiate()"`)
        println("  ✅ ElectronCall.jl environment ready")
    catch e
        println("  ❌ Failed to setup ElectronCall.jl environment: $e")
        return false
    end
    
    return true
end

function main()
    # Parse command line arguments
    electron_only = false
    electroncall_only = false
    benchmark_args = String[]
    
    for arg in ARGS
        if arg == "--electron-only"
            electron_only = true
        elseif arg == "--electroncall-only"
            electroncall_only = true
        else
            push!(benchmark_args, arg)
        end
    end
    
    println("🔬 Electron.jl vs ElectronCall.jl Isolated Benchmark Comparison")
    println("="^70)
    println("This tool runs benchmarks in separate environments to ensure")
    println("each library uses its optimal dependency versions.")
    println("="^70)
    
    # Setup environments
    if !setup_environments()
        println("❌ Failed to setup benchmark environments")
        return 1
    end
    
    println("\n🚀 Running benchmarks...")
    println("="^50)
    
    electron_success = false
    electroncall_success = false
    
    # Run ElectronCall.jl benchmark first (current development version)
    if !electron_only
        electroncall_success = run_electroncall_benchmark(benchmark_args...)
        if electroncall_success
            println("\n✅ ElectronCall.jl benchmark completed successfully")
        end
    end
    
    # Run Electron.jl benchmark
    if !electroncall_only
        if !electron_only
            println("\n" * "="^50)
        end
        electron_success = run_electron_benchmark(benchmark_args...)
        if electron_success
            println("\n✅ Electron.jl benchmark completed successfully")
        end
    end
    
    println("\n" * "="^70)
    
    if electron_success && electroncall_success
        println("🎉 Both benchmarks completed successfully!")
        println("📊 Compare the results above to see performance differences.")
        println("💡 Key advantages of ElectronCall.jl:")
        println("   - Thread safety (concurrent execution)")
        println("   - Enhanced security configurations")
        println("   - JSON.jl v1.0.0 for optimized JSON processing")
        println("   - Manual JSON construction for hot paths")
    elseif electron_success
        println("✅ Electron.jl benchmark completed successfully")
        if !electroncall_only
            println("❌ ElectronCall.jl benchmark failed")
        end
    elseif electroncall_success
        println("✅ ElectronCall.jl benchmark completed successfully")
        if !electron_only
            println("❌ Electron.jl benchmark failed")
        end
    else
        println("❌ Both benchmarks failed")
        return 1
    end
    
    return 0
end

# Handle script execution
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end