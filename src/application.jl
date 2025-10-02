# Application management for ElectronCall.
#
# Handles Electron application lifecycle, process management, and security configuration.

const OptDict = Dict{String,Any}

# Application struct is forward declared in ElectronCall.jl
# Define the fields and internal constructor here
function Application(
    connection::IO,
    proc::Base.Process,
    secure_cookie::Vector{UInt8},
    security_config::SecurityConfig,
    name::String,
)
    app = Application(
        connection,
        proc,
        secure_cookie,
        Window[],
        true,
        security_config,
        name,
        ReentrantLock(),  # Initialize communication lock
    )
    push!(_global_applications, app)
    return app
end

function Base.show(io::IO, app::Application)
    if app.exists
        if length(app.windows) == 1
            appstate = ", [1 window])"
        else
            appstate = ", [$(length(app.windows)) windows])"
        end
    else
        appstate = ", [dead])"
    end
    print(io, "Application(\"$(app.name)\", ", app.connection, ", ", app.proc, appstate)
end

"""
    Application(; kwargs...) -> Application

Create a new Electron application with modern security defaults.

# Keywords
- `name::String = "ElectronCall-App"`: Application name
- `security::SecurityConfig = secure_defaults()`: Security configuration
- `development_mode::Bool = false`: Enable development features
- `additional_electron_args::Vector{String} = String[]`: Additional Electron arguments
- `main_js::String = default_main_js_path()`: Path to main.js file

# Examples
```julia
# Secure application with defaults
app = Application()

# Development application
app = Application(
    development_mode = true,
    security = development_config()
)

# Custom security configuration
app = Application(
    security = SecurityConfig(sandbox = false),
    additional_electron_args = ["--enable-logging", "--v=1"]
)
```
"""
function Application(;
    name::String = "ElectronCall-App",
    security::SecurityConfig = secure_defaults(),
    development_mode::Bool = false,
    additional_electron_args::Vector{String} = String[],
    main_js::String = default_main_js_path(),
)
    @assert isfile(main_js) "Main.js file not found: $main_js"

    # Adjust security for development mode
    if development_mode && security === secure_defaults()
        security = development_config()
        @info "Using development security configuration (some features disabled for debugging)"
    end



    # Validate security configuration
    validate_security_config(security)

    # Get the Electron binary path from Electron_jll
    electron_path = Electron_jll.electron_path

    # Generate unique identifiers for named pipes
    id = replace(string(uuid1()), "-" => "")
    main_pipe_name = generate_pipe_name("elcall-$id")
    sysnotify_pipe_name = generate_pipe_name("elcall-sn-$id")

    # Set up named pipe servers
    server = listen(main_pipe_name)
    sysnotify_server = listen(sysnotify_pipe_name)

    # Generate secure authentication cookie
    secure_cookie = rand(UInt8, 128)
    secure_cookie_encoded = base64encode(secure_cookie)

    # Build Electron command with security-conscious defaults
    # Electron flags must come before the main.js file
    electron_cmd_args = [electron_path]

    # Add sandbox control - default is enabled (opposite of original Electron.jl)
    if !security.sandbox
        push!(electron_cmd_args, "--no-sandbox")
        @warn "Sandbox disabled - this reduces security. Only disable for development/debugging."
    end

    # Add flags for better headless/CI compatibility (Linux only)
    if (haskey(ENV, "GITHUB_ACTIONS") || haskey(ENV, "CI")) && Sys.islinux()
        # Disable GPU and graphics features for headless environments
        push!(electron_cmd_args, "--disable-gpu")
        push!(electron_cmd_args, "--disable-dev-shm-usage")
        push!(electron_cmd_args, "--disable-software-rasterizer")
        # Disable system service dependencies that block in CI
        if security.sandbox  # Only add if not already added above
            push!(electron_cmd_args, "--no-sandbox")
        end
        push!(electron_cmd_args, "--disable-setuid-sandbox")
        push!(electron_cmd_args, "--disable-gpu-sandbox")
        # Most critical: Use stub D-Bus clients to prevent blocking on system services
        push!(electron_cmd_args, "--dbus-stub")
        # Prevent DBus and system service blocking
        push!(electron_cmd_args, "--disable-features=MediaRouter,UserAgentClientHint")
        # Explicitly disable DBus-related features
        push!(electron_cmd_args, "--no-xshm")
        # Disable zygote process to avoid DBus initialization
        push!(electron_cmd_args, "--no-zygote")
        # Disable background networking that may try to access system services
        push!(electron_cmd_args, "--disable-background-networking")
    end

    # Add custom electron arguments (before main.js)
    append!(electron_cmd_args, additional_electron_args)

    # Add main.js and application arguments
    append!(electron_cmd_args, [
        main_js,
        main_pipe_name,
        sysnotify_pipe_name,
        secure_cookie_encoded,
        base64encode(JSON3.write(security)),  # Pass security config to main.js
    ])

    electron_cmd = Cmd(electron_cmd_args)

    # Log command in CI for debugging
    if haskey(ENV, "GITHUB_ACTIONS") || haskey(ENV, "CI")
        @info "Electron command" electron_path main_js args=electron_cmd_args[2:end]
    end

    # Clean environment
    new_env = copy(ENV)
    if haskey(new_env, "ELECTRON_RUN_AS_NODE")
        delete!(new_env, "ELECTRON_RUN_AS_NODE")
    end
    
    # Disable DBus in Linux CI to prevent blocking on system service queries
    # Delete these variables entirely rather than setting to empty string
    if (haskey(ENV, "GITHUB_ACTIONS") || haskey(ENV, "CI")) && Sys.islinux()
        delete!(new_env, "DBUS_SESSION_BUS_ADDRESS")
        delete!(new_env, "DBUS_SYSTEM_BUS_ADDRESS")
        delete!(new_env, "XDG_RUNTIME_DIR")
    end

    # Start Electron process
    main_accept_event = Base.Event()
    sysnotify_accept_event = Base.Event()
    handshake_complete_event = Base.Event()
    monitor_tasks = Task[]

    try
        @info "Starting Electron process..." name main_pipe_name sysnotify_pipe_name
        
        # Redirect both stdout and stderr to Julia's output streams for visibility
        # This is especially important for console.log output in main.js
        proc = open(pipeline(Cmd(electron_cmd, env = new_env), stdout=stdout, stderr=stderr), "w")

        # Monitor for hung connections and unexpected process exits
        push!(monitor_tasks, @async begin
            try
                start_time = time()
                while !isready(main_accept_event)
                    sleep(5)
                    elapsed = round(Int, time() - start_time)
                    running = Base.process_running(proc)
                    if !running
                        exited = Base.process_exited(proc)
                        status = exited ? success(proc) : missing
                        exit_code = exited ? try
                                getfield(proc, :exitcode)
                            catch
                                nothing
                            end : nothing
                        @warn "Electron process no longer running while waiting for main connection, aborting wait" elapsed_seconds = elapsed status exit_code
                        return
                    end
                    @warn "Still waiting for Electron to connect main pipe" elapsed_seconds = elapsed pipe = main_pipe_name pid = getpid(proc)
                end
            catch err
                @debug "Main connection wait monitor encountered an error" exception = err
            end
        end)

        push!(monitor_tasks, @async begin
            try
                wait(main_accept_event)
                start_time = time()
                while !isready(sysnotify_accept_event) && !isready(handshake_complete_event)
                    sleep(5)
                    elapsed = round(Int, time() - start_time)
                    running = Base.process_running(proc)
                    if !running
                        exited = Base.process_exited(proc)
                        status = exited ? success(proc) : missing
                        exit_code = exited ? try
                                getfield(proc, :exitcode)
                            catch
                                nothing
                            end : nothing
                        @warn "Electron process no longer running while waiting for sysnotify connection, aborting wait" elapsed_seconds = elapsed status exit_code
                        return
                    end
                    @warn "Still waiting for Electron to connect sysnotify pipe" elapsed_seconds = elapsed pipe = sysnotify_pipe_name pid = getpid(proc)
                end
            catch err
                @debug "Sysnotify connection wait monitor encountered an error" exception = err
            end
        end)

        push!(monitor_tasks, @async begin
            try
                wait(proc)
                exit_success = success(proc)
                exit_code = try
                    getfield(proc, :exitcode)
                catch
                    nothing
                end
                if !isready(handshake_complete_event)
                    @warn "Electron process exited before completing handshake" exit_success exit_code
                else
                    @info "Electron process exited" exit_success exit_code
                end
            catch err
                @debug "Electron process monitor encountered an error" exception = err
            end
        end)
        
        @info "Electron process started (PID=$(getpid(proc))), waiting for connections..."

        # Accept connections with timeout
        @info "Waiting to accept main connection on $main_pipe_name..."
        sock = accept(server)
        notify(main_accept_event)
        @info "Main connection accepted, waiting for sysnotify connection on $sysnotify_pipe_name..."
        sysnotify_sock = accept(sysnotify_server)
        notify(sysnotify_accept_event)
        @info "Both connections accepted, authenticating..."

        # Authenticate connections
        if read!(sock, zero(secure_cookie)) != secure_cookie
            close.([server, sysnotify_server, sock, sysnotify_sock])
            error("Electron failed to authenticate with proper security token")
        end
        @info "Main connection authenticated successfully"

        if read!(sysnotify_sock, zero(secure_cookie)) != secure_cookie
            close.([server, sysnotify_server, sock, sysnotify_sock])
            error("Electron failed to authenticate with proper security token")
        end
        @info "Sysnotify connection authenticated successfully"

        notify(handshake_complete_event)

        close.([server, sysnotify_server])
        @info "Server sockets closed, application initialization complete"

        # Create application instance
        app = Application(sock, proc, secure_cookie, security, name)

        # Start async notification handler
        @async handle_notifications(app, sysnotify_sock)

        return app

    catch e
        notify(main_accept_event)
        notify(sysnotify_accept_event)
        notify(handshake_complete_event)
        close.([server, sysnotify_server])
        if e isa InterruptException
            rethrow(e)
        end
        error_msg = sprint(showerror, e)
        rethrow(ApplicationError("Failed to start Electron application: $error_msg", nothing))
    end
