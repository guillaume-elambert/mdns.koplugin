local _ = require("gettext")
return {
    name = "mdns",
    fullname = _("mDNS Responder"),
    description = _([[Announces the device on the local network via mDNS (Bonjour/Avahi) so it can be reached at <hostname>.local. Starts automatically when Wi-Fi connects and stops when it disconnects.]]),
}
