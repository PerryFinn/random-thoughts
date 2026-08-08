//
//  RandomThoughtsTests.swift
//  random-thoughtsTests
//
//  Created by 陈鹏飞 on 2026/7/26.
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import random_thoughts

struct RandomThoughtsTests {

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
        #expect(point.validTasks == 112)
        #expect(point.priceSamples == 104)
        #expect(point.durationSamples == 112)
        #expect(point.incompleteCostSamples == 2)
        #expect(response.history?.count == 1)
    }

    @Test @MainActor func derivesTrendComparisonAndConfidenceWarning() throws {
        let suiteName = "com.perryfinn.random-thoughts.metric-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Self.sampleResponseData, forKey: "cachedIntelligenceResponse")

        let store = IntelligenceStore(defaults: defaults)
        let maxPoint = try #require(
            store.points.first { $0.model == "gpt-5.6-sol" && $0.effort == "max" }
        )

        let comparison = try #require(store.comparisonWithNextLowerEffort(for: maxPoint))
        let iqChange = try #require(store.iqChange24Hours(for: maxPoint))
        #expect(abs(iqChange - 2.5) < 0.0001)
        #expect(comparison.baselineEffort == "high")
        #expect(abs(comparison.iqDelta - 15.8036) < 0.0001)
        #expect(abs((comparison.priceDeltaUSD ?? 0) - 4.980278) < 0.0001)
        #expect(abs((comparison.minutesDelta ?? 0) - 12.8176) < 0.0001)
        #expect(store.confidenceWarning(for: maxPoint) == .incompleteCost(2))
    }

    @Test @MainActor func flagsLowSampleBeforeIncompleteCost() throws {
        let suiteName = "com.perryfinn.random-thoughts.warning-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let point = IntelligencePoint(
            model: "gpt-5.6-terra",
            effort: "medium",
            iq: 72,
            averagePriceUSD: 1.2,
            averageMinutes: 14,
            runs24h: nil,
            latestGradedAt: nil,
            validTasks: 18,
            priceSamples: 16,
            durationSamples: 17,
            incompleteCostSamples: 2
        )
        let store = IntelligenceStore(defaults: defaults)

        #expect(store.confidenceWarning(for: point) == .lowSample(16))
    }

    @Test @MainActor func menuBarPanelReservesRoomForSelectedCard() throws {
        let suiteName = "com.perryfinn.random-thoughts.layout-tests"
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

    @Test @MainActor func metricCardKeepsCompactHeightWithTrendAndWarning() throws {
        let suiteName = "com.perryfinn.random-thoughts.card-layout-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Self.sampleResponseData, forKey: "cachedIntelligenceResponse")

        let store = IntelligenceStore(defaults: defaults)
        let point = try #require(store.selectedPoints.first)
        let card = IntelligenceCard(
            point: point,
            iqChange24Hours: store.iqChange24Hours(for: point),
            comparison: store.comparisonWithNextLowerEffort(for: point),
            confidenceWarning: store.confidenceWarning(for: point)
        )
        .frame(width: 260)
        let hostingView = NSHostingView(rootView: card)

        #expect(hostingView.fittingSize.height == IntelligenceCard.minimumHeight)
    }

    @Test @MainActor func limitsTrackedPointsToConfiguredMaximum() throws {
        let suiteName = "com.perryfinn.random-thoughts.selection-limit-tests"
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
              "valid_tasks": 112,
              "average_price_usd": 8.980278,
              "price_samples": 104,
              "average_minutes": 32.8176,
              "duration_samples": 112,
              "incomplete_cost_samples": 2,
              "runs_24h": 33,
              "latest_graded_at": "2026-08-07T10:34:41+00:00"
            },
            {
              "model": "gpt-5.6-sol",
              "effort": "high",
              "iq": 90.0,
              "valid_tasks": 112,
              "average_price_usd": 4.0,
              "price_samples": 112,
              "average_minutes": 20.0,
              "duration_samples": 112,
              "incomplete_cost_samples": 0,
              "runs_24h": 20,
              "latest_graded_at": "2026-08-07T10:34:41+00:00"
            }
          ],
          "history": [
            {
              "at": "2026-08-06T18:52:55+08:00",
              "points": [
                {
                  "model": "gpt-5.6-sol",
                  "effort": "max",
                  "iq": 103.3036
                }
              ]
            }
          ]
        }
        """.utf8
    )
}