end

"""
    close(app::Application)

Gracefully shut down the Electron application and all its windows.
"""
function Base.close(app::Application)
    app.exists || error("Cannot close application - already closed")

    # Close all windows first
    while length(app.windows) > 0
        close(first(app.windows))
    end

    app.exists = false
    close(app.connection)

    # Remove from global applications list
    app_index = findfirst(a -> a === app, _global_applications)
    if app_index !== nothing
        deleteat!(_global_applications, app_index)
    end
end

# Helper functions

function generate_pipe_name(name::String)
    return if Sys.iswindows()
        "\\\\.\\pipe\\$name"
    elseif Sys.isunix()
        joinpath(tempdir(), name)
    end
end

function default_main_js_path()
    return normpath(joinpath(@__DIR__, "main.js"))
end

"""
    get_electron_binary_cmd() -> String

Get the path to the Electron binary executable.

This function provides compatibility with Electron.jl's API and returns
the path to the electron executable provided by Electron_jll.

# Examples
```julia
julia> path = get_electron_binary_cmd()
"/path/to/electron"
```
"""
function get_electron_binary_cmd()
    return Electron_jll.electron_path
end

function validate_security_config(config::SecurityConfig)
    # Warn about insecure configurations
    if config.node_integration && config.context_isolation
        @warn "node_integration=true with context_isolation=true may not work as expected"
    end

    if !config.context_isolation && !config.sandbox
        @warn "Disabling both context_isolation and sandbox creates significant security risks"
    end

    # Electron automatically disables sandbox when nodeIntegration is enabled
    # See: https://www.electronjs.org/docs/latest/tutorial/sandbox
    if config.node_integration && config.sandbox
        throw(
            SecurityError(
                "Cannot enable node_integration with sandbox=true. " *
                "Electron automatically disables the sandbox when nodeIntegration is enabled. " *
                "Set sandbox=false explicitly or disable node_integration.",
                "configuration",
            ),
        )
    end
