import Foundation

extension String {
    /// Decodes HTML character entities — named (`&ntilde;`, `&amp;`, …) and numeric
    /// (`&#241;`, `&#xF1;`) — into their Unicode characters.
    ///
    /// Both Now Playing metadata from browser sources (e.g. YouTube Music) and scraped
    /// Ultimate Guitar content arrive HTML-encoded, so accented names like "Chance Peña"
    /// otherwise display as "Chance Pe&ntilde;a".
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        var result = self

        // Named entities (except &amp;, decoded last so "&amp;quot;" stays literal).
        // Unknown names are left untouched.
        let ns = result as NSString
        let matches = Self.namedEntityRegex.matches(
            in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: result),
                  let codePoint = Self.namedEntities[String(result[nameRange])],
                  let scalar = Unicode.Scalar(codePoint),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        // Numeric entities: decimal &#NNN; and hexadecimal &#xHH;
        result = result.replacingNumericEntities(pattern: "&#(\\d+);", radix: 10)
        result = result.replacingNumericEntities(pattern: "&#x([0-9a-fA-F]+);", radix: 16)

        // &amp; last.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    private func replacingNumericEntities(pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        var result = self
        let ns = result as NSString
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let digitsRange = Range(match.range(at: 1), in: result),
                  let codePoint = UInt32(result[digitsRange], radix: radix),
                  let scalar = Unicode.Scalar(codePoint),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }

    /// Matches a named entity like `&ntilde;`; capture group 1 is the bare name.
    /// The `[A-Za-z]` start excludes numeric (`&#…`) entities.
    private static let namedEntityRegex = try! NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]+);")

    /// Common HTML named entities → Unicode scalar values. Covers the Latin-1 set
    /// (accented letters that show up constantly in artist/song names) plus frequent
    /// punctuation and symbols. `amp` is intentionally absent (handled last).
    private static let namedEntities: [String: UInt32] = [
        "quot": 0x22, "apos": 0x27, "lt": 0x3C, "gt": 0x3E,
        "nbsp": 0xA0, "iexcl": 0xA1, "cent": 0xA2, "pound": 0xA3, "curren": 0xA4,
        "yen": 0xA5, "brvbar": 0xA6, "sect": 0xA7, "uml": 0xA8, "copy": 0xA9,
        "ordf": 0xAA, "laquo": 0xAB, "not": 0xAC, "shy": 0xAD, "reg": 0xAE,
        "macr": 0xAF, "deg": 0xB0, "plusmn": 0xB1, "sup2": 0xB2, "sup3": 0xB3,
        "acute": 0xB4, "micro": 0xB5, "para": 0xB6, "middot": 0xB7, "cedil": 0xB8,
        "sup1": 0xB9, "ordm": 0xBA, "raquo": 0xBB, "frac14": 0xBC, "frac12": 0xBD,
        "frac34": 0xBE, "iquest": 0xBF,
        "Agrave": 0xC0, "Aacute": 0xC1, "Acirc": 0xC2, "Atilde": 0xC3, "Auml": 0xC4,
        "Aring": 0xC5, "AElig": 0xC6, "Ccedil": 0xC7, "Egrave": 0xC8, "Eacute": 0xC9,
        "Ecirc": 0xCA, "Euml": 0xCB, "Igrave": 0xCC, "Iacute": 0xCD, "Icirc": 0xCE,
        "Iuml": 0xCF, "ETH": 0xD0, "Ntilde": 0xD1, "Ograve": 0xD2, "Oacute": 0xD3,
        "Ocirc": 0xD4, "Otilde": 0xD5, "Ouml": 0xD6, "times": 0xD7, "Oslash": 0xD8,
        "Ugrave": 0xD9, "Uacute": 0xDA, "Ucirc": 0xDB, "Uuml": 0xDC, "Yacute": 0xDD,
        "THORN": 0xDE, "szlig": 0xDF,
        "agrave": 0xE0, "aacute": 0xE1, "acirc": 0xE2, "atilde": 0xE3, "auml": 0xE4,
        "aring": 0xE5, "aelig": 0xE6, "ccedil": 0xE7, "egrave": 0xE8, "eacute": 0xE9,
        "ecirc": 0xEA, "euml": 0xEB, "igrave": 0xEC, "iacute": 0xED, "icirc": 0xEE,
        "iuml": 0xEF, "eth": 0xF0, "ntilde": 0xF1, "ograve": 0xF2, "oacute": 0xF3,
        "ocirc": 0xF4, "otilde": 0xF5, "ouml": 0xF6, "divide": 0xF7, "oslash": 0xF8,
        "ugrave": 0xF9, "uacute": 0xFA, "ucirc": 0xFB, "uuml": 0xFC, "yacute": 0xFD,
        "thorn": 0xFE, "yuml": 0xFF,
        "OElig": 0x152, "oelig": 0x153, "Scaron": 0x160, "scaron": 0x161,
        "Yuml": 0x178, "fnof": 0x192, "circ": 0x2C6, "tilde": 0x2DC,
        "ndash": 0x2013, "mdash": 0x2014, "lsquo": 0x2018, "rsquo": 0x2019,
        "sbquo": 0x201A, "ldquo": 0x201C, "rdquo": 0x201D, "bdquo": 0x201E,
        "dagger": 0x2020, "Dagger": 0x2021, "bull": 0x2022, "hellip": 0x2026,
        "permil": 0x2030, "prime": 0x2032, "Prime": 0x2033, "lsaquo": 0x2039,
        "rsaquo": 0x203A, "oline": 0x203E, "frasl": 0x2044, "euro": 0x20AC,
        "trade": 0x2122,
    ]
}
