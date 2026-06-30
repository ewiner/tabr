import Foundation
import Combine
import HTMLEntities

struct TabResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let rating: Double
    let votes: Int
    let type: String // "Chords", "Tab", etc.
    let url: URL
    let relevanceScore: Double

    static func == (lhs: TabResult, rhs: TabResult) -> Bool {
        lhs.url == rhs.url
    }
}

struct TabContent: Equatable {
    let title: String
    let artist: String
    let type: String
    let content: String // The actual tab/chord text
    let url: URL
    let tuning: String?
    let capo: Int?
}

@MainActor
class TabSearchService: ObservableObject {
    @Published var results: [TabResult] = []
    @Published var selectedTab: TabContent?
    @Published var isSearching = false
    @Published var isLoadingTab = false
    @Published var lastQuery = ""
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    // Store search components for relevance scoring
    private var searchArtist = ""
    private var searchTitle = ""

    /// Search Ultimate Guitar for tabs matching the query.
    /// When `autoSelect` is true (default for auto/now-playing searches), the best result is loaded immediately.
    /// When false (manual search), results are shown for the user to pick from.
    func search(query: String, artist: String = "", title: String = "", autoSelect: Bool = true) {
        guard !query.isEmpty, query != lastQuery else { return }
        lastQuery = query
        searchArtist = artist
        searchTitle = title

        currentTask?.cancel()
        currentTask = Task {
            self.isSearching = true
            self.errorMessage = nil
            self.results = []
            self.selectedTab = nil

            do {
                let results = try await performSearch(query: query)
                if !Task.isCancelled {
                    self.results = results
                    if autoSelect, let best = results.first {
                        self.loadTab(best)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = "Search failed: \(error.localizedDescription)"
                }
            }

            self.isSearching = false
        }
    }

    /// Load the full tab content from a result
    func loadTab(_ result: TabResult) {
        currentTask = Task {
            self.isLoadingTab = true
            self.errorMessage = nil

            do {
                let content = try await fetchTabContent(result: result)
                if !Task.isCancelled {
                    self.selectedTab = content
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = "Failed to load tab: \(error.localizedDescription)"
                }
            }

            self.isLoadingTab = false
        }
    }

    // MARK: - Relevance Scoring

    /// Normalize a string for fuzzy comparison: lowercase, strip punctuation, collapse whitespace
    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let stripped = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let str = String(stripped)
        return str.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Word overlap score between two strings (0..1)
    private static func wordOverlap(_ a: String, _ b: String) -> Double {
        let wordsA = Set(normalize(a).components(separatedBy: " "))
        let wordsB = Set(normalize(b).components(separatedBy: " "))
        guard !wordsA.isEmpty && !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let smaller = min(wordsA.count, wordsB.count)
        return Double(intersection) / Double(smaller)
    }

    /// Compute relevance of a result against the search artist/title
    private func relevanceScore(resultTitle: String, resultArtist: String) -> Double {
        let normSearchTitle = Self.normalize(searchTitle)
        let normSearchArtist = Self.normalize(searchArtist)
        let normResultTitle = Self.normalize(resultTitle)
        let normResultArtist = Self.normalize(resultArtist)

        // Title score
        var titleScore: Double = 0
        if !normSearchTitle.isEmpty {
            if normResultTitle == normSearchTitle {
                titleScore = 1.0
            } else if normResultTitle.contains(normSearchTitle) || normSearchTitle.contains(normResultTitle) {
                titleScore = 0.8
            } else {
                titleScore = Self.wordOverlap(normSearchTitle, normResultTitle)
            }
        } else {
            titleScore = 0.5 // No search title to compare against
        }

        // Artist score
        var artistScore: Double = 0
        if !normSearchArtist.isEmpty {
            if normResultArtist == normSearchArtist {
                artistScore = 1.0
            } else if normResultArtist.contains(normSearchArtist) || normSearchArtist.contains(normResultArtist) {
                artistScore = 0.8
            } else {
                artistScore = Self.wordOverlap(normSearchArtist, normResultArtist)
            }
        } else {
            artistScore = 0.5
        }

        return 0.5 * titleScore + 0.5 * artistScore
    }

    /// Bayesian weighted rating: balances rating vs vote count
    /// A 4.7 with 1000 votes beats a 4.8 with 20 votes
    private static func weightedRating(rating: Double, votes: Int) -> Double {
        let k: Double = 50 // prior weight
        let avgRating: Double = 3.5 // assumed global average
        let v = Double(votes)
        return (v / (v + k)) * rating + (k / (v + k)) * avgRating
    }

    // MARK: - Networking

    private func performSearch(query: String) async throws -> [TabResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = URL(string: "https://www.ultimate-guitar.com/search.php?search_type=title&value=\(encoded)")!

        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        return parseSearchResults(html: html)
    }

    private func parseSearchResults(html: String) -> [TabResult] {
        // Ultimate Guitar embeds search results as JSON in a data-content attribute
        // within a <div class="js-store"> element
        guard let storeRange = html.range(of: "data-content=\"") else {
            // Fallback: try to find the JSON store data
            return parseSearchResultsFallback(html: html)
        }

        let afterStore = html[storeRange.upperBound...]
        guard let endQuote = afterStore.firstIndex(of: "\"") else {
            return parseSearchResultsFallback(html: html)
        }

        let encodedJSON = String(afterStore[..<endQuote])
        let decodedJSON = encodedJSON.htmlUnescape()

        guard let jsonData = decodedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let store = json["store"] as? [String: Any],
              let page = store["page"] as? [String: Any],
              let data = page["data"] as? [String: Any],
              let results = data["results"] as? [[String: Any]] else {
            return parseSearchResultsFallback(html: html)
        }

        return rankResults(results)
    }

    private func parseSearchResultsFallback(html: String) -> [TabResult] {
        guard let resultsRange = html.range(of: "\"results\":["),
              let startBracket = html.range(of: "[", range: resultsRange.upperBound..<html.endIndex) else {
            return []
        }

        var depth = 1
        var idx = startBracket.upperBound
        while idx < html.endIndex && depth > 0 {
            let ch = html[idx]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1 }
            idx = html.index(after: idx)
        }

        let arrayStr = "[\(html[startBracket.upperBound..<html.index(before: idx)])]"
        let decoded = arrayStr.htmlUnescape()

        guard let data = decoded.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return rankResults(items)
    }

