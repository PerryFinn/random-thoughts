import AppKit
import Foundation
import SwiftUI
import Testing
@testable import random_thoughts

@MainActor
struct IntelligenceLayoutTests {
    @Test func metricCardFitsWithoutCreatingAWindow() throws {
        let response = try JSONDecoder().decode(IntelligenceResponse.self, from: SyntheticTransport.points)
        let point = try #require(response.points.first)
        let hostingView = NSHostingView(rootView: IntelligenceCard(
            point: point,
            iqChange24Hours: 2.5,
            comparison: .init(baselineEffort: "high", iqDelta: 3, priceDeltaUSD: nil, minutesDelta: nil),
            confidenceWarning: .lowSample(10)
        ).frame(width: 260))

        #expect(hostingView.fittingSize == NSSize(width: 260, height: 88))
        #expect(hostingView.window == nil)
    }
}
