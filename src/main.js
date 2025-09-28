const electron = require('electron')
const path = require('path')
const url = require('url')
const net = require('net')
const os = require('os')
const readline = require('readline')

const BrowserWindow = electron.BrowserWindow;
const app = electron.app;
const ipcMain = electron.ipcMain;

let sysnotify_connection = null;
let security_config = null;

// Helper function to safely write to sysnotify connection
function safe_sysnotify_write(data) {
    if (sysnotify_connection && !sysnotify_connection.destroyed) {
        try {
            const result = sysnotify_connection.write(JSON.stringify(data) + '\n');
            if (!result) {
                // Write failed, likely because the connection is closing
                return false;
            }
        } catch (error) {
            // Connection may already be closed during rapid cleanup - this is expected
            if (error.code !== 'EPIPE' && error.code !== 'ECONNRESET') {
                console.error('ElectronCall: Unexpected error writing to sysnotify connection:', error);
            }
        }
    }
    return true;
}

function createWindow(connection, opts) {
    // Apply security configuration
    if (security_config) {
        if ('webPreferences' in opts) {
            // Merge with existing webPreferences, prioritizing security config
            const webPrefs = opts.webPreferences;
            webPrefs.contextIsolation = security_config.context_isolation;
            webPrefs.sandbox = security_config.sandbox;
            webPrefs.nodeIntegration = security_config.node_integration;
            webPrefs.webSecurity = security_config.web_security;
            
            // Set preload script if specified
            if (security_config.preload_script) {
                webPrefs.preload = path.join(__dirname, security_config.preload_script);
            } else if (security_config.context_isolation) {
                // Use default preload script for secure communication
                webPrefs.preload = path.join(__dirname, 'preload.js');
            }
        } else {
            opts.webPreferences = {
                contextIsolation: security_config.context_isolation,
                sandbox: security_config.sandbox,
                nodeIntegration: security_config.node_integration,
                webSecurity: security_config.web_security,
                preload: security_config.context_isolation ? 
                    path.join(__dirname, 'preload.js') : undefined
            };
        }
    } else {
        // Fallback to secure defaults if no config provided
        if ('webPreferences' in opts) {
            opts.webPreferences.contextIsolation = opts.webPreferences.contextIsolation !== false;
            opts.webPreferences.sandbox = opts.webPreferences.sandbox !== false;
            opts.webPreferences.nodeIntegration = opts.webPreferences.nodeIntegration === true;
            opts.webPreferences.webSecurity = opts.webPreferences.webSecurity !== false;
        } else {
            opts.webPreferences = {
                contextIsolation: true,
                sandbox: true,
                nodeIntegration: false,
                webSecurity: true,
                preload: path.join(__dirname, 'preload.js')
            };
        }
    }

    // Create the browser window
    const win = new BrowserWindow(opts);
    
    // Load URL or default page
    win.loadURL(opts.url || "about:blank");
    
    // Remove menu bar (can be overridden by options)
    if (!opts.menu) {
        win.setMenu(null);
    }

    const win_id = win.id;

    // Set up secure communication based on security config
    if (!security_config || !security_config.context_isolation) {
        // Legacy mode - inject sendMessageToJulia directly (INSECURE)
        win.webContents.on("did-finish-load", function() {
            win.webContents.executeJavaScript(`
                const {ipcRenderer} = require('electron'); 
                function sendMessageToJulia(message) { 
                    ipcRenderer.send('msg-for-julia-process', message); 
                }; 
                global['sendMessageToJulia'] = sendMessageToJulia;
                undefined
            `);
        });
    } else {
        // Secure mode - communication via preload script
        // The preload script handles the secure bridge
    }

    // Handle window lifecycle
    win.webContents.once("did-finish-load", function() {
        connection.write(JSON.stringify({data: win_id}) + '\n');

        win.on('closed', function() {
            safe_sysnotify_write({
                cmd: "windowclosed", 
                winid: win_id
            });
        });
    });

    // Handle load errors
    win.webContents.on('did-fail-load', function(event, errorCode, errorDescription, validatedURL) {
        connection.write(JSON.stringify({
            error: `Failed to load ${validatedURL}: ${errorDescription} (${errorCode})`
        }) + '\n');
    });
}

