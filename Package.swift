// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPulse",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentPulse", targets: ["AgentPulse"]),
        .executable(name: "pulse-hook", targets: ["pulse-hook"]),
    ],
    dependencies: [
        // Облик Agent Pals: Lottie на движке Core Animation — анимации крутит рендер-сервер, без кадров на CPU.
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.0"),
    ],
    targets: [
        // Ядро: модель событий, адаптеры, стейт-машина, реплики, настройки. Ничего не знает про UI.
        .target(name: "AgentPulseCore"),
        // Menu bar приложение: оверлей, маскот, облачко, уведомления, MascotLab.
        .executableTarget(
            name: "AgentPulse",
            dependencies: ["AgentPulseCore", .product(name: "Lottie", package: "lottie-spm")]
        ),
        // Хук Claude Code: stdin → unix-сокет. Только Darwin, без Foundation — быстрый старт.
        .executableTarget(name: "pulse-hook"),
        .testTarget(name: "AgentPulseCoreTests", dependencies: ["AgentPulseCore"]),
    ]
)
