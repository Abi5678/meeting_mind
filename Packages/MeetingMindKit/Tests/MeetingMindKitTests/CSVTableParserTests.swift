import Testing

@testable import MeetingMindKit

@Suite("CSVTableParser")
struct CSVTableParserTests {
    @Test("Empty input yields no columns and no rows")
    func emptyInput() {
        let table = CSVTableParser.parse("")
        #expect(table.columns.isEmpty)
        #expect(table.rows.isEmpty)
    }

    @Test("A header with no data rows yields columns and zero rows")
    func headerOnly() {
        let table = CSVTableParser.parse("Name,Status")
        #expect(table.columns.map(\.name) == ["Name", "Status"])
        #expect(table.rows.isEmpty)
    }

    @Test("A simple table parses column names and row values by column id")
    func simpleTable() throws {
        let table = CSVTableParser.parse("Name,Owner\nWireframe download flow,Priya\nBenchmark small.en,Sam")

        #expect(table.columns.map(\.name) == ["Name", "Owner"])
        try #require(table.rows.count == 2)

        let nameColumn = table.columns[0].id
        let ownerColumn = table.columns[1].id
        #expect(table.rows[0].values[nameColumn] == "Wireframe download flow")
        #expect(table.rows[0].values[ownerColumn] == "Priya")
        #expect(table.rows[1].values[nameColumn] == "Benchmark small.en")
    }

    @Test("Each column gets a distinct id")
    func distinctColumnIDs() {
        let table = CSVTableParser.parse("A,B,C")
        let ids = Set(table.columns.map(\.id))
        #expect(ids.count == 3)
    }

    @Test("A quoted field containing a comma is not split")
    func quotedFieldWithComma() throws {
        let table = CSVTableParser.parse("Name,Notes\nTask,\"Ship, then iterate\"")
        try #require(table.columns.count == 2)
        try #require(table.rows.count == 1)
        #expect(table.rows[0].values[table.columns[1].id] == "Ship, then iterate")
    }

    @Test("A quoted field containing an embedded newline stays one field")
    func quotedFieldWithNewline() throws {
        let table = CSVTableParser.parse("Name,Notes\nTask,\"Line one\nLine two\"")
        try #require(table.rows.count == 1)
        let notesColumn = table.columns[1].id
        #expect(table.rows[0].values[notesColumn] == "Line one\nLine two")
    }

    @Test("A doubled quote inside a quoted field decodes to one literal quote")
    func escapedQuote() throws {
        let table = CSVTableParser.parse("Name\n\"She said \"\"hi\"\"\"")
        try #require(table.columns.count == 1)
        try #require(table.rows.count == 1)
        #expect(table.rows[0].values[table.columns[0].id] == "She said \"hi\"")
    }

    @Test("CRLF line endings parse the same as LF")
    func crlfLineEndings() throws {
        let table = CSVTableParser.parse("Name,Owner\r\nTask,Priya\r\n")
        try #require(table.rows.count == 1)
        #expect(table.rows[0].values[table.columns[0].id] == "Task")
        #expect(table.rows[0].values[table.columns[1].id] == "Priya")
    }

    @Test("A trailing newline does not produce a phantom empty row")
    func noTrailingPhantomRow() {
        let table = CSVTableParser.parse("Name\nOnly\n")
        #expect(table.rows.count == 1)
    }

    @Test("A file with no trailing newline still parses its last row")
    func noTrailingNewline() throws {
        let table = CSVTableParser.parse("Name\nOnly")
        try #require(table.rows.count == 1)
        #expect(table.rows[0].values[table.columns[0].id] == "Only")
    }

    @Test("A leading UTF-8 byte-order mark is stripped from the header")
    func stripsByteOrderMark() {
        let table = CSVTableParser.parse("\u{FEFF}Name,Owner\nTask,Priya")
        #expect(table.columns.map(\.name) == ["Name", "Owner"])
    }

    @Test("A short row is padded with empty values for the remaining columns")
    func raggedRowPadding() throws {
        let table = CSVTableParser.parse("A,B,C\nonly-a")
        try #require(table.columns.count == 3)
        try #require(table.rows.count == 1)
        #expect(table.rows[0].values[table.columns[0].id] == "only-a")
        #expect(table.rows[0].values[table.columns[1].id] == "")
        #expect(table.rows[0].values[table.columns[2].id] == "")
    }

    // MARK: - Type inference

    @Test("A column of Yes/No values infers as checkbox")
    func checkboxInference() throws {
        let table = CSVTableParser.parse("Done\nYes\nNo\nyes\nno")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .checkbox)
    }

    @Test("A column of numeric strings infers as number")
    func numberInference() throws {
        let table = CSVTableParser.parse("Count\n1\n2.5\n-3")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .number)
    }

    @Test("A column of Notion-format dates infers as date")
    func dateInference() throws {
        // The dates must be quoted: they contain a literal comma, which is a field
        // separator when unquoted — this is exercising date inference, not CSV escaping.
        let table = CSVTableParser.parse("Due\n\"July 8, 2026\"\n\"July 9, 2026\"")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .date)
    }

    @Test("A column of ISO 8601 dates also infers as date")
    func iso8601DateInference() throws {
        let table = CSVTableParser.parse("Due\n2026-07-08T10:00:00Z")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .date)
    }

    @Test("A column of free text infers as text")
    func textInference() throws {
        let table = CSVTableParser.parse("Name\nAlpha\nBeta")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .text)
    }

    @Test("A column with mixed types falls back to text")
    func mixedTypeFallsBackToText() throws {
        let table = CSVTableParser.parse("Value\n1\nYes\n\"July 8, 2026\"")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .text)
    }

    @Test("Blank cells are ignored when inferring a column's type")
    func blanksIgnoredForInference() throws {
        let table = CSVTableParser.parse("Count\n1\n\n2\n")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .number)
    }

    @Test("A column that is entirely blank infers as text")
    func allBlankInfersText() throws {
        let table = CSVTableParser.parse("Notes\n\n\n")
        try #require(table.columns.count == 1)
        #expect(table.columns[0].type == .text)
    }
}