    /// Shared ranking logic: filter types, compute relevance + weighted rating, sort, and cap results
    private func rankResults(_ items: [[String: Any]]) -> [TabResult] {
        let results: [TabResult] = items.compactMap { result -> TabResult? in
            guard let title = result["song_name"] as? String,
                  let artist = result["artist_name"] as? String,
                  let urlString = result["tab_url"] as? String,
                  let url = URL(string: urlString),
                  let type = result["type"] as? String else {
                return nil
            }

            let rating = result["rating"] as? Double ?? 0
            let votes = result["votes"] as? Int ?? 0

            // Only keep Chords and Tabs (standard guitar content)
            guard type == "Chords" || type == "Tab" else {
                return nil
            }

            let relevance = relevanceScore(
                resultTitle: title.htmlUnescape(),
                resultArtist: artist.htmlUnescape()
            )

            return TabResult(
                title: title.htmlUnescape(),
                artist: artist.htmlUnescape(),
                rating: rating,
                votes: votes,
                type: type,
                url: url,
                relevanceScore: relevance
            )
        }

        // Filter out low-relevance results (when we have search terms to compare)
        let hasSearchTerms = !searchArtist.isEmpty || !searchTitle.isEmpty
        let filtered = hasSearchTerms ? results.filter { $0.relevanceScore >= 0.3 } : results

        // Sort: primary by relevance, secondary by weighted rating
        return filtered.sorted { a, b in
            // If relevance differs significantly, sort by relevance
            if abs(a.relevanceScore - b.relevanceScore) > 0.15 {
                return a.relevanceScore > b.relevanceScore
            }
            // Otherwise sort by weighted rating
            return Self.weightedRating(rating: a.rating, votes: a.votes) >
                   Self.weightedRating(rating: b.rating, votes: b.votes)
        }
    }

    func fetchTabContent(result: TabResult) async throws -> TabContent {
        var request = URLRequest(url: result.url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        let (tabText, tuning, capo) = extractTabContent(from: html)

        return TabContent(
            title: result.title,
            artist: result.artist,
            type: result.type,
            content: tabText,
            url: result.url,
            tuning: tuning,
            capo: capo
        )
    }

    private func extractTabContent(from html: String) -> (content: String, tuning: String?, capo: Int?) {
        guard let storeRange = html.range(of: "data-content=\"") else {
            return (extractTabContentFallback(from: html), nil, nil)
        }

        let afterStore = html[storeRange.upperBound...]
        guard let endQuote = afterStore.firstIndex(of: "\"") else {
            return (extractTabContentFallback(from: html), nil, nil)
        }

        let encoded = String(afterStore[..<endQuote])
        let decoded = encoded.htmlUnescape()

        guard let jsonData = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let store = json["store"] as? [String: Any],
              let page = store["page"] as? [String: Any],
              let data = page["data"] as? [String: Any] else {
            return (extractTabContentFallback(from: html), nil, nil)
        }

        // Extract tuning and capo metadata
        var tuning: String? = nil
        var capo: Int? = nil

        if let tabView = data["tab_view"] as? [String: Any],
           let meta = tabView["meta"] as? [String: Any] {
            if let tuningObj = meta["tuning"] as? [String: Any] {
                tuning = tuningObj["value"] as? String ?? tuningObj["name"] as? String
            }
            capo = meta["capo"] as? Int
        }

        if let tabData = data["tab"] as? [String: Any] {
            if tuning == nil {
                if let tuningObj = tabData["tuning"] as? [String: Any] {
                    tuning = tuningObj["value"] as? String ?? tuningObj["name"] as? String
                } else if let tuningStr = tabData["tuning"] as? String {
                    tuning = tuningStr
                }
            }
            if capo == nil {
                capo = tabData["capo"] as? Int
            }
        }

        if let tabView = data["tab_view"] as? [String: Any],
           let wikiTab = tabView["wiki_tab"] as? [String: Any],
           let content = wikiTab["content"] as? String {
            return (cleanTabContent(content), tuning, capo)
        }

        if let tab = data["tab"] as? [String: Any],
           let content = tab["content"] as? String {
            return (cleanTabContent(content), tuning, capo)
        }

        return (extractTabContentFallback(from: html), tuning, capo)
    }

    private func extractTabContentFallback(from html: String) -> String {
        if let preRange = html.range(of: "<pre class=\"") {
            let afterPre = html[preRange.lowerBound...]
            if let contentStart = afterPre.range(of: ">"),
               let contentEnd = afterPre.range(of: "</pre>") {
                let content = String(afterPre[contentStart.upperBound..<contentEnd.lowerBound])
                return cleanTabContent(content)
            }
        }
        return "Could not load tab content. Try opening in browser."
    }

    private func cleanTabContent(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "[tab]", with: "")
            .replacingOccurrences(of: "[/tab]", with: "")
            .replacingOccurrences(of: "[ch]", with: "")
            .replacingOccurrences(of: "[/ch]", with: "")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        text = text.htmlUnescape()
        return text
    }
}
