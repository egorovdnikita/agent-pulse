import AgentPulseCore
import Foundation

/// Новости **[решение]**: раз в час читает публичные ленты и открытые Telegram-каналы включённых тем.
/// Запросы — обычные GET без данных пользователя; что показано, хранится только локально.
@MainActor
final class NewsSense: Sense {
    let id = SenseID.news
    static let interval: TimeInterval = 3600
    static let firstFetchDelay: TimeInterval = 20

    private let topics: Set<NewsTopic>
    private let deliver: @MainActor ([NewsItem]) -> Void
    private var timer: Timer?
    private var task: Task<Void, Never>?

    init(topics: Set<NewsTopic>, deliver: @escaping @MainActor ([NewsItem]) -> Void) {
        self.topics = topics
        self.deliver = deliver
    }

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstFetchDelay) { [weak self] in
            MainActor.assumeIsolated { self?.fetch() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetch() }
        }
    }

    func stop() {
        timer?.invalidate()
        task?.cancel()
    }

    private func fetch() {
        task?.cancel()
        let topics = topics
        task = Task { [weak self] in
            let items = await Self.load(topics: topics)
            guard !Task.isCancelled, !items.isEmpty else { return }
            self?.deliver(items)
        }
    }

    nonisolated static func load(topics: Set<NewsTopic> = Set(NewsTopic.allCases)) async -> [NewsItem] {
        await withTaskGroup(of: [NewsItem].self) { group in
            for feed in NewsFeeds.all where topics.contains(feed.topic) {
                group.addTask {
                    var request = URLRequest(url: feed.url, timeoutInterval: 15)
                    request.setValue("Mozilla/5.0 (Macintosh) Pulse/1.0", forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return NewsFeeds.filter(NewsFeeds.parse(data, feed: feed), feed: feed)
                }
            }
            var all: [NewsItem] = []
            for await items in group { all += items }
            return all
        }
    }
}
