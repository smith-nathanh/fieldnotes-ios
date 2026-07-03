import Foundation
import FieldnotesCore
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct DetectionRepository: Sendable {
    private let databaseName = "fieldnotes.sqlite3"
    private let legacyJSONName = "detections.json"

    func load() async throws -> [FieldDetection] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try createSchema(in: database)
        let detections = try fetchDetections(in: database)
        guard detections.isEmpty else {
            return detections
        }

        let legacyDetections = try loadLegacyJSONDetections()
        if !legacyDetections.isEmpty {
            try execute("BEGIN IMMEDIATE TRANSACTION", in: database)
            do {
                try insert(legacyDetections, in: database)
                try execute("COMMIT", in: database)
            } catch {
                try? execute("ROLLBACK", in: database)
                throw error
            }
        }
        return legacyDetections.sorted { $0.detectedAt > $1.detectedAt }
    }

    func save(_ detections: [FieldDetection]) async throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        try createSchema(in: database)
        try execute("BEGIN IMMEDIATE TRANSACTION", in: database)
        do {
            try execute("DELETE FROM detections", in: database)
            try insert(detections, in: database)
            try execute("COMMIT", in: database)
        } catch {
            try? execute("ROLLBACK", in: database)
            throw error
        }
    }

    private func fetchDetections(in database: OpaquePointer) throws -> [FieldDetection] {
        let sql = """
        SELECT id, scientific_name, common_name, taxon, source, confidence, detected_at, clip_path, latitude, longitude, week
        FROM detections
        ORDER BY detected_at DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database, message: "Could not prepare detection load")
        }
        defer { sqlite3_finalize(statement) }

        var detections: [FieldDetection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            detections.append(try decodeDetection(from: statement))
        }
        return detections
    }

    private func databaseURL() throws -> URL {
        try documentsDirectory().appendingPathComponent(databaseName)
    }

    private func legacyJSONURL() throws -> URL {
        try documentsDirectory().appendingPathComponent(legacyJSONName)
    }

    private func documentsDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory
    }

    private func loadLegacyJSONDetections() throws -> [FieldDetection] {
        let url = try legacyJSONURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.fieldnotes.decode([FieldDetection].self, from: data)
    }

    private func openDatabase() throws -> OpaquePointer {
        var database: OpaquePointer?
        let url = try databaseURL()
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw DetectionRepositoryError.openFailed
        }
        return database
    }

    private func createSchema(in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS detections (
                id TEXT PRIMARY KEY NOT NULL,
                scientific_name TEXT NOT NULL,
                common_name TEXT NOT NULL,
                taxon TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'audio',
                confidence REAL NOT NULL,
                detected_at TEXT NOT NULL,
                clip_path TEXT,
                latitude REAL,
                longitude REAL,
                week INTEGER NOT NULL
            )
            """,
            in: database
        )
        try addColumnIfNeeded(
            named: "source",
            definition: "TEXT NOT NULL DEFAULT 'audio'",
            in: "detections",
            database: database
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_detections_species_seen ON detections(scientific_name, detected_at)",
            in: database
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_detections_seen ON detections(detected_at)",
            in: database
        )
    }

    private func insert(_ detections: [FieldDetection], in database: OpaquePointer) throws {
        let sql = """
        INSERT OR REPLACE INTO detections (
            id, scientific_name, common_name, taxon, source, confidence, detected_at, clip_path, latitude, longitude, week
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database, message: "Could not prepare detection insert")
        }
        defer { sqlite3_finalize(statement) }

        for detection in detections {
            sqlite3_bind_text(statement, 1, detection.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, detection.scientificName, -1, sqliteTransient)
            sqlite3_bind_text(statement, 3, detection.commonName, -1, sqliteTransient)
            sqlite3_bind_text(statement, 4, detection.taxon.rawValue, -1, sqliteTransient)
            sqlite3_bind_text(statement, 5, detection.source.rawValue, -1, sqliteTransient)
            sqlite3_bind_double(statement, 6, Double(detection.confidence))
            sqlite3_bind_text(statement, 7, Self.dateFormatter.string(from: detection.detectedAt), -1, sqliteTransient)
            if let clipURL = detection.clipURL {
                sqlite3_bind_text(statement, 8, clipURL.path, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(statement, 8)
            }
            if let latitude = detection.latitude {
                sqlite3_bind_double(statement, 9, latitude)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            if let longitude = detection.longitude {
                sqlite3_bind_double(statement, 10, longitude)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_int(statement, 11, Int32(detection.week))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw sqliteError(database, message: "Could not insert detection")
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func decodeDetection(from statement: OpaquePointer?) throws -> FieldDetection {
        guard
            let idText = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
            let id = UUID(uuidString: idText),
            let scientificName = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
            let commonName = sqlite3_column_text(statement, 2).map({ String(cString: $0) }),
            let taxonRaw = sqlite3_column_text(statement, 3).map({ String(cString: $0) }),
            let sourceRaw = sqlite3_column_text(statement, 4).map({ String(cString: $0) }),
            let detectedAtRaw = sqlite3_column_text(statement, 6).map({ String(cString: $0) }),
            let detectedAt = Self.dateFormatter.date(from: detectedAtRaw)
        else {
            throw DetectionRepositoryError.decodeFailed
        }

        let clipURL: URL?
        if sqlite3_column_type(statement, 7) == SQLITE_NULL {
            clipURL = nil
        } else if let path = sqlite3_column_text(statement, 7).map({ String(cString: $0) }) {
            clipURL = URL(fileURLWithPath: path)
        } else {
            clipURL = nil
        }

        let latitude = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 8)
        let longitude = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 9)

        return FieldDetection(
            id: id,
            scientificName: scientificName,
            commonName: commonName,
            taxon: Taxon(rawValue: taxonRaw) ?? .unknown,
            source: DetectionSource(rawValue: sourceRaw) ?? .audio,
            confidence: Float(sqlite3_column_double(statement, 5)),
            detectedAt: detectedAt,
            clipURL: clipURL,
            latitude: latitude,
            longitude: longitude,
            week: Int(sqlite3_column_int(statement, 10))
        )
    }

    private func addColumnIfNeeded(
        named columnName: String,
        definition: String,
        in tableName: String,
        database: OpaquePointer
    ) throws {
        let columns = try columnNames(in: tableName, database: database)
        guard !columns.contains(columnName) else {
            return
        }
        try execute("ALTER TABLE \(tableName) ADD COLUMN \(columnName) \(definition)", in: database)
    }

    private func columnNames(in tableName: String, database: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(tableName))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database, message: "Could not inspect field log database")
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1).map({ String(cString: $0) }) {
                columns.insert(name)
            }
        }
        return columns
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(database, message: "SQLite statement failed")
        }
    }

    private func sqliteError(_ database: OpaquePointer, message: String) -> Error {
        let detail = sqlite3_errmsg(database).map { String(cString: $0) } ?? "unknown SQLite error"
        return DetectionRepositoryError.queryFailed("\(message): \(detail)")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension JSONDecoder {
    static var fieldnotes: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private enum DetectionRepositoryError: LocalizedError {
    case openFailed
    case decodeFailed
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "Could not open field log database"
        case .decodeFailed:
            return "Could not read field log database"
        case .queryFailed(let message):
            return message
        }
    }
}
