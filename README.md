# ElectronCall.jl

[![Project Status: Active](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)

A modern, security-first Julia package for creating desktop applications with Electron. Built from the ground up with secure defaults, comprehensive error handling, and full compatibility with existing Electron.jl patterns.

## Key Features

- **Security-First**: Context isolation and sandboxing enabled by default
- **Fully Compatible**: Drop-in replacement for most Electron.jl code
- **Comprehensive Testing**: 47/47 tests passing with full functionality coverage
- **Modern Error Handling**: Structured error types with stack traces
- **Cross-Platform**: Windows, macOS, and Linux support

## ElectronCall.jl vs Electron.jl

| Feature | Electron.jl | ElectronCall.jl | Migration Notes |
|---------|-------------|------------------|-----------------|
| **Security** | | | |
| Context Isolation | ❌ Disabled by default | ✅ Enabled by default | Automatic - no code changes needed |
| Sandbox | ❌ Disabled (`--no-sandbox`) | ✅ Enabled by default | Use `development_config()` to disable for debugging |
| Node Integration | ✅ Enabled in renderer | ❌ Disabled by default | Use IPC or preload scripts for Node.js access |
| **API Compatibility** | | | |
| `Application()` | ✅ Basic constructor | ✅ Compatible + security options | Drop-in replacement |
| `Window()` | ✅ Basic constructor | ✅ Compatible + security features | Drop-in replacement |
| `run(win, js)` | ✅ JavaScript execution | ✅ Enhanced error handling | Drop-in replacement with better errors |
| **Error Handling** | | | |
| JavaScript Errors | ⚠️ Basic error propagation | ✅ Structured `JSExecutionError` | Better debugging with stack traces |
| Window State | ⚠️ Limited validation | ✅ `WindowClosedError` detection | Automatic validation |
| Application State | ⚠️ Manual tracking | ✅ Automatic lifecycle management | Built-in cleanup and validation |
| **Development Experience** | | | |
| Testing Support | ⚠️ Limited CI compatibility | ✅ Full CI/CD support | Comprehensive test suite |
| Documentation | ⚠️ Basic examples | ✅ Comprehensive docs + examples | Better API documentation |
| Debugging | ⚠️ Basic error messages | ✅ Detailed error context | Enhanced debugging experience |
| **Configuration** | | | |
| Security Settings | ❌ Hardcoded insecure defaults | ✅ Flexible `SecurityConfig` | Use `secure_defaults()`, `development_config()` |
| Development Mode | ❌ Not available | ✅ `development_mode = true` | Easier debugging and development |
| Custom Electron Args | ✅ Basic support | ✅ Enhanced support | More flexible configuration |

### Migration Examples

```julia
# Electron.jl → ElectronCall.jl

# Basic application (works unchanged)
app = Application()                    # Same in both packages
win = Window(app, "https://google.com") # Same in both packages

# JavaScript execution (enhanced)
run(win, "document.title")             # Same API, better error handling

# File loading (simplified)
# Electron.jl
win = Window(app, URI("file://$(pwd())/index.html"))
# ElectronCall.jl
win = Window(app, "file://$(pwd())/index.html")  # URI wrapper optional

# Security configuration (new feature)
# For development/debugging
app = Application(development_mode = true)
# Custom security
app = Application(security = SecurityConfig(sandbox = false))
```

## Installation

```julia
using Pkg
Pkg.add("ElectronCall")  # When registered
# Or for development:
Pkg.add(url="https://github.com/IanButterworth/ElectronCall.jl")
```

## Quick Start

```julia
using ElectronCall

# Create a secure application
app = Application()

# Create a window
win = Window(app, "https://example.com")

# Execute JavaScript securely
title = run(win, "document.title")
println("Page title: $title")

# Clean up
close(app)
```

## Migration from Electron.jl

ElectronCall.jl provides compatibility with most Electron.jl patterns:

```julia
# Electron.jl (original)
app = Application()
win = Window(app, URI("file://index.html"))
result = run(win, "document.title")

# ElectronCall.jl (compatible)
app = Application()
win = Window(app, "file://index.html")  # URI optional
result = run(win, "document.title")        # enhanced error handling
# result = run(win, "document.title")      # also works
```

## Security Configurations

```julia
# Secure defaults (recommended)
app = Application()

# Development mode
app = Application(development_mode = true)

# Custom security
app = Application(
    security = SecurityConfig(
        context_isolation = true,
        sandbox = true,
        node_integration = false
    )
)
```

## API Reference

### Core Functions

- `Application()` - Create a new Electron application
- `Window()` - Create a new window
- `run(target, js)` - Execute JavaScript code (extends Base.run)
- `load()` - Load content into a window
- `msgchannel()` - Get message channel for communication
- `close()` - Clean up applications and windows

### Security

- `SecurityConfig` - Configure security settings
- `secure_defaults()` - Get secure default configuration
- `development_config()` - Get development-friendly configuration

## Testing

```julia
using Pkg
Pkg.test("ElectronCall")
```

## License

MIT License - see LICENSE.md for details.

## Related Packages

- [Electron.jl](https://github.com/davidanthoff/Electron.jl)
- [Blink.jl](https://github.com/JunoLab/Blink.jl)