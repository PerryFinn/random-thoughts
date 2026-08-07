//
//  my_first_macos_appTests.swift
//  my-first-macos-appTests
//
//  Created by 陈鹏飞 on 2026/7/26.
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import my_first_macos_app

struct my_first_macos_appTests {

    @Test @MainActor func decodesCodexRadarPoint() throws {
        let response = try JSONDecoder().decode(IntelligenceResponse.self, from: Self.sampleResponseData)
        let point = try #require(response.points.first)

        #expect(point.id == "gpt-5.6-sol|max")
        #expect(point.cardTitle == "Sol max")
        #expect(point.groupTitle == "GPT Sol")
        #expect(point.iq == 105.8036)
        #expect(point.averagePriceUSD == 8.980278)
        #expect(point.averageMinutes == 32.8176)
        #expect(point.runs24h == 33)
    }

    @Test @MainActor func menuBarPanelReservesRoomForSelectedCard() throws {
        let suiteName = "com.perryfinn.my-first-macos-app.layout-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Self.sampleResponseData, forKey: "cachedIntelligenceResponse")

        let store = IntelligenceStore(defaults: defaults)
        let hostingView = NSHostingView(rootView: MenuBarPanel(store: store))
        let fittingSize = hostingView.fittingSize

        #expect(store.selectedPoints.count == 1)
        #expect(fittingSize.width == 568)
        #expect(fittingSize.height > 170)
    }

    @Test @MainActor func limitsTrackedPointsToConfiguredMaximum() throws {
        let suiteName = "com.perryfinn.my-first-macos-app.selection-limit-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let points = (0..<10).map { index in
            IntelligencePoint(
                model: "gpt-5.6-sol",
                effort: "level-\(index)",
                iq: Double(index),
                averagePriceUSD: nil,
                averageMinutes: nil,
                runs24h: nil,
                latestGradedAt: nil
            )
        }
        let response = IntelligenceResponse(sourceUpdatedAt: nil, points: points)
        defaults.set(try JSONEncoder().encode(response), forKey: "cachedIntelligenceResponse")

        let store = IntelligenceStore(defaults: defaults)
        store.selectAll()

        #expect(store.selectedPoints.count == IntelligenceStore.selectionLimit)
        #expect(store.hasReachedSelectionLimit)

        let blockedPoint = points[IntelligenceStore.selectionLimit]
        store.setSelected(true, point: blockedPoint)
        #expect(!store.isSelected(blockedPoint))

        let firstPoint = points[0]
        store.setSelected(false, point: firstPoint)
        store.setSelected(true, point: blockedPoint)

        #expect(store.isSelected(blockedPoint))
        #expect(store.selectedPoints.count == IntelligenceStore.selectionLimit)
    }

    @Test @MainActor func formatsSettingsSourceDateAsYearDayMonth() throws {
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-08-09T13:04:00+08:00")
        )
        let timeZone = try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))

        #expect(
            SettingsView.formatSourceUpdatedAt(date, timeZone: timeZone)
                == "2026-09-08 13:04"
        )
    }

    @Test @MainActor func settingsPresenterMakesTitledWindowKey() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings Presenter Test"
        defer { window.close() }

        SettingsWindowPresenter.bringToFront()
        try? await Task.sleep(for: .milliseconds(250))

        #expect(window.isVisible)
        #expect(window.isKeyWindow)
    }

    private static let sampleResponseData = Data(
        """
        {
          "source_updated_at": "2026-08-07T18:52:55+08:00",
          "points": [
            {
              "model": "gpt-5.6-sol",
              "effort": "max",
              "iq": 105.8036,
              "average_price_usd": 8.980278,
              "average_minutes": 32.8176,
              "runs_24h": 33,
              "latest_graded_at": "2026-08-07T10:34:41+00:00"
            }
          ]
        }
        """.utf8
    )
}
