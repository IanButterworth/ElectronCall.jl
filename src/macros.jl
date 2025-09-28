# Convenient macros for ElectronCall.
#
# Provides high-level, declarative APIs for creating Electron applications
# with a more modern Julia syntax.

"""
    @async_app(expr)
    @async_app("AppName", expr)
    @async_app("AppName", security=config, expr)

Create and manage an Electron application with async syntax sugar.

Supports all Application constructor keyword arguments including `security`.

# Examples
```jldoctest
julia> @async_app begin
           win = Window("https://example.com")
           result = run(win, "document.title")
           @info "Page title: \$result"
       end
Application(...)

julia> @async_app "MyApp" security=development_config() begin
           win = Window("https://example.com")
           # App automatically uses development_config() security
       end
42
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
            # Escape the entire keyword argument expression
            push!(app_kwargs, esc(kw))
        else
            error("Invalid keyword argument: $kw")
        end
    end

    return quote
        local app = Application(; name = $app_name, $(app_kwargs...))
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

Provides automatic conversion of Julia values to JavaScript equivalents:
- Numbers, strings, booleans: Direct conversion
- Arrays, tuples: Convert to JavaScript arrays
- Dictionaries: Convert to JavaScript objects
- Other types: JSON serialization

# Examples
```jldoctest
julia> win = Window()
Window(...)

julia> name = "World"
"World"

julia> result = @js win "Hello, \$name!"
"Hello, World!"

julia> data = [1, 2, 3]
3-element Vector{Int64}: [1, 2, 3]

julia> @js win "console.log(\$data)"  # Becomes: console.log([1,2,3])

julia> config = Dict("width" => 800, "height" => 600)
Dict{String, Int64} with 2 entries: ...

julia> @js win "window.resizeTo(\$(config["width"]), \$(config["height"]))"
```
"""
macro js(win, expr)
    if expr isa String
        # Parse the string at macro expansion time to handle interpolations
        result_expr = _process_js_interpolations(expr, __module__)
        return quote
            run($(esc(win)), $result_expr)
        end
    else
        return quote
            run($(esc(win)), $(esc(expr)))
        end
    end
end

"""
    _process_js_interpolations(str::String, mod::Module) -> Expr

Process a JavaScript string with Julia interpolations at macro expansion time.
Returns an expression that will generate the final JavaScript string.
"""
function _process_js_interpolations(str::String, mod::Module)
    parts = []
    i = 1

    while i <= length(str)
        if str[i] == '$'
            if i + 1 <= length(str) && str[i+1] == '('
                # Handle $(expr) form
                paren_count = 1
                expr_start = i + 2
                j = expr_start

                while j <= length(str) && paren_count > 0
                    if str[j] == '('
                        paren_count += 1
                    elseif str[j] == ')'
                        paren_count -= 1
                    end
                    j += 1
                end

                if paren_count == 0
                    # Extract the expression
                    expr_str = str[expr_start:j-2]
                    try
                        expr_parsed = Meta.parse(expr_str)
                        # Add conversion call for this expression
                        push!(parts, :(_julia_to_js($(esc(expr_parsed)))))
                        i = j
                        continue
                    catch e
                        # If parsing fails, treat as literal
                        push!(parts, str[i:j-1])
                        i = j
                        continue
                    end
                else
                    # Unmatched parentheses, treat as literal
                    push!(parts, string(str[i]))
                    i += 1
                end
            elseif i + 1 <= length(str) && (isletter(str[i+1]) || str[i+1] == '_')
                # Handle $var form
                var_start = i + 1
                j = var_start

                while j <= length(str) &&
                    (isletter(str[j]) || isdigit(str[j]) || str[j] == '_')
                    j += 1
                end

                var_name = str[var_start:j-1]
                if !isempty(var_name)
                    var_symbol = Symbol(var_name)
                    # Add conversion call for this variable
                    push!(parts, :(_julia_to_js($(esc(var_symbol)))))
                    i = j
                    continue
                end

                # Fallback: treat as literal
                push!(parts, string(str[i]))
                i += 1
            else
                # Just a $ by itself or $<non-identifier>
                push!(parts, string(str[i]))
                i += 1
            end
        else
            # Regular character, collect contiguous literal parts
            literal_start = i
            while i <= length(str) && str[i] != '$'
                i += 1
            end
            push!(parts, str[literal_start:i-1])
        end
    end

    # Combine parts into a single string expression
    if length(parts) == 1 && parts[1] isa String
        return parts[1]
    else
        # Create string concatenation expression
        concat_expr = Expr(:call, :string)
        for part in parts
            push!(concat_expr.args, part)
        end
        return concat_expr
    end
end

"""
    _julia_to_js(value) -> String

Convert a Julia value to its JavaScript string representation.
"""
function _julia_to_js(value)
    if value isa Nothing
        return "null"
    elseif value isa Bool
        return value ? "true" : "false"
    elseif value isa AbstractString
        return JSON3.write(value)  # Proper string escaping
    elseif value isa Number
        if isfinite(value)
            return string(value)
        elseif isnan(value)
            return "NaN"
        elseif isinf(value)
            return value > 0 ? "Infinity" : "-Infinity"
        else
            return "null"
        end
    elseif value isa AbstractArray || value isa Tuple
        # Convert to JavaScript array
        return JSON3.write(collect(value))
    elseif value isa AbstractDict
        # Convert to JavaScript object
        return JSON3.write(value)
    else
        # Fallback: try JSON serialization
        try
            return JSON3.write(value)
        catch
            # If JSON fails, convert to string and quote it
            return JSON3.write(string(value))
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
