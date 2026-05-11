import Foundation

// Generator + validator for the 6-character pairing code that
// joins a host and a guest in a Tier 2 cloud-backed duo race.
//
// Alphabet: A-Z + 0-9 minus visually ambiguous characters (0/O,
// 1/I/L). 31 characters × 6 positions = ~887M combinations,
// plenty for the cardinality we need. Even at 100K active
// rooms simultaneously, collision probability is well under
// 1-in-10K per generation; we add a unique constraint on the
// table column so a collision just retries.
//
// Format matches the Postgres CHECK constraint:
//   `pair_code ~ '^[A-Z0-9]{6}$'`
// — note the constraint is loose (allows 0/1/I/L/O) for
// forward compatibility with future code formats. Generation
// is the stricter form.
//
// User-friendliness:
//   • All caps so the user can't be confused by case
//   • No vowels in some positions wouldn't help (codes are
//     short enough to glance at), so we keep the simpler
//     "drop ambiguous chars" rule
//   • The PairingView normalizes the input (uppercase + strip
//     whitespace) before sending so the user can type
//     comfortably in lowercase / with spaces
enum DuoRoomCode {

    // Unambiguous alphabet (no 0/O, no 1/I/L). 31 characters.
    private static let alphabet: [Character] = Array(
        "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    )

    static let length = 6

    // Generate a fresh random code. Caller should retry on the
    // (extremely rare) duplicate-key error from Postgres.
    static func random() -> String {
        var code = ""
        for _ in 0..<length {
            // SystemRandomNumberGenerator is cryptographically
            // secure on Apple platforms; overkill for pairing
            // codes but no reason to use weaker.
            if let pick = alphabet.randomElement() {
                code.append(pick)
            }
        }
        return code
    }

    // Normalize user input from the join screen: uppercase,
    // strip whitespace + dashes. So a user typing "abc-123"
    // or "abc 123 " resolves to "ABC123" before the lookup.
    static func normalize(_ raw: String) -> String {
        raw
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
    }

    // Validate that a normalized code looks right — exactly
    // `length` characters, all in the alphabet (the CHECK
    // constraint is more permissive but we don't want to
    // round-trip a bad code to the server). Returns the
    // normalized form when valid, nil otherwise.
    static func validate(_ raw: String) -> String? {
        let normalized = normalize(raw)
        guard normalized.count == length else { return nil }
        let alphabetSet = Set(alphabet)
        guard normalized.allSatisfy({ alphabetSet.contains($0) }) else {
            return nil
        }
        return normalized
    }
}
