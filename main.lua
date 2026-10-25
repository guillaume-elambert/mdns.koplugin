--[[--
mDNS Responder plugin for KOReader.

Announces the device on the local network via multicast DNS (Bonjour/Avahi)
so it can be reached at `<hostname>.local`.  Starts automatically when Wi-Fi
connects and stops when it disconnects.

The underlying mDNS implementation is borrowed from the FileSync plugin
(`filesync.koplugin/filesync/mdns.lua`).  A vendored copy lives at
`lib/mdns.lua` inside this plugin directory.

@module koplugin.mdns
--]]--

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local socket = require("socket")
local _ = require("gettext")

-- Resolve the plugin's own directory so we can load lib/mdns.lua and store
-- settings next to the plugin itself.
local _plugin_dir = debug.getinfo(1, "S").source:match("@(.+)/[^/]+$") or "."

-- Settings file lives in KOReader's settings directory (alongside
-- `settings.reader.lua`), following the convention used by contrib plugins.
local DataStorage = require("datastorage")
local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/mdns.lua"

-- Default hostname when the user has not configured one.
local DEFAULT_HOSTNAME = "koreader"

local MdnsPlugin = WidgetContainer:extend{
    name = "mdns",
    is_doc_only = false,
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

--- Detect the device's local IP address, trying multiple methods.
--- Mirrors the approach used by the FileSync plugin.
--- @return string|nil: IPv4 address, or nil if unavailable
local function getLocalIP()
    -- Method 1: KOReader's NetworkMgr
    if NetworkMgr and NetworkMgr.getLocalIpAddress then
        local ip = NetworkMgr:getLocalIpAddress()
        if ip and ip ~= "0.0.0.0" and ip ~= "127.0.0.1" then
            return ip
        end
    end

    -- Method 2: Parse ifconfig / ip addr output
    local fd = io.popen("ifconfig 2>/dev/null || ip addr show 2>/dev/null")
    if fd then
        local output = fd:read("*all")
        fd:close()
        if output then
            for ip in output:gmatch("inet%s+(%d+%.%d+%.%d+%.%d+)") do
                if ip ~= "127.0.0.1" then
                    return ip
                end
            end
        end
    end

    -- Method 3: UDP socket trick (does not send data)
    local s = socket.udp()
    if s then
        s:setpeername("8.8.8.8", 80)
        local ip = s:getsockname()
        s:close()
        if ip and ip ~= "0.0.0.0" then
            return ip
        end
    end

    return nil
end

--- Open the Kindle firewall for a UDP port (no-op on other platforms).
local function openKindleFirewall(port)
    if not Device:isKindle() then return end
    port = tonumber(port)
    if not port then return end
    os.execute(string.format(
        "iptables -A INPUT -p udp --dport %d -j ACCEPT 2>/dev/null", port))
    logger.info("mDNS: Kindle firewall rule added for UDP port", port)
end

--- Close the Kindle firewall for a UDP port.
local function closeKindleFirewall(port)
    if not Device:isKindle() then return end
    port = tonumber(port)
    if not port then return end
    os.execute(string.format(
        "iptables -D INPUT -p udp --dport %d -j ACCEPT 2>/dev/null", port))
    logger.info("mDNS: Kindle firewall rule removed for UDP port", port)
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function MdnsPlugin:init()
    -- Load persisted settings.
    self.settings = LuaSettings:open(SETTINGS_FILE)
    -- Runtime state.
    self._mdns = nil

    -- Register ourselves into the menu system.
    self.ui.menu:registerToMainMenu(self)

    -- If Wi-Fi is already connected when the plugin loads, start mDNS
    -- immediately (e.g. after a reader restart while connected).
    if NetworkMgr:isConnected() then
        -- Slight delay to let the UI finish initialising.
        UIManager:nextTick(function()
            self:_startMdns()
        end)
    end
end

function MdnsPlugin:onCloseDocument()
    -- Nothing to do; mDNS is device-wide, not per-document.
end

------------------------------------------------------------------------
-- Wi-Fi event handlers
------------------------------------------------------------------------

--- Called by UIManager after the network connection is fully established.
--- This is the equivalent of the `delayedWifiOn` / `NetworkConnected`
--- event; KOReader broadcasts `Event:new("NetworkConnected")` which
--- WidgetContainer dispatches as `onNetworkConnected`.
function MdnsPlugin:onNetworkConnected()
    logger.dbg("mDNS: NetworkConnected event received")
    self:_startMdns()
end

--- Called when Wi-Fi is about to be torn down.
function MdnsPlugin:onNetworkDisconnected()
    logger.dbg("mDNS: NetworkDisconnected event received")
    self:_stopMdns()
end

------------------------------------------------------------------------
-- mDNS start / stop
------------------------------------------------------------------------

--- Start the mDNS responder.  Safe to call repeatedly (no-op if already
--- running).  Failures are logged but never raise.
function MdnsPlugin:_startMdns()
    if self._mdns and self._mdns:isRunning() then
        logger.dbg("mDNS: already running, skipping start")
        return true
    end

    local ip = getLocalIP()
    if not ip then
        logger.warn("mDNS: no IP address available, responder not started")
        return false
    end

    local hostname = self:_getHostname()
    local ok, result = pcall(function()
        -- Load the vendored mdns module from lib/.
        local Mdns = dofile(_plugin_dir .. "/lib/mdns.lua")
        local mdns = Mdns:new{
            hostname = hostname,
            port = 0,  -- no HTTP service; A-record only
            ip = ip,
        }
        if not mdns:start() then
            return nil
        end
        return mdns
    end)

    if not ok then
        logger.warn("mDNS: responder failed to start:", result)
        return false
    end
    if not result then
        return false
    end

    self._mdns = result
    openKindleFirewall(5353)
    logger.info("mDNS: responder started —", hostname .. ".local", "->", ip)
    return true
end

--- Stop the mDNS responder (sends the goodbye packet).
function MdnsPlugin:_stopMdns()
    if not self._mdns then return end
    pcall(function() self._mdns:stop() end)
    self._mdns = nil
    closeKindleFirewall(5353)
    logger.info("mDNS: responder stopped")
end

------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------

function MdnsPlugin:_getHostname()
    return self.settings:readSetting("hostname", DEFAULT_HOSTNAME)
end

function MdnsPlugin:_setHostname(hostname)
    self.settings:saveSetting("hostname", hostname)
    self.settings:flush()
    -- If the responder is already running, restart it so the new name
    -- takes effect immediately.
    if self._mdns and self._mdns:isRunning() then
        self:_stopMdns()
        self:_startMdns()
    end
end

------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------

function MdnsPlugin:addToMainMenu(menu_items)
    menu_items.mdns = {
        text = _("mDNS Responder"),
        sorting_hint = "network",
        sub_item_table = {
            {
                text_func = function()
                    if self._mdns and self._mdns:isRunning() then
                        return _("Status: running")
                    else
                        return _("Status: stopped")
                    end
                end,
                keep_menu_open = true,
                callback = function()
                    local ip = getLocalIP()
                    local hostname = self:_getHostname()
                    local running = self._mdns and self._mdns:isRunning()
                    local msg
                    if running then
                        msg = _("mDNS responder is active.\n\n") ..
                              _("Hostname: ") .. hostname .. ".local\n" ..
                              _("IP: ") .. (ip or _("unknown"))
                    else
                        msg = _("mDNS responder is not running.\n\n") ..
                              _("It will start automatically when Wi-Fi connects.")
                    end
                    UIManager:show(InfoMessage:new{
                        text = msg,
                    })
                end,
            },
            {
                text_func = function()
                    return _("Hostname: ") .. self:_getHostname()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:_showHostnameDialog(touchmenu_instance)
                end,
                help_text = _("Set the mDNS hostname (the part before .local). Only lowercase letters, digits, and hyphens are allowed."),
            },
            {
                text = _("Start now"),
                enabled_func = function()
                    return not (self._mdns and self._mdns:isRunning())
                end,
                callback = function(touchmenu_instance)
                    if not NetworkMgr:isConnected() then
                        UIManager:show(InfoMessage:new{
                            text = _("Wi-Fi is not connected. Please connect first."),
                        })
                        return
                    end
                    local ok = self:_startMdns()
                    if ok then
                        UIManager:show(InfoMessage:new{
                            text = _("mDNS responder started."),
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Failed to start mDNS responder. Check the logs."),
                        })
                    end
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = _("Stop"),
                enabled_func = function()
                    return self._mdns and self._mdns:isRunning()
                end,
                callback = function(touchmenu_instance)
                    self:_stopMdns()
                    UIManager:show(InfoMessage:new{
                        text = _("mDNS responder stopped."),
                    })
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
        },
    }
end

--- Show a text input dialog for the hostname.
function MdnsPlugin:_showHostnameDialog(touchmenu_instance)
    local Mdns = dofile(_plugin_dir .. "/lib/mdns.lua")
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set mDNS Hostname"),
        input = self:_getHostname(),
        input_hint = DEFAULT_HOSTNAME,
        description = _("Enter the hostname (without .local).\nAllowed: a-z, 0-9, hyphens. Max 63 chars."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_hostname = input_dialog:getInputText()
                        new_hostname = new_hostname:lower():gsub("^%s+", ""):gsub("%s+$", "")
                        if not Mdns.isValidHostname(new_hostname) then
                            UIManager:show(InfoMessage:new{
                                text = _("Invalid hostname. Use 1-63 characters: a-z, 0-9, hyphens (no leading/trailing hyphen)."),
                                icon = "notice-warning",
                            })
                            return
                        end
                        UIManager:close(input_dialog)
                        self:_setHostname(new_hostname)
                        UIManager:show(InfoMessage:new{
                            text = _("Hostname set to: ") .. new_hostname .. ".local",
                        })
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

return MdnsPlugin
