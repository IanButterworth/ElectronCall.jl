"""
Basic ElectronCall.jl Example with Async Messaging

This example demonstrates the comprehensive usage of ElectronCall.jl including:
- Basic application and window creation with secure de                                                        case 'greeting_response':
                            addMessage('👋 Julia says: ' + data.message);
                            break;                          addMessage('👋 Julia says: ' + data.message);                           addMessage('👋 Julia says: ' + data.message);                     case 'greeting_response':
                            addMessage('👋 Julia says: ' + data.message);                     case 'greeting_response':
                            addMessage('👋 Julia says: ' + data.message);witch(data.type) {
                        case 'system_info_response':
                            addMessage('💻 System Info: OS=' + data.os + ', Julia=' + data.julia_version + ', CPU=' + data.cpu_cores + ' cores');
                            break;
                        case 'stream_data':
                            addMessage('📊 ' + data.description + ': ' + data.value, 'stream-messages');
                            break;
                        case 'greeting_response':
                            addMessage('👋 Julia says: ' + data.message);
                            break;
                        default:
                            addMessage('📨 Julia: ' + message);
                    }ch(data.type) {
                        case 'system_info_response':
                            addMessage('💻 System Info: OS=' + data.os + ', Julia=' + data.julia_version + ', CPU=' + data.cpu_cores + ' cores');
                            break;
                        case 'stream_data':
                            addMessage('📊 ' + data.description + ': ' + data.value, 'stream-messages');
                            break;
                        case 'greeting_response':
                            addMessage('👋 Julia says: ' + data.message);
                            break;
                        default:
                            addMessage('📨 Julia: ' + message);
                    }rectional async messaging between Julia and JavaScript
- Message callbacks and response handling
- Real-time data streaming
- Error handling and cleanup
"""

using ElectronCall
using JSON
using Dates

