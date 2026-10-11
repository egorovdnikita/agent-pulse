import Foundation

public struct HumanizedTool: Sendable, Equatable {
    public var kind: ToolKind
    public var target: WorkTarget
    /// Полный текст для уведомления и тултипа. Реплику облачка выбирает `PhrasePicker`.
    public var text: String
}

/// Инструмент + аргументы → человеческая фраза. Таблица правил; каждое правило покрыто тестом.
public enum Humanizer {
    /// Инструменты официального Figma MCP. Имя сервера бывает произвольным (`mcp__<uuid>__use_figma`),
    /// поэтому узнаём Figma и по имени инструмента.
    static let figmaTools: Set<String> = [
        "use_figma", "get_design_context", "get_metadata", "get_screenshot", "get_variable_defs",
        "get_figjam", "create_new_file", "generate_diagram", "generate_image", "upload_assets",
        "download_assets", "get_code_connect_map", "add_code_connect_map", "search_design_system",
        "get_libraries", "html_to_figma",
    ]

    /// Инструменты, которыми агент спрашивает пользователя: это ожидание, а не работа.
    public static let questionTools: [String: String] = [
        "AskUserQuestion": "Агент задаёт вопрос",
        "ExitPlanMode": "Агент ждёт одобрения плана",
    ]

    /// Инструменты MCP-серверов окружения (Cowork, браузер), узнаваемые по имени при любом сервере.
    static func genericMCP(_ tool: String, input: [String: Any]) -> HumanizedTool? {
        switch tool {
        case "bash", "run_command", "execute_command":
            return HumanizedTool(kind: .run, target: .code, text: bash(input))
        case "read_file", "read_file_content", "get_file_metadata", "get_page_text", "read_page":
            return HumanizedTool(kind: .read, target: .code, text: "Читает файл")
        case "search_files", "find", "grep":
            return HumanizedTool(kind: .read, target: .code, text: "Ищет файлы")
        case "write_file", "edit_file", "create_file":
            return HumanizedTool(kind: .edit, target: .code, text: "Пишет файл")
        case "web_fetch", "navigate", "web_search":
            return HumanizedTool(kind: .search, target: .code, text: "Смотрит в сети")
        case "computer":
            return HumanizedTool(kind: .other, target: .code, text: "Управляет компьютером")
        default:
            return nil
        }
    }

    public static func classify(tool: String) -> HumanizedTool {
        describe(tool: tool, input: [:])
    }

