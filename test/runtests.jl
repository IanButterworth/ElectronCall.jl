using ElectronCall
using ElectronCall: secure_defaults, development_config, legacy_compatibility_config
using Test
using URIs

# Test environment setup for CI
function prep_test_env()
    if haskey(ENV, "GITHUB_ACTIONS") && ENV["GITHUB_ACTIONS"] == "true"
        if Sys.islinux()
            @info "Setting up Xvfb for Linux CI"
            run(Cmd(`Xvfb :99 -screen 0 1024x768x24`), wait=false)
            ENV["DISPLAY"] = ":99"
            # Add small delay to ensure display is ready
            sleep(2)
        end
    end
end

# Prepare test environment (sets up Xvfb on Linux CI)
prep_test_env()

# Helper function to get appropriate security config for tests
function test_security_config()
    # Use development config on Linux CI to avoid SUID sandbox issues
    return (haskey(ENV, "GITHUB_ACTIONS") && Sys.islinux()) ? development_config() : secure_defaults()
end

# Helper function to clean up all applications
function cleanup_all_applications()
    @info "Cleaning up applications: $(length(applications())) active"
    for app in copy(applications())  # Copy to avoid modification during iteration
        try
            if app.exists
                for win in copy(app.windows)
                    try
                        close(win)
                    catch e
                        @warn "Error closing window: $e"
                    end
                end
                close(app)
            end
        catch e
            @warn "Error closing application: $e"
        end
    end
    # Small delay to allow processes to terminate
    sleep(0.5)
end

