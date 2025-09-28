# Convenient macros for ElectronCall.
#
# Provides high-level, declarative APIs for creating Electron applications
# with a more modern Julia syntax.

"""
    @async_app(expr)

Create and manage an Electron application with async syntax sugar.

# Examples
```jldoctest
julia> @async_app begin
           win = Window("https://example.com")
           result = run(win, "document.title")
           @info "Page title: \$result"
       end
Application(...)
```
"""
macro async_app(args...)
    if length(args) == 1
        # @async_app begin ... end
        expr = args[1]
        app_name = "ElectronCall-App"
        kwargs = []
    elseif length(args) >= 2 && args[1] isa String
        # @async_app "AppName" kwargs... begin ... end
        app_name = args[1]
        expr = args[end]
        kwargs = args[2:end-1]
    else
        error("Invalid @async_app syntax")
    end

    # Build kwargs for Application constructor
    app_kwargs = []
    for kw in kwargs
        if kw isa Expr && kw.head == :(=)
            push!(app_kwargs, kw)
        else
            error("Invalid keyword argument: $kw")
        end
    end

    return quote
        local app = Application(name = $app_name, $(app_kwargs...))
        try
            # Make app available in the block scope
            $(esc(expr))
        finally
            # Ensure cleanup
            if app.exists
                close(app)
            end
        end
    end
end

"""
    @electron_function(func_def)

Register a Julia function to be callable from JavaScript via the secure bridge.

# Examples
```julia
@electron_function function add_numbers(a::Float64, b::Float64)
    return a + b
end

@electron_function function get_system_info()
    return Dict(
        "os" => string(Sys.KERNEL),
        "julia_version" => string(VERSION),
        "cpu_cores" => Sys.CPU_THREADS
    )
end

# In JavaScript:
# const result = await window.electronAPI.invoke('add_numbers', [3.14, 2.86]);
# const info = await window.electronAPI.invoke('get_system_info', []);
```
"""
macro electron_function(func_def)
    # Extract function name and signature
    if func_def.head != :function
        error("@electron_function can only be applied to function definitions")
    end

    func_signature = func_def.args[1]
    func_body = func_def.args[2]

    # Extract function name
    func_name = if func_signature isa Symbol
        func_signature
    elseif func_signature isa Expr && func_signature.head == :call
        func_signature.args[1]
    else
        error("Cannot extract function name from signature: $func_signature")
    end

    func_name_str = string(func_name)

    return quote
        # Define the original function
        $(esc(func_def))

        # Register it in the global RPC registry
        ElectronCall._register_rpc_function($func_name_str, $(esc(func_name)))
    end
end

# Internal RPC function registry
const _rpc_functions = Dict{String,Function}()

function _register_rpc_function(name::String, func::Function)
    _rpc_functions[name] = func
    @info "Registered Electron RPC function: $name"
end

function _handle_rpc_call(name::String, args::Vector)
    if !haskey(_rpc_functions, name)
        throw(ArgumentError("Unknown RPC function: $name"))
    end

    func = _rpc_functions[name]
    try
        return func(args...)
    catch e
        @error "Error in RPC function $name" exception = e
        rethrow(e)
    end
end

"""
    @js(win, expr)

Execute JavaScript with interpolated Julia values.

# Examples
```jldoctest
julia> win = Window()
Window(...)

julia> name = "World"
"World"

julia> result = @js win "Hello, \$name!"
"Hello, World!"
```
"""
macro js(win, expr)
    # Simple string interpolation for JavaScript
    if expr isa String
        # Handle string interpolation
        interpolated = quote
            local interpolated_js = $expr
            # TODO: Add proper Julia -> JS value interpolation
            run($(esc(win)), interpolated_js)
        end
        return interpolated
    else
        return quote
            run($(esc(win)), $(esc(expr)))
        end
    end
end

"""
    @window(args...) -> Window

Convenient window creation with builder-style syntax.

# Examples
```julia
# Simple window
win = @window "https://example.com"

# Window with options
win = @window width=800 height=600 title="My App" begin
    "<h1>Hello World</h1>"
end

# Window with application
app = Application()
win = @window app width=1200 height=800 "file:///path/to/index.html"
```
"""
macro window(args...)
    if length(args) == 0
        return :(Window())
    elseif length(args) == 1
        arg = args[1]
        if arg isa String
            # @window "url"
            return :(Window($arg))
        elseif arg isa Expr && arg.head == :block
            # @window begin ... end (HTML content)
            html_content = string(arg)  # Convert block to string
            return :(Window($html_content))
        else
            return :(Window($(esc(arg))))
        end
    else
        # Multiple arguments - need to parse them
        app_arg = nothing
        content_arg = nothing
        kwargs = []

        for arg in args
            if arg isa Expr && arg.head == :(=)
                # Keyword argument
                push!(kwargs, arg)
            elseif app_arg === nothing && content_arg === nothing
                # Could be app or content
                app_arg = arg
            elseif content_arg === nothing
                # Second positional arg is content
                content_arg = arg
            else
                error("Too many positional arguments to @window")
            end
        end

        if content_arg !== nothing
            return :(Window($(esc(app_arg)), $(esc(content_arg)); $(kwargs...)))
        else
            return :(Window($(esc(app_arg)); $(kwargs...)))
        end
    end
end
