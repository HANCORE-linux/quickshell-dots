.pragma library

var icons = {
    "lan": "\uEB2F",
    "wifi_off": "\uE648",
    "signal_wifi_off": "\uE1DA",
    "signal_wifi_0_bar": "\uF0B0",
    "wifi_1_bar": "\uE4CA",
    "network_wifi_1_bar": "\uEBE4",
    "wifi_2_bar": "\uE4D9",
    "network_wifi_2_bar": "\uEBD6",
    "network_wifi_3_bar": "\uEBE1",
    "signal_wifi_4_bar": "\uF065",
    "bluetooth": "\uE1A7",
    "bluetooth_connected": "\uE1A8",
    "bluetooth_disabled": "\uE1A9",
    "volume_up": "\uE050",
    "volume_down": "\uE04D",
    "volume_mute": "\uE04E",
    "volume_off": "\uE04F",
    "headphones": "\uE8F0",
    "mic": "\uE029",
    "mic_off": "\uE02B",
    "memory": "\uE322",
    "storage": "\uE1DB",
    "speed": "\uE9E4",
    "package_2": "\uF569",
    "bt_gamepad": "\uE338",
    "bt_speaker": "\uE32D",
    "bt_headset": "\uE310",
    "bt_headphones": "\uF01F",
    "bt_phone": "\uE32C",
    "bt_computer": "\uE30A",
    "bt_printer": "\uE8AD",
    "bt_scanner": "\uE329",
    "bt_keyboard": "\uE312",
    "bt_mouse": "\uE323",
    "bt_watch": "\uE334",
    "bt_tv": "\uE333",
    "bt_router": "\uE328",
    "bt_generic": "\uE337",
}

function icon(name) {
    return icons[name] || name
}

function btTypeIcon(bluezIcon) {
    var names = {
        "audio-card": "bt_speaker",
        "audio-speakers": "bt_speaker",
        "audio-headset": "bt_headset",
        "audio-headphones": "bt_headphones",
        "audio-input-microphone": "bt_headset",
        "input-gaming": "bt_gamepad",
        "input-keyboard": "bt_keyboard",
        "input-mouse": "bt_mouse",
        "phone": "bt_phone",
        "computer": "bt_computer",
        "printer": "bt_printer",
        "scanner": "bt_scanner",
        "video-display": "bt_tv",
        "tv": "bt_tv",
        "network-wireless": "bt_router",
        "modem": "bt_router",
        "watch": "bt_watch"
    }
    var key = (bluezIcon || "").toLowerCase()
    if (names[key]) return icons[names[key]]
    if (key.indexOf("audio") === 0) return icons.bt_headphones
    if (key.indexOf("phone") === 0) return icons.bt_phone
    return icons.bluetooth || icons.bt_generic
}
