import Foundation
import SQLite3

private let copySQLiteText = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteError: LocalizedError {
    let message: String

    var errorDescription: String? { "媒体库数据库错误：\(message)" }
}

enum SQLiteValue {
    case integer(Int64)
    case text(String)
}

final class Database {
    private let connection: OpaquePointer

    init(url: URL) throws {
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard let connection else {
            throw SQLiteError(message: "无法打开数据库（\(result)）")
        }
        guard result == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(connection))
            sqlite3_close(connection)
            throw SQLiteError(message: message)
        }
        self.connection = connection
        sqlite3_busy_timeout(connection, 5_000)
    }

    deinit { sqlite3_close(connection) }

    func script(_ sql: String) throws {
        try check(sqlite3_exec(connection, sql, nil, nil, nil))
    }

    func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try statement(sql, values) { statement in
            try check(sqlite3_step(statement), expected: SQLITE_DONE)
        }
    }

    func select<Row>(_ sql: String, _ values: [SQLiteValue] = [], row: (OpaquePointer) -> Row) throws -> [Row] {
        try statement(sql, values) { statement in
            var rows: [Row] = []
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                rows.append(row(statement))
                result = sqlite3_step(statement)
            }
            try check(result, expected: SQLITE_DONE)
            return rows
        }
    }

    func repeated(_ sql: String, bindings: [[SQLiteValue]]) throws {
        try statement(sql, []) { statement in
            for values in bindings {
                try bind(values, to: statement)
                try check(sqlite3_step(statement), expected: SQLITE_DONE)
                try check(sqlite3_reset(statement))
            }
        }
    }

    func transaction<T>(write: Bool = true, _ operation: () throws -> T) throws -> T {
        try script(write ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            let value = try operation()
            try script("COMMIT")
            return value
        } catch {
            let operationError = error
            do {
                try script("ROLLBACK")
            } catch {
                throw SQLiteError(message: "\(operationError.localizedDescription)；回滚失败：\(error.localizedDescription)")
            }
            throw operationError
        }
    }

    var insertedID: Int64 { sqlite3_last_insert_rowid(connection) }

    private func statement<T>(_ sql: String, _ values: [SQLiteValue], operation: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(connection, sql, -1, &statement, nil))
        let prepared = statement!
        defer { sqlite3_finalize(prepared) }

        try bind(values, to: prepared)
        return try operation(prepared)
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .integer(let integer):
                try check(sqlite3_bind_int64(statement, position, integer))
            case .text(let text):
                try check(sqlite3_bind_text(statement, position, text, -1, copySQLiteText))
            }
        }
    }

    private func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
        guard result == expected else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(connection)))
        }
    }
}

func textColumn(_ row: OpaquePointer, _ index: Int32) -> String {
    let length = Int(sqlite3_column_bytes(row, index))
    let bytes = UnsafeBufferPointer(start: sqlite3_column_text(row, index), count: length)
    return String(decoding: bytes, as: UTF8.self)
}
