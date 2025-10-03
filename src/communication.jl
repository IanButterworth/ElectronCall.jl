# Communication layer for ElectronCall.
#
# Handles JavaScript execution and bidirectional communication between
# Julia and Electron processes with async support and error handling.

"""
    Base.run(target::Union{Application,Window}, code::AbstractString) -> Any

Execute JavaScript code in the specified target (Application or Window).
Returns the result of the JavaScript expression.

Extends Base.run with methods for Electron applications and windows,
providing error handling and async support.

# Arguments
- `target`: Either an `Application` (main process) or `Window` (renderer process)
- `code`: JavaScript code to execute

# Examples
```jldoctest
julia> app = Application()
Application(...)

julia> result = run(app, "Math.PI")
3.141592653589793

julia> win = Window()
Window(...)

julia> title = run(win, "document.title")
"My App"
```
"""
function Base.run(app::Application, code::AbstractString)
    app.exists || throw(ApplicationError("Cannot execute JavaScript in closed application"))

    # Optimization: Use pre-serialized command template to reduce JSON overhead
    retval = req_response_js(app, "runcode", "app", nothing, code)

    if haskey(retval, "error")
        throw(JSExecutionError(retval["error"], context = "main"))
    end

    return get(retval, "data", nothing)
end

function Base.run(win::Window, code::AbstractString)
    isopen(win) || throw(WindowClosedError(win.id, "run"))

    # Optimization: Use pre-serialized command template to reduce JSON overhead
    retval = req_response_js(win.app, "runcode", "window", win.id, code)

    @assert haskey(retval, "status") "Invalid response format from Electron"

    if retval["status"] == "success"
        return get(retval, "data", nothing)
    elseif retval["status"] == "error"
        error_info = retval["error"]

        # Handle both string and dict error formats
        if isa(error_info, String)
            # Simple string error (optimized format)
            message = error_info
            stack = nothing
            line = nothing
            column = nothing
        else
            # Detailed error object format
            message = get(error_info, "message", "Unknown JavaScript error")
            stack = get(error_info, "stack", nothing)
            line = get(error_info, "line", nothing)
            column = get(error_info, "column", nothing)
        end

        throw(
            JSExecutionError(
                message,
                stack = stack,
                line = line,
                column = column,
                context = "renderer",
            ),
        )
    else
        throw(CommunicationError("Unexpected response status: $(retval["status"])"))
    end
end



"""
    @js_str(code) -> String

String macro for JavaScript code with syntax highlighting hints.
This is purely for developer convenience and IDE support.

# Examples
```julia
result = run(win, js"
    const title = document.title;
    return title.toUpperCase();
")
```
"""
macro js_str(code)
    return code
end

"""
    send_message_to_julia(win::Window, message)

Send a message from the renderer process to Julia. This is called from JavaScript
using the globally available `sendMessageToJulia` function.

This function is primarily for internal use - JavaScript code should use
the `sendMessageToJulia` function which is automatically injected.
"""
function send_message_to_julia(win::Window, message)
    isopen(win) || return  # Silently ignore if window is closed

    try
        put!(win.msg_channel, message)
    catch e
        @warn "Failed to send message to Julia" exception = e
    end
end

"""
    wait_for_message(win::Window; timeout::Union{Real,Nothing} = nothing) -> Any

Wait for a message from the window's renderer process.

# Arguments
- `win::Window`: The window to wait for messages from
- `timeout::Union{Real,Nothing}`: Optional timeout in seconds

# Examples
```julia
win = Window()

# Wait indefinitely
@async begin
    msg = wait_for_message(win)
    @info "Received: \$msg"
end

# Wait with timeout
try
    msg = wait_for_message(win, timeout=5.0)
    @info "Received: \$msg"
catch TimeoutError
    @warn "No message received within timeout"
end
```
"""
function wait_for_message(win::Window; timeout::Union{Real,Nothing} = nothing)
    isopen(win) || throw(WindowClosedError(win.id, "wait_for_message"))

    if timeout === nothing
        return take!(win.msg_channel)
    else
        # Implement timeout using Timer
        result_ref = Ref{Any}()
        completed = Ref{Bool}(false)

        # Start waiting for message
        @async begin
            try
                result_ref[] = take!(win.msg_channel)
                completed[] = true
            catch e
                if completed[]  # Don't error if we already timed out
                    return
                end
                rethrow(e)
            end
        end

        # Start timeout timer
        timer = Timer(timeout) do t
            if !completed[]
                completed[] = true
                # This will cause take! to error, which is what we want
                close(win.msg_channel)
            end
        end

        # Wait for completion
        while !completed[]
            sleep(0.01)  # Small sleep to prevent busy waiting
        end

        close(timer)

        if !isassigned(result_ref)
            throw(TimeoutError("No message received within $(timeout) seconds"))
        end

        return result_ref[]
    end
