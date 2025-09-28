# ElectronCall.jl vs Electron.jl Comparison

This document provides a detailed comparison between ElectronCall.jl (v1.0.0) and the original Electron.jl (v6.0.0), including migration guidance and feature differences.

## Performance Comparison

**Latest Benchmark Results** (September 2025):

| Metric | Electron.jl | ElectronCall.jl | Winner |
|--------|-------------|-----------------|---------|
| **Application Startup** | 161.03 ms | 164.83 ms | ⚠️ Electron.jl (+2.4%) |
| **Window Creation** | 113.23 ms | 112.76 ms | 🚀 **ElectronCall.jl** (+0.4%) |
| **JS Execution (Single)** | 1.03 ms | 990.138 μs | 🚀 **ElectronCall.jl** (+3.9%) |
| **JS Throughput** | 3620 ops/sec | 3445 ops/sec | ⚠️ Electron.jl (+4.8%) |
| **Cleanup Time** | 20.05 ms | 19.47 ms | 🚀 **ElectronCall.jl** (+2.9%) |
| **Thread Safety** | ❌ Not supported | ✅ 3.09 ms concurrent exec | 🔒 **ElectronCall.jl exclusive** |

## Feature Comparison

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
| **Async Messaging** | | | |
| Basic Messaging | ✅ `sendMessageToJulia()` | ✅ Compatible API | Drop-in replacement |
| Timeout Support | ❌ Blocks indefinitely | ✅ `wait_for_message(timeout=5.0)` | Prevent hanging on missing messages |
| Callback Handlers | ❌ Manual channel handling | ✅ `on_message()` with async support | Cleaner event-driven code |
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

## Migration Examples

### Basic Usage (Compatible)

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
```

### Security Configuration (New Feature)

```julia
# For development/debugging
app = Application(development_mode = true)

# Custom security
app = Application(security = SecurityConfig(sandbox = false))
```

## Async Messaging Comparison

ElectronCall.jl provides enhanced async messaging capabilities compared to the original Electron.jl:

### Basic Messaging (Compatible)

Both packages support the same basic messaging pattern:

```julia
# Send message from JavaScript to Julia
run(win, "sendMessageToJulia('Hello from renderer!')")

# Receive message in Julia
ch = msgchannel(win)
msg = take!(ch)  # "Hello from renderer!"
```

### Enhanced Messaging Features (ElectronCall.jl Only)

| Feature | Electron.jl | ElectronCall.jl | Description |
|---------|-------------|------------------|-------------|
| **Timeout Support** | ❌ | ✅ | Wait for messages with timeout |
| **Async Callbacks** | ❌ | ✅ | Register callback functions for messages |
| **Error Handling** | ⚠️ Basic | ✅ Comprehensive | Structured error handling and recovery |
| **Non-blocking Handlers** | ❌ | ✅ | Handle messages without blocking the message loop |
| **Window State Validation** | ❌ | ✅ | Automatic validation of window state |

### Advanced Messaging Examples

```julia
using ElectronCall

app = Application()
win = Window(app, "<html><button onclick='sendMessageToJulia(\"clicked!\")'>Click me</button></html>")

# 1. Simple message waiting (compatible with Electron.jl)
ch = msgchannel(win)
msg = take!(ch)

# 2. Wait with timeout (ElectronCall.jl only)
try
    msg = wait_for_message(win, timeout=5.0)
    println("Received: $msg")
catch TimeoutError
    println("No message received within 5 seconds")
end

# 3. Async callback handling (ElectronCall.jl only)
on_message(win) do msg
    println("Async handler received: $msg")
    # This runs asynchronously and doesn't block other messages
end

# 4. Synchronous callback handling (ElectronCall.jl only)
on_message(win, async=false) do msg
    println("Sync handler received: $msg")
    # This processes messages one at a time
end
```

### Security Considerations

ElectronCall.jl's messaging system is designed with security in mind:

- **Context Isolation**: Messages are properly isolated between contexts
- **Sandbox Compatible**: Works with enabled sandbox (Electron.jl requires `--no-sandbox`)
- **Error Boundaries**: Failed message handlers don't crash the application
- **Resource Management**: Automatic cleanup when windows are closed

## Why ElectronCall.jl?

### Security First
- **Secure by Default**: Context isolation and sandboxing enabled out of the box
- **Modern Electron Standards**: Follows current Electron security best practices
- **Production Ready**: Safe for production deployment without security compromises

### Better Developer Experience
- **Enhanced Error Handling**: Detailed error messages with stack traces
- **Async Support**: Non-blocking message handling with timeout support
- **CI/CD Ready**: Full test suite with cross-platform CI support

### Drop-in Compatibility
- **Minimal Migration**: Most Electron.jl code works unchanged
- **Familiar API**: Same function names and patterns
- **Gradual Adoption**: Can migrate features incrementally

## Breaking Changes

### Security Changes (Intentional)
- Node.js integration disabled in renderer by default
- Sandbox enabled by default (use `development_config()` to disable)
- Some unsafe operations may be blocked

### API Enhancements
- Enhanced error types (more specific than basic exceptions)
- Optional timeout parameters for message operations
- Additional security configuration options

These changes improve security and reliability while maintaining API compatibility for most use cases.