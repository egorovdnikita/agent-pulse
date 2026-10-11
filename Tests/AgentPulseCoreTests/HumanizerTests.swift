import Testing
@testable import AgentPulseCore

@Suite struct HumanizerTests {
    @Test func codeTools() {
        #expect(Humanizer.describe(tool: "Edit", input: ["file_path": "/a/b/View.swift"]) == HumanizedTool(kind: .edit, target: .code, text: "Правит View.swift"))
        #expect(Humanizer.describe(tool: "Write", input: ["file_path": "/a/README.md"]).text == "Пишет README.md")
        #expect(Humanizer.describe(tool: "Grep", input: ["pattern": "TODO"]).text == "Ищет «TODO»")
        #expect(Humanizer.classify(tool: "Glob").kind == .read)
        #expect(Humanizer.classify(tool: "WebSearch").kind == .search)
        #expect(Humanizer.classify(tool: "Task").kind == .search)
        #expect(Humanizer.describe(tool: "WebFetch", input: ["url": "https://developer.apple.com/docs"]).text == "Читает developer.apple.com")
    }

    @Test func bashRules() {
        func text(_ command: String, _ description: String? = nil) -> String {
            var input: [String: Any] = ["command": command]
            if let description { input["description"] = description }
            return Humanizer.describe(tool: "Bash", input: input).text
        }
        #expect(text("npm test") == "Запускает тесты")
        #expect(text("git commit -m 'add tests'") == "Делает коммит")
        #expect(text("swift build -c release") == "Собирает проект")
        #expect(text("ls -la", "List files") == "List files")
        #expect(text("ls -la") == "Выполняет команду")
        #expect(Humanizer.classify(tool: "Bash").kind == .run)
    }

    @Test func figmaIsRecognizedByToolNameEvenWithOpaqueServer() {
        let server = "mcp__8ece76e0-4474-4af1-aeee-e1b5e92835c3__"
        #expect(Humanizer.classify(tool: server + "use_figma") == HumanizedTool(kind: .edit, target: .figma, text: "Рисует в Figma"))
        #expect(Humanizer.classify(tool: server + "get_design_context") == HumanizedTool(kind: .read, target: .figma, text: "Читает макет"))
        #expect(Humanizer.classify(tool: server + "get_variable_defs").text == "Читает переменные")
        #expect(Humanizer.classify(tool: "mcp__figma__some_new_writer").target == .figma)
        #expect(Humanizer.classify(tool: "mcp__figma__get_whatever").kind == .read)
    }

    @Test func otherMCPAndUnknownTools() {
        #expect(Humanizer.classify(tool: "mcp__notion__search_pages") == HumanizedTool(kind: .read, target: .code, text: "Работает с notion"))
        #expect(Humanizer.classify(tool: "mcp__slack__post_message").kind == .other)
        #expect(Humanizer.classify(tool: "Teleport").kind == .other)
    }

    @Test func aggregatorCollapsesReadStreaks() {
        var aggregator = Aggregator()
        #expect(aggregator.text(for: .read, target: .code, original: "Читает a") == "Читает a")
        #expect(aggregator.text(for: .read, target: .code, original: "Читает b") == "Читает b")
        #expect(aggregator.text(for: .read, target: .code, original: "Читает c") == "Изучает проект")
        #expect(aggregator.text(for: .edit, target: .code, original: "Правит c") == "Правит c")
        #expect(aggregator.text(for: .read, target: .code, original: "Читает d") == "Читает d")
    }
}
