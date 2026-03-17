import Foundation
import Combine

struct TabResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let rating: Double
    let votes: Int
    let type: String // "Chords", "Tab", etc.
    let url: URL

    static func == (lhs: TabResult, rhs: TabResult) -> Bool {
        lhs.url == rhs.url
    }
}

struct TabContent: Equatable {
    let title: String
    let artist: String
    let type: String
    let content: String // The actual tab/chord text
}

class TabSearchService: ObservableObject {
    @Published var results: [TabResult] = []
    @Published var selectedTab: TabContent?
    @Published var isSearching = false
    @Published var isLoadingTab = false
    @Published var lastQuery = ""
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    /// Search Ultimate Guitar for tabs matching the query
    func search(query: String) {
        guard !query.isEmpty, query != lastQuery else { return }
        lastQuery = query

        currentTask?.cancel()
        currentTask = Task { @MainActor in
            self.isSearching = true
            self.errorMessage = nil
            self.results = []
            self.selectedTab = nil

            do {
                let results = try await performSearch(query: query)
                if !Task.isCancelled {
                    self.results = results
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
        currentTask?.cancel()
        currentTask = Task { @MainActor in
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
        let decodedJSON = encodedJSON
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        guard let jsonData = decodedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let store = json["store"] as? [String: Any],
              let page = store["page"] as? [String: Any],
              let data = page["data"] as? [String: Any],
              let results = data["results"] as? [[String: Any]] else {
            return parseSearchResultsFallback(html: html)
        }

        return results.compactMap { result -> TabResult? in
            guard let title = result["song_name"] as? String,
                  let artist = result["artist_name"] as? String,
                  let urlString = result["tab_url"] as? String,
                  let url = URL(string: urlString),
                  let type = result["type"] as? String else {
                return nil
            }

            let rating = result["rating"] as? Double ?? 0
            let votes = result["votes"] as? Int ?? 0

            // Prefer chords and standard tabs
            guard type == "Chords" || type == "Tab" || type == "Ukulele" else {
                return nil
            }

            return TabResult(
                title: title,
                artist: artist,
                rating: rating,
                votes: votes,
                type: type,
                url: url
            )
        }
        .sorted { $0.rating > $1.rating }
    }

    private func parseSearchResultsFallback(html: String) -> [TabResult] {
        // Try to extract from js-store JSON blob that sometimes appears differently
        // Look for the pattern: "results":[ ... ]
        guard let resultsRange = html.range(of: "\"results\":["),
              let startBracket = html.range(of: "[", range: resultsRange.upperBound..<html.endIndex) else {
            return []
        }

        // Find matching closing bracket
        var depth = 1
        var idx = startBracket.upperBound
        while idx < html.endIndex && depth > 0 {
            let ch = html[idx]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1 }
            idx = html.index(after: idx)
        }

        let arrayStr = "[\(html[startBracket.upperBound..<html.index(before: idx)])]"
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")

        guard let data = arrayStr.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> TabResult? in
            guard let title = item["song_name"] as? String,
                  let artist = item["artist_name"] as? String,
                  let urlStr = item["tab_url"] as? String,
                  let url = URL(string: urlStr) else { return nil }

            let type = item["type"] as? String ?? "Chords"
            guard type == "Chords" || type == "Tab" || type == "Ukulele" else { return nil }

            return TabResult(
                title: title,
                artist: artist,
                rating: item["rating"] as? Double ?? 0,
                votes: item["votes"] as? Int ?? 0,
                type: type,
                url: url
            )
        }
        .sorted { $0.rating > $1.rating }
    }

    func fetchTabContent(result: TabResult) async throws -> TabContent {
        var request = URLRequest(url: result.url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        // Tab content is also stored in the js-store data-content JSON
        let tabText = extractTabContent(from: html)

        return TabContent(
            title: result.title,
            artist: result.artist,
            type: result.type,
            content: tabText
        )
    }

    private func extractTabContent(from html: String) -> String {
        // UG stores tab content in the data-content JSON as wiki_tab.content
        guard let storeRange = html.range(of: "data-content=\"") else {
            return extractTabContentFallback(from: html)
        }

        let afterStore = html[storeRange.upperBound...]
        guard let endQuote = afterStore.firstIndex(of: "\"") else {
            return extractTabContentFallback(from: html)
        }

        let encoded = String(afterStore[..<endQuote])
        let decoded = encoded
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        guard let jsonData = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let store = json["store"] as? [String: Any],
              let page = store["page"] as? [String: Any],
              let data = page["data"] as? [String: Any] else {
            return extractTabContentFallback(from: html)
        }

        // Try tab_view.wiki_tab.content
        if let tabView = data["tab_view"] as? [String: Any],
           let wikiTab = tabView["wiki_tab"] as? [String: Any],
           let content = wikiTab["content"] as? String {
            return cleanTabContent(content)
        }

        // Try tab.content
        if let tab = data["tab"] as? [String: Any],
           let content = tab["content"] as? String {
            return cleanTabContent(content)
        }

        return extractTabContentFallback(from: html)
    }

    private func extractTabContentFallback(from html: String) -> String {
        // Look for content between common tab content markers
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
        raw.replacingOccurrences(of: "[tab]", with: "")
            .replacingOccurrences(of: "[/tab]", with: "")
            .replacingOccurrences(of: "[ch]", with: "")
            .replacingOccurrences(of: "[/ch]", with: "")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
