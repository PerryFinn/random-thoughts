import AppKit
import Testing
@testable import random_thoughts

struct ProximityDevicePickerFocusTests {
    @Test @MainActor func commandFFocusesSearchAndConsumesTheEvent() throws {
        var focusRequestCount = 0
        let focusView = ProximityDevicePickerFocusView {
            focusRequestCount += 1
        }
        let commandF = try #require(keyEvent(characters: "f", modifiers: .command))

        let forwardedEvent = focusView.handleKeyDown(commandF)

        #expect(forwardedEvent == nil)
        #expect(focusRequestCount == 1)
    }

    @Test @MainActor func otherKeyCombinationsRemainUnhandled() throws {
        var focusRequestCount = 0
        let focusView = ProximityDevicePickerFocusView {
            focusRequestCount += 1
        }
        let commandShiftF = try #require(
            keyEvent(characters: "f", modifiers: [.command, .shift])
        )

        let forwardedEvent = focusView.handleKeyDown(commandShiftF)

        #expect(forwardedEvent === commandShiftF)
        #expect(focusRequestCount == 0)
    }
}

@MainActor
private func keyEvent(
    characters: String,
    modifiers: NSEvent.ModifierFlags
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: 3
    )
}
