import Foundation

/// The results as CSV, built only when the user clicks an export button. Cells that a spreadsheet could read as a
/// formula get a leading apostrophe; quotes, commas and line breaks are escaped.
public enum CSVExport {
    public static let header = ["IP", "Nom", "MAC", "Fabricant", "Latence (ms)", "Ports ouverts", "Passerelle"]

    public static func csv(_ records: [DeviceRecord]) -> String {
        var lines = [header.map(cell).joined(separator: ",")]
        for record in records {
            let latency = record.latencyMs.map { String(format: "%.1f", $0) } ?? ""
            let fields = [record.ip.description, record.displayName ?? "", record.mac?.description ?? "", record.vendor ?? "",
                          latency, record.openPorts.map(String.init).joined(separator: " "), record.isGateway ? "oui" : ""]
            lines.append(fields.map(cell).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func cell(_ raw: String) -> String {
        var text = raw
        if let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) { text = "'" + text }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
