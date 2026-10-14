import AgentPulseCore
import Foundation

/// Новости UI/UX-дизайна **[решение]**: раз в 3 часа читает публичные ленты.
/// Запросы — обычные GET без данных пользователя; что показано, хранится только локально.
@MainActor
final class NewsSense: Sense {
    let id = SenseID.news
    static let interval: TimeInterval = 3 * 3600
    static let firstFetchDelay: TimeInterval = 20

    private let deliver: @MainActor ([NewsItem]) -> Void
    private var timer: Timer?
    private var task: Task<Void, Never>?

    init(deliver: @escaping @MainActor ([NewsItem]) -> Void) {
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
        task = Task { [weak self] in
            let items = await Self.load()
            guard !Task.isCancelled, !items.isEmpty else { return }
            self?.deliver(items)
        }
    }

    nonisolated static func load() async -> [NewsItem] {
        await withTaskGroup(of: [NewsItem].self) { group in
            for feed in DesignFeeds.all {
                group.addTask {
                    var request = URLRequest(url: feed.url, timeoutInterval: 15)
                    request.setValue("Pulse/1.0 (macOS; design news)", forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return DesignFeeds.filter(FeedParser.parse(data, source: feed.name), feed: feed)
                }
            }
            var all: [NewsItem] = []
            for await items in group { all += items }
            return all
        }
    }
}
