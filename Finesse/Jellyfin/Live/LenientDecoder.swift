import Foundation
import OSLog

/// Decodes server responses so that one value the SDK doesn't understand can't fail a whole list.
///
/// The SDK's generated types use strict enums and optional fields, and the server may be newer than
/// the SDK. When decoding fails, `DecodingError` says exactly which value was at fault. That value
/// is removed everywhere it appears and decoding tries again. If what it belongs to can't exist
/// without it, that goes instead, working outwards. Anything else is still reported as an error.
enum LenientDecoder {
    private static let maxRepairs = 32
    private static let logger = Logger(subsystem: "Finesse", category: "Decoding")

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = makeDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch let original as DecodingError {
            guard var json = try? JSONSerialization.jsonObject(with: data) else { throw original }
            var error = original
            for _ in 0..<maxRepairs {
                guard let repaired = repair(json, after: error) else { throw original }
                json = repaired
                // Names the field only, because values can be anything the server sent.
                let field = error.path.last?.stringValue ?? ""
                logger.notice("Ignored a value the app doesn't understand in \(field, privacy: .public)")
                do {
                    return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: json))
                } catch let next as DecodingError {
                    error = next
                }
            }
            throw original
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        return decoder
    }

    /// The server writes seven digits of fractional seconds, and sometimes omits the time zone.
    private static func parseDate(_ text: String) -> Date? {
        let utc = TimeZone(secondsFromGMT: 0)!
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: utc)
        let whole = Date.ISO8601FormatStyle(timeZone: utc)
        let styles = [
            fractional,
            whole,
            fractional.year().month().day().time(includingFractionalSeconds: true),
            whole.year().month().day().time(includingFractionalSeconds: false),
        ]
        for style in styles {
            if let match = text.wholeMatch(of: style) {
                return match.output
            }
        }
        return nil
    }

    private static func repair(_ json: Any, after error: DecodingError) -> Any? {
        let path = error.path.map(JSONKey.init)
        if case .keyNotFound = error {
            // The object missing a required key can't be used. If that object is required too, the
            // next attempt reports its parent, so this removes the least it can.
            return removing(path: path, from: json)
        }
        guard let last = path.last else { return nil }
        switch last {
        case .index:
            return removing(path: path, from: json)
        case .name(let name):
            guard let value = value(at: path, in: json) else { return nil }
            return removingEverywhere(name: name, value: value, from: json)
        }
    }

    private enum JSONKey {
        case name(String)
        case index(Int)

        init(_ key: CodingKey) {
            self = key.intValue.map(JSONKey.index) ?? .name(key.stringValue)
        }
    }

    private static func value(at path: [JSONKey], in json: Any) -> Any? {
        var current = json
        for key in path {
            switch key {
            case .name(let name):
                guard let next = (current as? [String: Any])?[name] else { return nil }
                current = next
            case .index(let index):
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return current
    }

    /// One bad value usually repeats across a list, so removing them all saves a retry per item.
    private static func removingEverywhere(name: String, value: Any, from json: Any) -> Any {
        if var object = json as? [String: Any] {
            if let found = object[name] as? NSObject, let target = value as? NSObject, found.isEqual(target) {
                object[name] = nil
            }
            return object.mapValues { removingEverywhere(name: name, value: value, from: $0) }
        }
        if let array = json as? [Any] {
            return array.map { removingEverywhere(name: name, value: value, from: $0) }
        }
        return json
    }

    private static func removing(path: [JSONKey], from json: Any) -> Any? {
        guard let first = path.first else { return nil }
        let rest = Array(path.dropFirst())
        switch first {
        case .name(let name):
            guard var object = json as? [String: Any], let child = object[name] else { return nil }
            object[name] = rest.isEmpty ? nil : removing(path: rest, from: child)
            return object
        case .index(let index):
            guard var array = json as? [Any], array.indices.contains(index) else { return nil }
            if rest.isEmpty {
                array.remove(at: index)
            } else {
                guard let child = removing(path: rest, from: array[index]) else { return nil }
                array[index] = child
            }
            return array
        }
    }
}

private extension DecodingError {
    var path: [CodingKey] {
        switch self {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            return context.codingPath
        @unknown default:
            return []
        }
    }
}
