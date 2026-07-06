import Foundation

/// Fuzzy near-duplicate detection for extracted points — the code-level
/// backstop behind the prompts' merge / known-points instructions.
enum PointDedup {
    /// Normalizes a phrase to lowercase alphanumeric words for comparison.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when two normalized phrases are near-duplicates — one contains the
    /// other, or they share at least 80% of the smaller phrase's words.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b || a.contains(b) || b.contains(a) { return true }
        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }
        let overlap = wordsA.intersection(wordsB).count
        return Double(overlap) / Double(min(wordsA.count, wordsB.count)) >= 0.8
    }

    /// True when `candidate` is a near-duplicate of anything in `existing`.
    /// Takes raw strings. An empty/whitespace candidate counts as a duplicate
    /// so callers uniformly skip it.
    static func containsSimilar(_ candidate: String, in existing: [String]) -> Bool {
        let key = normalize(candidate)
        guard !key.isEmpty else { return true }
        return existing.contains { similar(normalize($0), key) }
    }
}
