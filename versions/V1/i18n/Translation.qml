import QtQuick
import Quickshell

QtObject {
    id: translation

    readonly property string rawLocale: Quickshell.env("LC_ALL") !== ""
        ? Quickshell.env("LC_ALL")
        : Quickshell.env("LC_MESSAGES") !== ""
            ? Quickshell.env("LC_MESSAGES")
            : Quickshell.env("LANG")
    readonly property string language: normalizeLanguage(rawLocale)
    readonly property string localeName: language === "it" ? "it_IT" : "en_US"

    readonly property var italian: ({
        "Weather": "Meteo",
        "Today": "Oggi",
        "Tomorrow": "Domani",
        "Location": "Località",
        "Feels like": "Percepita",
        "Humidity": "Umidità",
        "Wind": "Vento",
        "3-DAY FORECAST": "PREVISIONI 3 GIORNI",
        "rain": "pioggia",
        "Refreshing…": "Aggiornamento…",
        "Refresh": "Aggiorna",
        "metric": "metrico",
        "imperial": "imperiale"
    })

    function normalizeLanguage(value) {
        var candidate = String(value || "").trim().toLowerCase().replace("-", "_")
        return candidate.indexOf("it") === 0 ? "it" : "en"
    }

    function tr(source) {
        var value = String(source || "")
        if (language === "it" && italian[value] !== undefined)
            return italian[value]
        return value
    }

    function weekdayShort(dayOfWeek) {
        // 2023-01-01 was a Sunday; offset from it to get a stable weekday name.
        var date = new Date(2023, 0, 1 + dayOfWeek)
        return date.toLocaleString(Qt.locale(localeName), "ddd").slice(0, 2).toUpperCase()
    }

    function monthName(year, month) {
        return new Date(year, month, 1)
            .toLocaleString(Qt.locale(localeName), "MMMM")
            .toUpperCase()
    }
}
