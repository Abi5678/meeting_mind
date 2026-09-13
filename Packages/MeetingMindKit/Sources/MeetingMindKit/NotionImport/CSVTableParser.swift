import Foundation

/// Parses one Notion database export CSV into a `ParsedTable`.
///
/// CSV has no type system, so every value round-trips as a string; column `type` is inferred by
/// sampling every value in the column. A column with a mix of types (or none at all) falls back
/// to `.text` — Notion's own `select`/`multi-select`/`person`/`URL` columns all land here too,
/// which loses the distinction but loses no data.
public enum CSVTableParser {
    public struct ParsedColumn: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let type: ColumnType
    }

    public enum ColumnType: Equatable, Sendable {
        case text, number, date, checkbox
    }

    public struct ParsedRow: Equatable, Sendable {
        public let id: UUID
        /// Raw string values keyed by column id; empty string for a blank cell.
        public var values: [UUID: String]
    }

    public struct ParsedTable: Equatable, Sendable {
        public let columns: [ParsedColumn]
        public let rows: [ParsedRow]
    }

    public static func parse(_ csv: String) -> ParsedTable {
        let records = parseRecords(stripByteOrderMark(csv))
        guard let header = records.first else {
            return ParsedTable(columns: [], rows: [])
        }

        let dataRecords = Array(records.dropFirst())
        let columnIDs = header.map { _ in UUID() }

        let columns = header.indices.map { columnIndex in
            let values = dataRecords.map { columnIndex < $0.count ? $0[columnIndex] : "" }
            return ParsedColumn(id: columnIDs[columnIndex], name: header[columnIndex], type: inferType(values))
        }

        let rows = dataRecords.map { record -> ParsedRow in
            var values: [UUID: String] = [:]
            for (columnIndex, id) in columnIDs.enumerated() {
                values[id] = columnIndex < record.count ? record[columnIndex] : ""
            }
            return ParsedRow(id: UUID(), values: values)
        }

        return ParsedTable(columns: columns, rows: rows)
    }

    // MARK: - Type inference

    private static func inferType(_ values: [String]) -> ColumnType {
        let nonBlank = values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !nonBlank.isEmpty else { return .text }

        // Notion's CSV export renders a checked checkbox as "Yes" and unchecked as "No".
        if nonBlank.allSatisfy({ $0.caseInsensitiveCompare("Yes") == .orderedSame || $0.caseInsensitiveCompare("No") == .orderedSame }) {
            return .checkbox
        }
        if nonBlank.allSatisfy({ Double($0) != nil }) {
            return .number
        }
        if nonBlank.allSatisfy({ parseDate($0) != nil }) {
            return .date
        }
        return .text
    }

    /// Formatters are built per call, not cached as static state, so this type carries no
    /// mutable global (Foundation's formatter classes are not `Sendable`).
    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }

        let notionDate = DateFormatter()
        notionDate.locale = Locale(identifier: "en_US_POSIX")
        notionDate.dateFormat = "MMMM d, yyyy"  // Notion's default CSV date format, e.g. "July 8, 2026"
        return notionDate.date(from: value)
    }

    // MARK: - CSV tokenizing (RFC 4180: quoted fields, embedded commas/newlines, "" escapes)

    private static func stripByteOrderMark(_ csv: String) -> String {
        guard let first = csv.unicodeScalars.first, first == "\u{FEFF}" else { return csv }
        return String(csv.dropFirst())
    }

    /// Tokenizes over Unicode scalars, not `Character`. Swift's `Character` is an *extended
    /// grapheme cluster*, and CR+LF is one of the sequences that clusters into a single
    /// `Character` — so a `[Character]` tokenizer's `case "\r"` / `case "\n"` never fires on a
    /// CRLF file; the whole cluster falls through to `default` and gets appended as literal
    /// content instead of ending the record. Scalars don't cluster, so CR and LF always compare
    /// individually regardless of what is adjacent to them.
    private static func parseRecords(_ csv: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var insideQuotes = false

        let scalars = Array(csv.unicodeScalars)
        var i = 0

        let quote: Unicode.Scalar = "\""

        while i < scalars.count {
            let scalar = scalars[i]

            if insideQuotes {
                if scalar == quote {
                    if i + 1 < scalars.count, scalars[i + 1] == quote {
                        field.unicodeScalars.append(quote)
                        i += 2
                    } else {
                        insideQuotes = false
                        i += 1
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                    i += 1
                }
                continue
            }

            switch scalar {
            case quote:
                insideQuotes = true
                i += 1
            case ",":
                record.append(field)
                field = ""
                i += 1
            case "\r":
                i += 1  // swallow; the following "\n" (if any) ends the record
            case "\n":
                record.append(field)
                records.append(record)
                record = []
                field = ""
                i += 1
            default:
                field.unicodeScalars.append(scalar)
                i += 1
            }
        }

        // A final line with no trailing newline still needs to be flushed.
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }

        return records
    }
}
