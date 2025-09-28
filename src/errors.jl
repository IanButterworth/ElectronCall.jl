# Error types and exception handling for ElectronCall.
#
# Provides structured error types for better error handling and debugging
# compared to the original Electron.jl package.

# Base error type
abstract type ElectronCallError <: Exception end

"""
    JSExecutionError <: ElectronCallError

Thrown when JavaScript execution fails in either main or renderer process.
Provides detailed error information including stack traces.
"""
struct JSExecutionError <: ElectronCallError
    message::String
    stack::Union{String,Nothing}
    line::Union{Int,Nothing}
    column::Union{Int,Nothing}
    context::String  # "main" or "renderer"

    function JSExecutionError(
        message::String;
        stack::Union{String,Nothing} = nothing,
        line::Union{Int,Nothing} = nothing,
        column::Union{Int,Nothing} = nothing,
        context::String = "unknown",
    )
        new(message, stack, line, column, context)
    end
end

function Base.showerror(io::IO, e::JSExecutionError)
    print(io, "JSExecutionError in $(e.context) process: $(e.message)")
    if e.line !== nothing
        print(io, " (line $(e.line)")
        if e.column !== nothing
            print(io, ", column $(e.column)")
        end
        print(io, ")")
    end
    if e.stack !== nothing
        print(io, "\nStack trace:\n$(e.stack)")
    end
end

"""
    WindowClosedError <: ElectronCallError

Thrown when attempting to operate on a window that has been closed.
"""
struct WindowClosedError <: ElectronCallError
    window_id::Union{String,Int}
    operation::String

    WindowClosedError(window_id, operation) = new(window_id, operation)
end

function Base.showerror(io::IO, e::WindowClosedError)
    print(
        io,
        "WindowClosedError: Cannot perform '$(e.operation)' on window $(e.window_id) - window has been closed",
    )
end

"""
    SecurityError <: ElectronCallError

Thrown when a security violation occurs, such as attempting to disable
required security features or access unauthorized resources.
"""
struct SecurityError <: ElectronCallError
    message::String
    context::String

    SecurityError(message::String, context::String = "security") = new(message, context)
end

function Base.showerror(io::IO, e::SecurityError)
    print(io, "SecurityError [$(e.context)]: $(e.message)")
end

"""
    CommunicationError <: ElectronCallError

Thrown when communication between Julia and Electron processes fails.
"""
struct CommunicationError <: ElectronCallError
    message::String
    cause::Union{Exception,Nothing}

    CommunicationError(message::String, cause::Union{Exception,Nothing} = nothing) =
        new(message, cause)
end

function Base.showerror(io::IO, e::CommunicationError)
    print(io, "CommunicationError: $(e.message)")
    if e.cause !== nothing
        print(io, "\nCaused by: ")
        showerror(io, e.cause)
    end
end

"""
    ApplicationError <: ElectronCallError

Thrown when Electron application startup or management fails.
"""
struct ApplicationError <: ElectronCallError
    message::String
    exit_code::Union{Int,Nothing}

    ApplicationError(message::String, exit_code::Union{Int,Nothing} = nothing) =
        new(message, exit_code)
end

function Base.showerror(io::IO, e::ApplicationError)
    print(io, "ApplicationError: $(e.message)")
    if e.exit_code !== nothing
        print(io, " (exit code: $(e.exit_code))")
    end
end

# Legacy compatibility - matches original Electron.jl JSError
const JSError = JSExecutionError  # For backwards compatibility