function process_command(connection, cmd) {
    try {
        if (cmd.cmd == 'runcode' && cmd.target == 'app') {
            // Execute JavaScript in main process
            let retval;
            try {
                const result = eval(cmd.code);
                retval = {data: result === undefined ? null : result};
            } catch (error) {
                retval = {error: error.toString()};
            }
            connection.write(JSON.stringify(retval) + '\n');
            
        } else if (cmd.cmd == 'runcode' && cmd.target == 'window') {
            // Execute JavaScript in renderer process
            const win = BrowserWindow.fromId(cmd.winid);
            if (!win) {
                connection.write(JSON.stringify({
                    status: 'error',
                    error: {message: `Window ${cmd.winid} not found`}
                }) + '\n');
                return;
            }

            win.webContents.executeJavaScript(cmd.code, true)
                .then(function(result) {
                    connection.write(JSON.stringify({
                        status: 'success', 
                        data: result
                    }) + '\n');
                })
                .catch(function(error) {
                    // Enhanced error reporting
                    const errorInfo = {
                        message: error.message || error.toString(),
                        stack: error.stack || null,
                        name: error.name || 'Error'
                    };
                    
                    connection.write(JSON.stringify({
                        status: 'error',
                        error: errorInfo
                    }) + '\n');
                });
                
        } else if (cmd.cmd == 'loadurl') {
            const win = BrowserWindow.fromId(cmd.winid);
            if (!win) {
                connection.write(JSON.stringify({
                    error: `Window ${cmd.winid} not found`
                }) + '\n');
                return;
            }

            win.loadURL(cmd.url);
            win.webContents.once("did-finish-load", function() {
                connection.write(JSON.stringify({}) + '\n');
            });
            
            win.webContents.once("did-fail-load", function(event, errorCode, errorDescription) {
                connection.write(JSON.stringify({
                    error: `Failed to load: ${errorDescription}`
                }) + '\n');
            });
            
        } else if (cmd.cmd == 'closewindow') {
            const win = BrowserWindow.fromId(cmd.winid);
            if (win) {
                win.destroy();
            }
            connection.write(JSON.stringify({}) + '\n');
            
        } else if (cmd.cmd == 'newwindow') {
            createWindow(connection, cmd.options);
            
        } else {
            connection.write(JSON.stringify({
                error: `Unknown command: ${cmd.cmd}`
            }) + '\n');
        }
    } catch (error) {
        connection.write(JSON.stringify({
            error: `Command processing error: ${error.toString()}`
        }) + '\n');
    }
}

function secure_connect(addr, secure_cookie) {
    const connection = net.connect(addr);
    connection.setEncoding('utf8');
    connection.write(secure_cookie);
    return connection;
}

// Handle IPC messages from renderer processes
ipcMain.on('msg-for-julia-process', (event, arg) => {
    const win_id = BrowserWindow.fromWebContents(event.sender).id;
    safe_sysnotify_write({
        cmd: "msg_from_window",
        winid: win_id,
        payload: arg
    });
});

// Application ready handler
app.on('ready', function () {
    // Parse command line arguments - adjust indices since argv[0] = electron, argv[1] = main.js
    const secure_cookie = Buffer.from(process.argv[4], 'base64');
    
    // Parse security configuration if provided
    if (process.argv[5]) {
        try {
            security_config = JSON.parse(Buffer.from(process.argv[5], 'base64').toString());
            console.log('ElectronCall: Using security configuration', {
                contextIsolation: security_config.context_isolation,
                sandbox: security_config.sandbox,
                nodeIntegration: security_config.node_integration
            });
        } catch (error) {
            console.error('ElectronCall: Failed to parse security configuration:', error);
            security_config = null;
        }
    }

    // Connect to Julia process
    const connection = secure_connect(process.argv[2], secure_cookie);
    sysnotify_connection = secure_connect(process.argv[3], secure_cookie);
    
    // Handle sysnotify connection errors silently during cleanup
    sysnotify_connection.on('error', function(error) {
        if (error.code !== 'EPIPE' && error.code !== 'ECONNRESET') {
            console.error('ElectronCall: Sysnotify connection error:', error);
        }
        // Don't propagate EPIPE/ECONNRESET errors as uncaught exceptions
    });

    connection.on('end', function () {
        safe_sysnotify_write({cmd: "appclosing"});
        app.quit();
    });

    connection.on('error', function(error) {
        console.error('ElectronCall: Connection error:', error);
        safe_sysnotify_write({
            cmd: "error",
            message: error.toString()
        });
    });

    // Set up command processing
    const rloptions = {
        input: connection,
        terminal: false,
        historySize: 0,  
        crlfDelay: Infinity
    };
    const rl = readline.createInterface(rloptions);

    rl.on('line', function (line) {
        try {
            const cmd_as_json = JSON.parse(line);
            process_command(connection, cmd_as_json);
        } catch (error) {
            console.error('ElectronCall: Failed to parse command:', error);
            connection.write(JSON.stringify({
                error: `Invalid JSON command: ${error.toString()}`
            }) + '\n');
        }
    });

    rl.on('error', function(error) {
        console.error('ElectronCall: Readline error:', error);
    });
});

// Handle all windows closed
app.on('window-all-closed', function() {
    // Keep the app running even when all windows are closed
    // This matches the behavior expected by the Julia side
});

// Handle app activation (macOS)
app.on('activate', function() {
    // On macOS, re-create a window when the dock icon is clicked
    // This is handled by the Julia side, so we don't need to do anything here
});

// Handle uncaught exceptions
process.on('uncaughtException', function(error) {
    console.error('ElectronCall: Uncaught exception:', error);
    safe_sysnotify_write({
        cmd: "error",
        message: `Uncaught exception: ${error.toString()}`
    });
});

process.on('unhandledRejection', function(reason, promise) {
    console.error('ElectronCall: Unhandled rejection at:', promise, 'reason:', reason);
    safe_sysnotify_write({
        cmd: "error", 
        message: `Unhandled rejection: ${reason}`
    });
});