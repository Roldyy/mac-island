import Foundation

/// The kinds of status chip the open island can show. A closed list: the raw value is what the layout stores.
public enum StatusChipKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case network, ip, load, disk, batteryHealth, nextEvent, topApp, devices, timer

    public var id: String { rawValue }

    /// French name, for the Settings page and VoiceOver.
    public var title: String {
        switch self {
        case .network: "Réseau"
        case .ip: "Adresse IP"
        case .load: "Charge"
        case .disk: "Disque"
        case .batteryHealth: "Batterie"
        case .nextEvent: "Prochain rendez-vous"
        case .topApp: "Appli gourmande"
        case .devices: "Appareils"
        case .timer: "Minuteur"
        }
    }

    /// One line under the title in the Settings page.
    public var summary: String {
        switch self {
        case .network: "Connexion (Wi-Fi, Ethernet ou hors ligne) et débits."
        case .ip: "Adresse IP locale ; l’adresse publique seulement au clic."
        case .load: "Processeur et mémoire, avec la température si elle est lisible."
        case .disk: "Espace libre sur le disque de démarrage."
        case .batteryHealth: "Santé de la batterie : capacité et cycles."
        case .nextEvent: "Le prochain rendez-vous du calendrier."
        case .topApp: "L’appli qui sollicite le plus le processeur."
        case .devices: "Batterie des appareils Bluetooth connectés."
        case .timer: "Le minuteur en cours."
        }
    }

    /// SF Symbol of the chip when it has no better one of its own.
    public var symbol: String {
        switch self {
        case .network: "wifi"
        case .ip: "number"
        case .load: "cpu"
        case .disk: "internaldrive"
        case .batteryHealth: "battery.100"
        case .nextEvent: "calendar"
        case .topApp: "flame"
        case .devices: "headphones"
        case .timer: "timer"
        }
    }
}