end

"""
Handle system notifications from Electron process.
"""
function handle_notifications(app::Application, sysnotify_sock::IO)
    try
        while app.exists
            try
                line_json = readline(sysnotify_sock)
                isempty(line_json) && break  # EOF

                cmd_parsed = JSON3.read(line_json)

                if cmd_parsed["cmd"] == "windowclosed"
                    handle_window_closed(app, cmd_parsed["winid"])
                elseif cmd_parsed["cmd"] == "appclosing"
                    break
                elseif cmd_parsed["cmd"] == "msg_from_window"
                    handle_window_message(app, cmd_parsed["winid"], cmd_parsed["payload"])
                elseif cmd_parsed["cmd"] == "error"
                    @error "Electron process error: $(cmd_parsed["message"])"
                end
            catch err
                if app.exists  # Only log errors if app is still active
                    @error "Error processing notification" exception = err
                end
            end
        end
    finally
        # Cleanup
        for w in app.windows
            w.exists = false
        end
        empty!(app.windows)
        app.exists = false
        close(sysnotify_sock)
    end
end

function handle_window_closed(app::Application, winid::Int)
    win_index = findfirst(w -> w.id == winid, app.windows)
    if win_index !== nothing
        app.windows[win_index].exists = false
        close(app.windows[win_index].msg_channel)
        deleteat!(app.windows, win_index)
    end
end

function handle_window_message(app::Application, winid::Int, payload)
    win_index = findfirst(w -> w.id == winid, app.windows)
    if win_index !== nothing
        put!(app.windows[win_index].msg_channel, payload)
    end
end