    public static func describe(tool: String, input: [String: Any]) -> HumanizedTool {
        if let mcp = splitMCP(tool) {
            if isFigma(server: mcp.server, tool: mcp.tool) {
                return figma(mcp.tool)
            }
            if let generic = genericMCP(mcp.tool, input: input) {
                return generic
            }
            let readLike = ["get_", "list_", "search_", "read_", "fetch_", "query_"].contains { mcp.tool.hasPrefix($0) }
            return HumanizedTool(kind: readLike ? .read : .other, target: .code, text: "Работает с \(mcp.server)")
        }

        switch tool {
        case "Read", "NotebookRead":
            return HumanizedTool(kind: .read, target: .code, text: "Читает \(fileName(input) ?? "файл")")
        case "Grep":
            if let pattern = input["pattern"] as? String, !pattern.isEmpty {
                return HumanizedTool(kind: .read, target: .code, text: "Ищет «\(clip(pattern, 30))»")
            }
            return HumanizedTool(kind: .read, target: .code, text: "Ищет в коде")
        case "Glob", "LS":
            return HumanizedTool(kind: .read, target: .code, text: "Изучает проект")
        case "Edit", "MultiEdit":
            return HumanizedTool(kind: .edit, target: .code, text: "Правит \(fileName(input) ?? "файл")")
        case "Write":
            return HumanizedTool(kind: .edit, target: .code, text: "Пишет \(fileName(input) ?? "файл")")
        case "NotebookEdit":
            return HumanizedTool(kind: .edit, target: .code, text: "Правит \(fileName(input) ?? "ноутбук")")
        case "Bash":
            return HumanizedTool(kind: .run, target: .code, text: bash(input))
        case "BashOutput", "KillShell", "KillBash", "Monitor":
            return HumanizedTool(kind: .run, target: .code, text: "Следит за командой")
        case "WebSearch":
            if let query = input["query"] as? String, !query.isEmpty {
                return HumanizedTool(kind: .search, target: .code, text: "Ищет в сети: \(clip(query, 40))")
            }
            return HumanizedTool(kind: .search, target: .code, text: "Ищет в сети")
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host() }
            return HumanizedTool(kind: .search, target: .code, text: host.map { "Читает \($0)" } ?? "Читает страницу")
        case "Task", "Agent":
            if let description = input["description"] as? String, !description.isEmpty {
                return HumanizedTool(kind: .search, target: .code, text: "Субагент: \(clip(description, 40))")
            }
            return HumanizedTool(kind: .search, target: .code, text: "Запускает субагента")
        case "TodoWrite", "TaskCreate", "TaskUpdate":
            return HumanizedTool(kind: .other, target: .code, text: "Планирует шаги")
        case "ToolSearch":
            return HumanizedTool(kind: .other, target: .code, text: "Подбирает инструменты")
        case "Skill":
            return HumanizedTool(kind: .other, target: .code, text: "Применяет навык")
        default:
            return HumanizedTool(kind: .other, target: .code, text: "Работает: \(tool)")
        }
    }

    // MARK: - Правила

    /// Порядок важен: `git commit -m "add tests"` — это коммит, а не тесты.
    static let bashRules: [(needle: String, text: String)] = [
        ("git commit", "Делает коммит"),
        ("git push", "Отправляет изменения"),
        ("git ", "Работает с git"),
        ("test", "Запускает тесты"),
        ("build", "Собирает проект"),
        ("install", "Ставит зависимости"),
        ("lint", "Проверяет код"),
    ]

    static func bash(_ input: [String: Any]) -> String {
        let command = (input["command"] as? String ?? "").lowercased()
        for rule in bashRules where command.contains(rule.needle) {
            return rule.text
        }
        if let description = input["description"] as? String, !description.isEmpty {
            return clip(description, 40)
        }
        return "Выполняет команду"
    }

    static func figma(_ tool: String) -> HumanizedTool {
        let read: String? = switch tool {
        case "get_design_context": "Читает макет"
        case "get_metadata": "Изучает структуру файла"
        case "get_screenshot": "Смотрит на макет"
        case "get_variable_defs": "Читает переменные"
        case "get_figjam": "Читает доску FigJam"
        case "search_design_system", "get_libraries": "Изучает дизайн-систему"
        default: nil
        }
        if let read {
            return HumanizedTool(kind: .read, target: .figma, text: read)
        }
        if tool.hasPrefix("get_") || tool.hasPrefix("list_") || tool.hasPrefix("search_") {
            return HumanizedTool(kind: .read, target: .figma, text: "Читает Figma")
        }
        let write = switch tool {
        case "use_figma", "html_to_figma": "Рисует в Figma"
        case "create_new_file": "Создаёт файл Figma"
        case "generate_diagram": "Рисует диаграмму"
        case "generate_image": "Генерирует картинку"
        case "upload_assets": "Загружает ассеты"
        default: "Меняет макет"
        }
        return HumanizedTool(kind: .edit, target: .figma, text: write)
    }

    // MARK: - Помощники

    static func splitMCP(_ tool: String) -> (server: String, tool: String)? {
        guard tool.hasPrefix("mcp__") else { return nil }
        let rest = tool.dropFirst("mcp__".count)
        guard let separator = rest.range(of: "__") else { return nil }
        return (String(rest[..<separator.lowerBound]), String(rest[separator.upperBound...]))
    }

    static func isFigma(server: String, tool: String) -> Bool {
        server.localizedCaseInsensitiveContains("figma") || figmaTools.contains(tool)
    }

    static func fileName(_ input: [String: Any]) -> String? {
        for key in ["file_path", "notebook_path", "path"] {
            if let path = input[key] as? String, !path.isEmpty {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return nil
    }

    static func clip(_ string: String, _ limit: Int) -> String {
        let flat = string.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}
