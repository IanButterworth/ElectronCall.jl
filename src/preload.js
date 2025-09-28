/**
 * ElectronCall Preload Script
 * 
 * This script runs in the renderer process with access to Node.js APIs,
 * but in an isolated context. It provides a secure bridge between the
 * renderer process and the main process.
 */

const { contextBridge, ipcRenderer } = require('electron');

// Define the API that will be exposed to the renderer process
const electronAPI = {
    /**
     * Send a message to the Julia process
     * @param {any} message - The message to send
     */
    sendMessageToJulia: (message) => {
        ipcRenderer.send('msg-for-julia-process', message);
    },

    /**
     * Invoke an RPC function registered in Julia
     * @param {string} functionName - Name of the Julia function to call
     * @param {Array} args - Arguments to pass to the function
     * @returns {Promise<any>} Promise resolving to the function result
     */
    invoke: async (functionName, args = []) => {
        return ipcRenderer.invoke('julia-rpc-call', functionName, args);
    },

    /**
     * Listen for events from the main process
     * @param {string} channel - Event channel name
     * @param {Function} callback - Callback function
     */
    on: (channel, callback) => {
        // Validate channel names to prevent security issues
        const validChannels = [
            'julia-event',
            'window-event',
            'app-event'
        ];
        
        if (validChannels.includes(channel)) {
            ipcRenderer.on(channel, callback);
        } else {
            console.warn(`ElectronCall: Invalid channel '${channel}' - ignored for security`);
        }
    },

    /**
     * Remove all listeners for a channel
     * @param {string} channel - Event channel name
     */
    removeAllListeners: (channel) => {
        const validChannels = [
            'julia-event',
            'window-event', 
            'app-event'
        ];
        
        if (validChannels.includes(channel)) {
            ipcRenderer.removeAllListeners(channel);
        }
    },

    /**
     * Get information about the current environment
     * @returns {Object} Environment information
     */
    getEnvironmentInfo: () => {
        return {
            versions: process.versions,
            platform: process.platform,
            arch: process.arch,
            contextIsolated: true,
            sandbox: process.sandboxed || false
        };
    }
};

// Expose the API to the renderer process
contextBridge.exposeInMainWorld('electronAPI', electronAPI);

// For backwards compatibility, also expose sendMessageToJulia globally
// This allows existing Electron.jl code to work with minimal changes
contextBridge.exposeInMainWorld('sendMessageToJulia', electronAPI.sendMessageToJulia);

// Log successful initialization
console.log('ElectronCall: Secure preload script loaded successfully');
console.log('ElectronCall: Available APIs:', Object.keys(electronAPI));

// Expose security information for debugging
contextBridge.exposeInMainWorld('__electronCallDebug', {
    contextIsolated: true,
    preloadLoaded: true,
    apiVersion: '0.1.0'
});