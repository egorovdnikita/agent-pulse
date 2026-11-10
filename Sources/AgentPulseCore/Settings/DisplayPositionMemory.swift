import Foundation

/// Миграция прежних числовых ключей к постоянному идентификатору дисплея.
public enum DisplayPositionMemory {
    public static func offset(in values: inout [String: [Double]], stableID: String, legacyID: String) -> [Double]? {
        func valid(_ offset: [Double]) -> Bool { offset.count == 2 && offset.allSatisfy(\.isFinite) }
        if let offset = values[stableID], valid(offset) { return offset }
        guard let offset = values[legacyID], valid(offset) else { return nil }
        values[stableID] = offset
        if stableID != legacyID { values[legacyID] = nil }
        return offset
    }
}