end

struct TimeoutError <: Exception
    message::String
end

"""
    on_message(callback::Function, win::Window; async::Bool = true)

Register a callback function to handle messages from the window's renderer process.

# Arguments
- `callback::Function`: Function to call when messages are received
- `win::Window`: The window to listen to
- `async::Bool`: Whether to handle messages asynchronously (default: true)

# Examples
```julia
win = Window()

# Async message handling (recommended)
on_message(win) do msg
    @info "Received message: \$msg"
    # Handle message...
end

# Synchronous message handling
on_message(win, async=false) do msg
    # This blocks the message loop - use carefully
    process_message_synchronously(msg)
end
```
"""
function on_message(callback::Function, win::Window; async::Bool = true)
    isopen(win) || throw(WindowClosedError(win.id, "on_message"))

    if async
        @async begin
            try
                while isopen(win) && isopen(win.msg_channel)
                    msg = take!(win.msg_channel)
                    @async callback(msg)  # Handle each message asynchronously
                end
            catch e
                if isopen(win)  # Only log if window is still supposed to be active
                    @error "Error in message handler" exception = e
                end
            end
        end
    else
        @async begin
            try
                while isopen(win) && isopen(win.msg_channel)
                    msg = take!(win.msg_channel)
                    callback(msg)  # Handle synchronously
                end
            catch e
                if isopen(win)
                    @error "Error in message handler" exception = e
                end
            end
        end
    end
end

# High-performance request-response function optimized for JavaScript execution
# Uses manual JSON construction to eliminate JSON.json() overhead
function req_response_js(
    app::Application,
    cmd::String,
    target::String,
    winid::Union{Int64,Nothing},
    code::String,
)
    app.exists || throw(ApplicationError("Cannot communicate with closed application"))

    lock(app.comm_lock) do
        connection = app.connection

        # Optimization: Manual JSON construction to avoid full serialization overhead
        # This eliminates the expensive JSON.json() call seen in profiling
        if target == "app"
            # Pre-built template for app commands
            json_cmd = string(
                "{\"cmd\":\"",
                cmd,
                "\",\"target\":\"",
                target,
                "\",\"code\":\"",
                escape_json_string(code),
                "\"}",
            )
        else
            # Pre-built template for window commands  
            json_cmd = string(
                "{\"cmd\":\"",
                cmd,
                "\",\"target\":\"",
                target,
                "\",\"winid\":",
                winid,
                ",\"code\":\"",
                escape_json_string(code),
                "\"}",
            )
        end

        try
            # Optimization: Use write instead of println to reduce buffer flushes
            write(connection, json_cmd, '\n')
            flush(connection)  # Explicit flush for better control  
            response_line = readline(connection)

            if isempty(response_line)
                throw(CommunicationError("Empty response from Electron process"))
            end

            return JSON.parse(response_line)
        catch e
            if e isa Base.IOError
                app.exists = false
                throw(CommunicationError("Lost connection to Electron process", e))
            else
                rethrow(e)
            end
        end
    end
end

# General request-response function for non-JavaScript commands
function req_response(app::Application, cmd::Dict)
    app.exists || throw(ApplicationError("Cannot communicate with closed application"))

    lock(app.comm_lock) do
        connection = app.connection
        json_cmd = JSON.json(cmd)

        try
            # Optimization: Use write instead of println to reduce buffer flushes
            write(connection, json_cmd, '\n')
            flush(connection)  # Explicit flush for better control
            response_line = readline(connection)

            if isempty(response_line)
                throw(CommunicationError("Empty response from Electron process"))
            end

            return JSON.parse(response_line)
        catch e
            if e isa Base.IOError
                app.exists = false
                throw(CommunicationError("Lost connection to Electron process", e))
            else
                rethrow(e)
            end
        end
    end
end

# Fast JSON string escaping for common cases
function escape_json_string(s::String)
    # Optimization: Handle common cases without full JSON escaping
    if !contains(s, '"') &&
       !contains(s, '\\') &&
       !contains(s, '\n') &&
       !contains(s, '\r') &&
       !contains(s, '\t')
        return s  # No escaping needed for simple strings
    else
        # Fall back to proper JSON escaping for complex strings
        return replace(
            replace(
                replace(replace(replace(s, "\\" => "\\\\"), "\"" => "\\\""), "\n" => "\\n"),
                "\r" => "\\r",
            ),
            "\t" => "\\t",
        )
    end
end