function main()
    println("🚀 Starting ElectronCall.jl basic example...")

    # Create a secure application
    app = Application(name = "BasicExample")
    println("✅ Created application: $(app.name)")

    try
        # Create a window with some content
        win = Window(
            app,
            """
    <!DOCTYPE html>
    <html>
    <head>
        <title>ElectronCall.jl Basic Example</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                margin: 40px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                text-align: center;
            }
            .container {
                max-width: 600px;
                margin: 0 auto;
                background: rgba(255, 255, 255, 0.1);
                padding: 40px;
                border-radius: 20px;
                backdrop-filter: blur(10px);
            }
            button {
                background: #4CAF50;
                color: white;
                border: none;
                padding: 15px 30px;
                border-radius: 10px;
                cursor: pointer;
                font-size: 16px;
                margin: 10px;
            }
            button:hover { background: #45a049; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🎉 Hello ElectronCall.jl!</h1>
            <p>This is a basic example of a secure Electron application built with Julia.</p>
            <h2>💬 Async Messaging Demo</h2>
            <button onclick="sendHello()">Send Hello to Julia</button>
            <button onclick="requestSystemInfo()">Request System Info</button>
            <button onclick="startDataStream()">Start Data Stream</button>
            <button onclick="stopDataStream()">Stop Data Stream</button>
            <button onclick="getCurrentTime()">Get Current Time</button>

            <div id="output" style="margin-top: 20px; padding: 20px; background: rgba(0,0,0,0.2); border-radius: 10px;">
                <h3>📋 Output:</h3>
                <div id="messages"></div>
            </div>
            <div id="stream-data" style="margin-top: 20px; padding: 20px; background: rgba(0,0,0,0.3); border-radius: 10px;">
                <h3>📊 Live Data Stream:</h3>
                <div id="stream-messages"></div>
            </div>
        </div>

        <script>
            let streamActive = false;
            let messageCounter = 0;

            function addMessage(message, target = 'messages') {
                const div = document.getElementById(target);
                const timestamp = new Date().toLocaleTimeString();
                div.innerHTML += '<div style="margin: 5px 0; padding: 5px; background: rgba(255,255,255,0.1); border-radius: 5px;">' +
                    '<small>[' + timestamp + ']</small> ' + message +
                    '</div>';
                div.scrollTop = div.scrollHeight;
            }

            function sendHello() {
                const message = {
                    type: 'greeting',
                    data: 'Hello from the renderer process!',
                    timestamp: Date.now(),
                    counter: ++messageCounter
                };

                if (window.electronAPI) {
                    window.electronAPI.sendMessageToJulia(JSON.stringify(message));
                    addMessage('📤 Greeting sent to Julia (secure mode)');
                } else if (window.sendMessageToJulia) {
                    window.sendMessageToJulia(JSON.stringify(message));
                    addMessage('📤 Greeting sent to Julia (legacy mode)');
                } else {
                    addMessage('❌ No messaging API available');
                }
            }

            function requestSystemInfo() {
                const message = {
                    type: 'system_info_request',
                    timestamp: Date.now()
                };

                if (window.electronAPI) {
                    window.electronAPI.sendMessageToJulia(JSON.stringify(message));
                    addMessage('📡 System info requested...');
                } else if (window.sendMessageToJulia) {
                    window.sendMessageToJulia(JSON.stringify(message));
                    addMessage('📡 System info requested (legacy mode)...');
                } else {
                    addMessage('❌ No messaging API available');
                }
            }

            function startDataStream() {
                if (streamActive) {
                    addMessage('⚠️ Data stream already active');
                    return;
                }

                const message = {
                    type: 'start_stream',
                    timestamp: Date.now()
                };

                if (window.electronAPI) {
                    window.electronAPI.sendMessageToJulia(JSON.stringify(message));
                    streamActive = true;
                    addMessage('🚀 Data stream started');
                    document.getElementById('stream-messages').innerHTML = '';
                } else if (window.sendMessageToJulia) {
                    window.sendMessageToJulia(JSON.stringify(message));
                    streamActive = true;
                    addMessage('🚀 Data stream started (legacy mode)');
                    document.getElementById('stream-messages').innerHTML = '';
                } else {
                    addMessage('❌ No messaging API available');
                }
            }

            function stopDataStream() {
                if (!streamActive) {
                    addMessage('⚠️ No active data stream');
                    return;
                }

                const message = {
                    type: 'stop_stream',
                    timestamp: Date.now()
                };

                if (window.electronAPI) {
                    window.electronAPI.sendMessageToJulia(JSON.stringify(message));
                    streamActive = false;
                    addMessage('🛑 Data stream stopped');
                } else if (window.sendMessageToJulia) {
                    window.sendMessageToJulia(JSON.stringify(message));
                    streamActive = false;
                    addMessage('🛑 Data stream stopped (legacy mode)');
                } else {
                    addMessage('❌ No messaging API available');
                }
            }

            function getCurrentTime() {
                const now = new Date().toLocaleString();
                addMessage('🕐 Current time: ' + now);
            }

            // Function to handle messages from Julia
            window.handleJuliaMessage = function(message) {
                try {
                    const data = JSON.parse(message);

                    switch(data.type) {
                        case 'system_info_response':
                            addMessage('💻 System Info: OS=' + data.os + ', Julia=' + data.julia_version + ', CPU=' + data.cpu_cores + ' cores');
                            break;
                        case 'stream_data':
                            addMessage('📊 ' + data.description + ': ' + data.value, 'stream-messages');
                            break;
                        case 'greeting_response':
                            addMessage(`� Julia says: \${data.message}`);
                            break;
                        default:
                            addMessage('📨 Julia: ' + message);
                    }
                } catch (e) {
                    addMessage('📨 Julia: ' + message);
                }
            };

            // Display security status
            document.addEventListener('DOMContentLoaded', function() {
                const isSecure = window.electronAPI !== undefined;
                const securityStatus = isSecure ? '🔒 Secure Mode (Context Isolation Enabled)' : '⚠️ Legacy Mode';
                console.log('ElectronCall.jl Security Status:', securityStatus);
                addMessage('Security Status: ' + securityStatus);
            });
        </script>
    </body>
    </html>
""",
            width = 800,
            height = 600,
            title = "ElectronCall.jl Basic Example",
        )

        println("✅ Created window")

        # Set up async message handling
        ch = msgchannel(win)
        println("📡 Setting up async message handlers...")

        # Data streaming control
        stream_active = Ref(false)
        stream_task = Ref{Union{Task,Nothing}}(nothing)

        # Main message handler
        message_handler = @async begin
            try
                while isopen(ch)
                    msg = take!(ch)
                    println("📨 Received message from renderer: $msg")

                    # Handle different message types
                    handle_message(win, msg, stream_active, stream_task)
                end
            catch e
                if isa(e, InvalidStateException) && e.state == :closed
                    println("📪 Message channel closed")
                else
                    println("❌ Error in message handler: $e")
                end
            end
        end

        # Helper function to handle different message types
        function handle_message(win, msg_str, stream_active, stream_task)
            try
                # Try to parse as JSON for structured messages
                if startswith(strip(msg_str), "{")
                    msg_data = JSON.parse(msg_str)

                    message_type = get(msg_data, "type", "unknown")

                    if message_type == "greeting"
                        # Respond to greeting
                        response = Dict(
                            "type" => "greeting_response",
                            "message" => "Hello from Julia! 👋 Message $(msg_data["counter"]) received at $(now())",
                            "timestamp" => time(),
                        )
                        send_to_renderer(win, response)

                    elseif message_type == "system_info_request"
                        # Send system information
                        response = Dict(
                            "type" => "system_info_response",
                            "os" => string(Sys.KERNEL),
                            "julia_version" => string(VERSION),
                            "cpu_cores" => Sys.CPU_THREADS,
                            "timestamp" => time(),
                        )
                        send_to_renderer(win, response)

                    elseif message_type == "start_stream"
                        start_data_stream(win, stream_active, stream_task)

                    elseif message_type == "stop_stream"
                        stop_data_stream(stream_active, stream_task)

                    else
                        println("🤷 Unknown message type: $message_type")
                    end
                else
                    # Handle plain text messages
                    println("💬 Plain text message: $msg_str")
                end

            catch e
                println("❌ Error parsing message: $e")
                println("📄 Raw message: $msg_str")
            end
        end

        # Function to send structured data to renderer
        function send_to_renderer(win, data)
            try
                json_str = JSON.json(data)
                # Escape quotes for JavaScript string
                escaped_json = replace(json_str, "'" => "\\'")
                run(
                    win,
                    "window.handleJuliaMessage && window.handleJuliaMessage('$escaped_json')",
                )
            catch e
                println("❌ Error sending to renderer: $e")
            end
        end

        # Data streaming functions
        function start_data_stream(win, stream_active, stream_task)
            if stream_active[]
                println("⚠️ Data stream already active")
                return
            end

            stream_active[] = true
            println("🚀 Starting data stream...")

            stream_task[] = @async begin
                counter = 0
                while stream_active[]
                    try
                        # Generate some sample data
                        counter += 1
                        cpu_time = time()
                        memory_usage = Base.gc_bytes() / (1024^2) # MB
                        random_value = rand() * 100

                        # Send different types of data
                        if counter % 3 == 1
                            data = Dict(
                                "type" => "stream_data",
                                "description" => "CPU Time",
                                "value" => round(cpu_time, digits = 2),
                                "counter" => counter,
                            )
                        elseif counter % 3 == 2
                            data = Dict(
                                "type" => "stream_data",
                                "description" => "Memory Usage (MB)",
                                "value" => round(memory_usage, digits = 2),
                                "counter" => counter,
                            )
                        else
                            data = Dict(
                                "type" => "stream_data",
                                "description" => "Random Value",
                                "value" => round(random_value, digits = 2),
                                "counter" => counter,
                            )
                        end

                        send_to_renderer(win, data)
                        sleep(1.0) # Send data every second

                    catch e
                        if stream_active[]
                            println("❌ Error in data stream: $e")
                        end
                        break
                    end
                end
                println("📊 Data stream ended")
            end
        end

        function stop_data_stream(stream_active, stream_task)
            if !stream_active[]
                println("⚠️ No active data stream to stop")
                return
            end

            stream_active[] = false
            if stream_task[] !== nothing
                # Task will naturally end when stream_active becomes false
                stream_task[] = nothing
            end
            println("🛑 Data stream stopped")
        end

        # Demonstrate basic JavaScript execution
        println("🧪 Testing JavaScript execution...")

        # Get page title
        title = run(win, "document.title")
        println("📄 Page title: $title")

        # Do some math in the renderer
        result = run(win, "Math.PI * 2")
        println("🔢 Math result: $result")

        # Show user agent (first few characters to avoid clutter)
        user_agent = run(win, "navigator.userAgent")
        println("🌐 User agent: $(first(user_agent, 50))...")

        println("\n🎯 Application is running with async messaging!")
        println("� Available interactions:")
        println("  • Send Hello - Basic bidirectional messaging")
        println("  • Request System Info - Structured data exchange")
        println("  • Start/Stop Data Stream - Real-time data streaming")
        println("  • Get Current Time - Client-side operation")
        println("\n🛑 Press Ctrl+C to stop the application")

        # Keep the application running
        try
            while isopen(win)
                sleep(1)
            end
        catch InterruptException
            println("\n🛑 Interrupted by user")
            # Clean up streaming
            if stream_active[]
                stream_active[] = false
            end
        end

    catch e
        println("❌ Error: $e")
        if isa(e, JSExecutionError)
            println("📍 JavaScript error details:")
            println("   Message: $(e.message)")
            println("   Context: $(e.context)")
            if e.stack !== nothing
                println("   Stack: $(e.stack)")
            end
        end
    finally
        # Clean up
        println("🧹 Cleaning up...")
        if app.exists
            close(app)
        end
        println("✅ Done!")
    end
end

# Run the example
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
