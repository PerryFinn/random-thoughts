// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "RandomThoughtsIsolation",
    platforms: [.macOS("26.5")],
    products: [
        .library(name: "random_thoughts", targets: ["random_thoughts"]),
        .executable(name: "ReportStorageProbe", targets: ["ReportStorageProbe"]),
        .executable(name: "SyntheticCodexServer", targets: ["SyntheticCodexServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", exact: "3.10.0")
    ],
    targets: [
        .systemLibrary(name: "ReportTokenizerC", path: "Tokenizer/include"),
        .target(
            name: "random_thoughts",
            dependencies: ["ReportTokenizerC", .product(name: "CocoaLumberjack", package: "CocoaLumberjack")],
            path: "random-thoughts",
            exclude: [
                "App", "Assets.xcassets", "Models/ProximityModels.swift",
                "Services/ProximityBluetoothController.swift", "Services/ProximityPresenceDetector.swift",
                "Services/ProximitySystemController.swift", "Stores/ProximityLockStore.swift",
                "Stores/ProximityDevicePickerState.swift", "Support/AppleDeviceNames.swift",
                "Support/AppLifecycleDelegate.swift", "Support/ProximityDeviceNameResolver.swift",
                "Support/ProximityDevicePickerFocusBridge.swift", "Support/AppWindowCoordinator.swift",
                "Support/SystemBridge.c", "Support/SystemBridge.h",
                "Views/IQHistoryChart.swift", "Views/IntelligenceDetailView.swift", "Views/MenuBarPanel.swift",
                "Views/ProximityDevicePickerSheet.swift", "Views/ProximitySettingsView.swift"
            ],
            sources: [
                "Models/AppWindowModels.swift", "Models/DailyReportModels.swift", "Stores/DailyReportFlow.swift",
                "Models/DailyReportGeneralSettings.swift",
                "Models/AIServiceConfiguration.swift", "Stores/AIServiceStore.swift",
                "Services/AIServiceCredentialCipher.swift",
                "Models/AIServiceValidation.swift",
                "Services/ChatCompletionsStream.swift", "Models/AIRequest.swift", "Services/AIHTTPTransport.swift", "Services/ChatCompletionsAdapter.swift",
                "Services/ResponsesAdapter.swift", "Services/ResponsesStream.swift", "Services/ServerSentEvents.swift", "Services/AIJSONValue.swift",
                "Services/AIServiceClient.swift",
                "Services/MessagesAdapter.swift", "Services/MessagesStream.swift",
                "Models/ReportPayload.swift",
                "Services/OfflineReportTokenizer.swift",
                "Views/DailyReportGenerationStatusView.swift", "Models/ReportGeneration.swift", "Services/ReportInputPlanner.swift", "Stores/ReportGenerationStore.swift",
                "Views/DailyReportAIServiceView.swift", "Views/AIServiceDefaultsEditor.swift",
                "Models/CodexDataSource.swift", "Stores/CodexDataSourceStore.swift",
                "Models/CodexSessionScan.swift", "Stores/CodexSessionStore.swift",
                "Services/CodexDataSourceReader.swift",
                "Services/CodexStdioSession.swift", "Services/CodexSessionContent.swift",
                "Services/CodexScanOperation.swift",
                "Services/CodexScanLock.swift",
                "Services/CredentialRedaction.swift",
                "Services/DailyReportDatabase.swift",
                "Models/MarkdownDiff.swift", "Models/SafeMarkdown.swift",
                "Views/ReportConfirmationView.swift",
                "Views/DailyReportGeneralSettingsView.swift",
                "Views/DailyReportCodexSourceView.swift",
                "Views/DailyReportSourcesView.swift",
                "Models/AppWindowConfiguration.swift", "Views/DailyReportView.swift", "Views/SettingsView.swift",
                "Views/IntelligenceSettingsView.swift",
                "Support/DailyReportTelemetry.swift",
                "Support/AppLaunchReasonDetector.swift",
                "Support/AppMenuCommands.swift",
                "Models/IntelligencePoint.swift", "Services/IntelligenceService.swift",
                "Stores/IntelligenceStore.swift", "Support/AppTelemetry.swift", "Views/IntelligenceCard.swift"
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "ReportStorageProbe", dependencies: ["random_thoughts"], path: "StorageProbe"),
        .executableTarget(name: "SyntheticCodexServer", path: "CodexProbe", exclude: ["README.md"]),
        .testTarget(
            name: "IsolatedTests",
            dependencies: ["random_thoughts", "ReportTokenizerC", .product(name: "CocoaLumberjack", package: "CocoaLumberjack")],
            path: "IsolatedTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
