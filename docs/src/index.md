# ElectronCall.jl Documentation

Welcome to the documentation for ElectronCall.jl, a modern, security-first Julia package for creating desktop applications with Electron.

## Quick Start

```julia
using ElectronCall

# Create a secure application
app = Application()

# Create a window  
win = Window(app, "https://example.com")

# Execute JavaScript securely
result = run(win, "document.title")

# Clean up
close(app)
```

## Key Features

- **Security First**: Context isolation, sandboxing, and secure defaults
- **Modern Architecture**: Async-first with structured error handling  
- **Developer Friendly**: Rich debugging and comprehensive testing
- **Migration Ready**: Compatible with Electron.jl patterns

## Navigation

- [Getting Started](getting-started.md) - Installation and basic usage
- [Security](security.md) - Security configurations and best practices
- [API Reference](api.md) - Complete API documentation
- [Migration Guide](migration.md) - Moving from Electron.jl
- [Examples](examples.md) - Practical examples and tutorials