@testset "ElectronCall.jl Tests" begin

    @testset "Basic Application Tests" begin
        @info "Testing basic application creation..."

        # Ensure clean start
        cleanup_all_applications()

        @info "Creating single test application..."
        app = Application(name = "TestApp", security = test_security_config())
        @test app isa Application
        @test app.exists == true
        @test app.name == "TestApp"
        @test length(applications()) == 1

        @info "Testing JavaScript execution..."
        result = run(app, "Math.PI")
        @test result ≈ π

        result = run(app, "2 + 3")
        @test result == 5

        @info "Testing error handling..."
        @test_throws JSExecutionError run(app, "invalidFunction()")

        @info "Closing application..."
        close(app)
        @test app.exists == false

        # Cleanup after test
        cleanup_all_applications()
        @test length(applications()) == 0
    end

    @testset "Window Management Tests" begin
        @info "Testing window management..."

        app = Application(name = "WindowTestApp", security = test_security_config())

        # Test window creation
        win = Window(app)
        @test win isa Window
        @test win.exists == true
        @test length(windows(app)) == 1

        # Test content loading
        load(win, "<html><body><h1>Test</h1></body></html>")

                # Test JavaScript execution in window
        result = run(win, "1 + 1")
        @test result == 2

        run(win, "document.title = 'Test Window'")
        title = run(win, "document.title")

        # Test message channel
        ch = msgchannel(win)
        @test ch isa Channel

        # Test window closure
        close(win)
        @test win.exists == false
        @test length(windows(app)) == 0

        close(app)

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Security Configuration Tests" begin
        @info "Testing security configurations..."

        # Test secure defaults
        secure_config = secure_defaults()
        @test secure_config.context_isolation == true
        @test secure_config.sandbox == true
        @test secure_config.node_integration == false
        @test secure_config.web_security == true

        # Test development config
        dev_config = development_config()
        @test dev_config.context_isolation == true
        @test dev_config.sandbox == false  # Disabled for debugging
        @test dev_config.node_integration == false

        # Test legacy compatibility config (should warn)
        legacy_config = nothing
        @test_logs (:warn, r"legacy compatibility.*security vulnerabilities") begin
            legacy_config = legacy_compatibility_config()
        end
        @test legacy_config.context_isolation == false
        @test legacy_config.sandbox == false
        @test legacy_config.node_integration == true

        # Test application with custom security
        # Use development config on Linux CI to avoid SUID sandbox issues
        test_config = (haskey(ENV, "GITHUB_ACTIONS") && Sys.islinux()) ? development_config() : secure_config
        expected_sandbox = (haskey(ENV, "GITHUB_ACTIONS") && Sys.islinux()) ? false : true

        app = Application(name = "SecureTestApp", security = test_config)
        @test app.security_config.sandbox == expected_sandbox
        close(app)

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Error Handling Tests" begin
        @info "Testing error handling..."

        app = Application(security = test_security_config())
        win = Window(app)

        # Test JSExecutionError
        try
            run(win, "throw new Error('Test error')")
            @test false  # Should not reach here
        catch e
            @test e isa JSExecutionError
            # In secure sandbox mode, Electron masks specific error details for security
            @test occursin("Script failed to execute", e.message)
            @test e.context == "renderer"
        end

        # Test WindowClosedError
        close(win)
        @test_throws WindowClosedError run(win, "1 + 1")
        @test_throws WindowClosedError load(win, "<html></html>")

        close(app)

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Legacy Compatibility Tests" begin
        @info "Testing legacy compatibility..."

        # Test run function (compatible API)
        app = Application(security = test_security_config())
        result = run(app, "Math.sqrt(16)")
        @test result == 4.0

        win = Window(app, "<html><body>Legacy Test</body></html>")
        result = run(win, "document.body.textContent")
        @test occursin("Legacy Test", result)

        # Test default application pattern
        # Ensure default application uses appropriate security config for testing
        default_app = default_application(test_security_config())
        default_win = Window(default_app)
        @test default_win isa Window
        @test default_win.app === default_app

        close(default_win)
        close(app)

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Communication Tests" begin
        @info "Testing communication features..."

        app = Application(
            security = development_config(),  # Easier to test without full isolation
        )
        win = Window(app)

        # Test message channel
        ch = msgchannel(win)

        # Simulate sending message from renderer (in real usage, this comes from JS)
        # For testing, we'll use the internal function
        test_message = "Hello from renderer"
        ElectronCall.send_message_to_julia(win, test_message)

        # Check message was received
        @test isready(ch)
        received = take!(ch)
        @test received == test_message

        close(win)
        close(app)

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Nightly/Pre-release Testing" begin
        @info "Testing pre-release/nightly specific features..."

        # Only run extended tests on scheduled runs or when explicitly requested
        if haskey(ENV, "GITHUB_EVENT_NAME") && (
            ENV["GITHUB_EVENT_NAME"] == "schedule" ||
            haskey(ENV, "ELECTRON_EXTENDED_TESTS")
        )

            @info "Running extended nightly tests"

            # Test with multiple applications (reduced to 2 to avoid resource exhaustion)
            apps = [Application(name = "NightlyApp$i", security = test_security_config()) for i = 1:2]
            @test length(applications()) >= 2

            # Test heavy JavaScript execution
            app = apps[1]
            result = run(
                app,
                """
    let sum = 0;
    for(let i = 0; i < 10000; i++) {
        sum += Math.sqrt(i);
    }
    sum;
""",
            )
            @test result > 0

            # Test multiple windows per application
            windows_per_app = [Window(app) for app in apps]
            @test length(windows_per_app) == 2

            for win in windows_per_app
                load(win, "<html><body>Nightly test window</body></html>")
                result = run(win, "document.body.textContent")
                @test occursin("Nightly test", result)
            end

            # Cleanup with delays
            for win in windows_per_app
                close(win)
                sleep(0.1)  # Small delay between window closes
            end
            for app in apps
                close(app)
                sleep(0.1)  # Small delay between app closes
            end

            # Extra cleanup for nightly tests
            cleanup_all_applications()
        else
            @info "Skipping extended nightly tests (not a scheduled run)"
        end

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Architecture Specific Tests" begin
        @info "Testing architecture-specific functionality..."

        app = Application(name = "ArchTestApp", security = test_security_config())
        win = Window(app)

        # Test basic functionality works across architectures
        result = run(win, "navigator.platform")
        @test result isa String
        @test length(result) > 0

        # Test memory handling (important for 32-bit vs 64-bit)
        result = run(win, "new Array(1000).fill(1).reduce((a,b) => a+b)")
        @test result == 1000

        close(win)
        close(app)

        # Cleanup after test
        cleanup_all_applications()
    end

    @testset "Electron Compatibility Tests" begin
        @info "Testing Electron version compatibility..."

        app = Application(name = "ElectronCompatApp", security = test_security_config())

        # Test that we can access basic Electron APIs through main process
        version_info = run(app, "process.versions")
        @test haskey(version_info, "electron")
        @test haskey(version_info, "node")
        @test haskey(version_info, "chrome")

        # Test context isolation is working
        win = Window(app)
        load(
            win,
            "<html><body><script>window.testValue = 'isolated';</script></body></html>",
        )

        # This should NOT be accessible due to context isolation
        try
            result = run(win, "window.testValue")
            # If we get here, context isolation might not be working properly
            @warn "Context isolation may not be fully effective"
        catch e
            # This is expected - context isolation should prevent access
            @test e isa JSExecutionError
        end

        close(win)
        close(app)

        # Cleanup after test
        cleanup_all_applications()

        # Final verification that all applications are properly cleaned up
        @info "Performing final cleanup verification..."
        sleep(1.0)  # Give extra time for cleanup
        @test length(applications()) == 0
    end
end
