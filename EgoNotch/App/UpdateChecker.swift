import AppKit
import Observation

/// Sparkle-free update check against a user-configured GitHub repo's latest
/// release. Entirely optional: with no repo set the button never appears and
/// the app makes no network calls.
@Observable
final class UpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    private(set) var status: Status = .idle

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
    }

    func check(repo: String) {
        let trimmed = repo.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(trimmed)/releases/latest")
        else {
            status = .failed
            return
        }
        status = .checking
        Task { [weak self] in
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
            }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: data),
                  let releaseURL = URL(string: release.html_url) else {
                self?.status = .failed
                return
            }
            let latest = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst()) : release.tag_name
            if Self.isNewer(latest, than: Self.currentVersion) {
                self?.status = .available(version: latest, url: releaseURL)
            } else {
                self?.status = .upToDate
            }
        }
    }

    /// Component-wise numeric comparison; non-numeric tags ("latest",
    /// "1.0-beta") never count as updates.
    private static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int]? {
            let comps = s.split(separator: ".")
            guard !comps.isEmpty else { return nil }
            var out: [Int] = []
            for c in comps {
                guard let n = Int(c) else { return nil }
                out.append(n)
            }
            return out
        }
        guard let l = parts(latest), let c = parts(current) else { return false }
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    func openRelease() {
        if case .available(_, let url) = status {
            NSWorkspace.shared.open(url)
        }
    }
}
