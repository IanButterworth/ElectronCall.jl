"""
Basic ElectronCall.jl Example

This example demonstrates the basic usage of ElectronCall.jl for creating
a simple desk        # Get page title
        title = run(win, "document.title")
        println("📄 Page title: $title")

        # Do some math in the renderer
        result = run(win, "Math.PI * 2")
        println("🔢 Math result: $result")

        # Get user agent
        user_agent = run(win, "navigator.userAgent")ation with secure defaults.
"""

using ElectronCall

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
            <button onclick="sendHello()">Send Hello to Julia</button>
            <button onclick="getCurrentTime()">Get Current Time</button>
            <div id="output" style="margin-top: 20px; padding: 20px; background: rgba(0,0,0,0.2); border-radius: 10px;"></div>
        </div>

        <script>
            function sendHello() {
                if (window.electronAPI) {
                    window.electronAPI.sendMessageToJulia("Hello from the renderer process!");
                    document.getElementById('output').innerHTML = '📤 Message sent to Julia!';
                } else if (window.sendMessageToJulia) {
                    window.sendMessageToJulia("Hello from the renderer process!");
                    document.getElementById('output').innerHTML = '📤 Message sent to Julia (legacy mode)!';
                }
            }

            function getCurrentTime() {
                const now = new Date().toLocaleString();
                document.getElementById('output').innerHTML = `🕐 Current time: \${now}`;
            }

            // Display security status
            document.addEventListener('DOMContentLoaded', function() {
                const isSecure = window.electronAPI !== undefined;
                const securityStatus = isSecure ? '🔒 Secure Mode (Context Isolation Enabled)' : '⚠️ Legacy Mode';
                console.log('ElectronCall.jl Security Status:', securityStatus);
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

        # Set up message handling
        ch = msgchannel(win)
        println("📡 Listening for messages from renderer...")

        # Handle messages in a separate task
        @async begin
            try
                while isopen(ch)
                    msg = take!(ch)
                    println("📨 Received message from renderer: $msg")

                    # You could respond back to the renderer here
                    # run(win, "console.log('Julia received: $msg')")
                end
            catch e
                if isa(e, InvalidStateException) && e.state == :closed
                    println("📪 Message channel closed")
                else
                    println("❌ Error in message handler: $e")
                end
            end
        end

        # Demonstrate JavaScript execution
        println("🧪 Testing JavaScript execution...")

        # Get page title
        title = run(win, "document.title")
        println("📄 Page title: $title")

        # Do some math in the renderer
        result = run(win, "Math.PI * 2")
        println("🔢 Math result: $result")

        # Show user agent
        user_agent = run(win, "navigator.userAgent")
        println("🌐 User agent: $user_agent")

        println("\n🎯 Application is running!")
        println("💡 Try clicking the button in the window to send a message to Julia")
        println("🛑 Press Ctrl+C to stop the application")

        # Keep the application running
        # In a real application, you might want to use a different approach
        try
            while win.exists
                sleep(1)
            end
        catch InterruptException
            println("\n🛑 Interrupted by user")
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
