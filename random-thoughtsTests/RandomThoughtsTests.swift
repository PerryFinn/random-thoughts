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

    @Test func recommendsModelsForDifferentGoals() throws {
        let points = [
            Self.point(model: "balanced", iq: 90, price: 3, minutes: 10),
            Self.point(model: "genius", iq: 100, price: 10, minutes: 30),
            Self.point(model: "budget", iq: 70, price: 1, minutes: 20),
            Self.point(model: "sprinter", iq: 75, price: 4, minutes: 2)
        ]

        #expect(ModelRecommender.recommend(from: points, strategy: .sweetSpot)?.point.model == "balanced")
        #expect(ModelRecommender.recommend(from: points, strategy: .smartest)?.point.model == "genius")
        #expect(ModelRecommender.recommend(from: points, strategy: .cheapest)?.point.model == "budget")
        #expect(ModelRecommender.recommend(from: points, strategy: .fastest)?.point.model == "sprinter")
    }

    @Test func recommendationSkipsMissingMetricsAndFallsBackToIQ() throws {
        let incomplete = Self.point(model: "incomplete", iq: 120, price: nil, minutes: nil)
        let complete = Self.point(model: "complete", iq: 80, price: 2, minutes: 8)

        #expect(
            ModelRecommender.recommend(
                from: [incomplete, complete],
                strategy: .cheapest
            )?.point.model == "complete"
        )
        #expect(
            ModelRecommender.recommend(
                from: [incomplete],
                strategy: .sweetSpot
            )?.point.model == "incomplete"
        )
        #expect(ModelRecommender.recommend(from: [], strategy: .smartest) == nil)
    }

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
        #expect(response.history?.count == 2)
    }

    private static func point(
        model: String,
        iq: Double,
        price: Double?,
        minutes: Double?
    ) -> IntelligencePoint {
        IntelligencePoint(
            model: model,
            effort: "medium",
            iq: iq,
            averagePriceUSD: price,
            averageMinutes: minutes,
            runs24h: nil,
            latestGradedAt: nil
        )
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

    @Test @MainActor func flagsLowMetricCoverage() throws {
        let suiteName = "com.perryfinn.random-thoughts.coverage-warning-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let point = IntelligencePoint(
            model: "gpt-5.6-terra",
            effort: "ultra",
            iq: 92.4,
            averagePriceUSD: 10.02,
            averageMinutes: 43.7,
            runs24h: 15,
            latestGradedAt: nil,
            validTasks: 112,
            priceSamples: 74,
            durationSamples: 112,
            incompleteCostSamples: 0
        )
        let store = IntelligenceStore(defaults: defaults)

        #expect(
            store.confidenceWarning(for: point)
                == .lowCoverage(metric: "成本数据", available: 74, total: 112)
        )
    }

    @Test @MainActor func formatsLatestDetailUpdateAsRelativeTime() throws {
        let referenceDate = try #require(
            ISO8601DateFormatter().date(from: "2026-08-08T07:00:00Z")
        )
        let sourceUpdatedAt = try #require(
            ISO8601DateFormatter().date(from: "2026-08-08T06:59:00Z")
        )

        #expect(
            IntelligenceDetailView.formatLatestUpdate(
                latestGradedAt: "2026-08-08T06:48:00Z",
                sourceUpdatedAt: sourceUpdatedAt,
                relativeTo: referenceDate
            ) == "最近更新于 12 分钟前"
        )
    }

    @Test @MainActor func buildsSortedIQHistoryIncludingCurrentPoint() throws {
        let suiteName = "com.perryfinn.random-thoughts.iq-history-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Self.sampleResponseData, forKey: "cachedIntelligenceResponse")

        let store = IntelligenceStore(defaults: defaults)
        let point = try #require(
            store.points.first { $0.model == "gpt-5.6-sol" && $0.effort == "max" }
        )
        let samples = store.iqHistory(for: point)

        #expect(samples.map(\.iq) == [101.7, 103.3036, 105.8036])
        #expect(samples[0].at < samples[1].at)
        #expect(samples[1].at < samples[2].at)
        #expect(samples.last?.at == store.sourceUpdatedAt)
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

    @Test @MainActor func modelDetailOccupiesFullMenuBarPanel() throws {
        let suiteName = "com.perryfinn.random-thoughts.detail-layout-tests"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Self.sampleResponseData, forKey: "cachedIntelligenceResponse")

        let store = IntelligenceStore(defaults: defaults)
        let point = try #require(store.selectedPoints.first)
        let hostingView = NSHostingView(
            rootView: MenuBarPanel(store: store, selectedPointID: point.id)
        )

        #expect(hostingView.fittingSize.width == MenuBarPanel.panelWidth)
        #expect(hostingView.fittingSize.height == IntelligenceDetailView.panelHeight)
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
            },
            {
              "at": "2026-08-05T18:52:55+08:00",
              "points": [
                {
                  "model": "gpt-5.6-sol",
                  "effort": "max",
                  "iq": 101.7
                }
              ]
            }
          ]
        }
        """.utf8
    )
}
