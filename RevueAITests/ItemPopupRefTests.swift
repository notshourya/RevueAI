import Foundation
import Testing
@testable import RevueAI

struct ItemPopupRefTests {
    @Test func roundTripsThroughCodable() throws {
        let id = UUID()
        let refs: [ItemPopupRef] = [.actionItem(id), .question(id), .decision(id)]
        for ref in refs {
            let data = try JSONEncoder().encode(ref)
            let decoded = try JSONDecoder().decode(ItemPopupRef.self, from: data)
            #expect(decoded == ref)
        }
    }
}
