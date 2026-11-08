// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "RandomThoughtsIsolation",
    platforms: [.macOS("26.5")],
    products: [
        .library(name: "random_thoughts", targets: ["random_thoughts"])
    ],
    targets: [
        .target(
            name: "random_thoughts",
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
                "Models/IntelligencePoint.swift",
                "Services/IntelligenceService.swift",
                "Stores/IntelligenceStore.swift",
                "Support/AppMenuCommands.swift",
                "Support/AppTelemetry.swift",
                "Views/IntelligenceCard.swift",
                "Views/IntelligenceSettingsView.swift",
                "Views/SettingsView.swift"
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "IsolatedTests",
            dependencies: ["random_thoughts"],
            path: "IsolatedTests"
        )
    ]
)
