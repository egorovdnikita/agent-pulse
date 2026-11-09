import Foundation
import Testing
@testable import AgentPulseCore

struct ControlTapTests {
    @Test func singleTap() {
        var tap = ControlTap()
        let result1 = tap.observe(control: true, otherModifier: false, activity: 10, time: 0)
        #expect(!result1)
        let result2 = tap.observe(control: false, otherModifier: false, activity: 10, time: 0.15)
        #expect(result2)
        let result3 = tap.observe(control: false, otherModifier: false, activity: 10, time: 0.16)
        #expect(!result3)
    }
    @Test func typingAndSelectionDoNotTrigger() {
        for changed in [UInt64(1), 2, 3] {
            var tap = ControlTap()
            _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 0)
            let result4 = tap.observe(control: false, otherModifier: false, activity: changed, time: 0.2)
            #expect(!result4)
        }
    }
    @Test func modifierChordDoesNotTrigger() {
        var tap = ControlTap()
        _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 0)
        _ = tap.observe(control: true, otherModifier: true, activity: 0, time: 0.1)
        _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 0.15)
        let result5 = tap.observe(control: false, otherModifier: false, activity: 0, time: 0.2)
        #expect(!result5)
    }
    @Test func heldControlAndOrphanReleaseDoNotTrigger() {
        var tap = ControlTap()
        let result6 = tap.observe(control: false, otherModifier: false, activity: 0, time: 0)
        #expect(!result6)
        _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 1)
        let result7 = tap.observe(control: false, otherModifier: false, activity: 0, time: 2)
        #expect(!result7)
    }
    @Test func existingChordAndRepeatedFlagsDoNotRearm() {
        var tap = ControlTap()
        _ = tap.observe(control: true, otherModifier: true, activity: 0, time: 0)
        _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 0.1)
        let result8 = tap.observe(control: false, otherModifier: false, activity: 0, time: 0.2)
        #expect(!result8)
        _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 1)
        _ = tap.observe(control: true, otherModifier: false, activity: 0, time: 1.4)
        let result9 = tap.observe(control: false, otherModifier: false, activity: 0, time: 1.5)
        #expect(!result9)
    }
    @Test func retiredShiftMigratesWithoutChangingOtherPreferences() {
        let old = PulseConfig.decode(Data(#"{"console":{"hotkey":"shift","sounds":false}}"#.utf8))
        #expect(old.console.hotkey == "control")
        #expect(!old.console.sounds)
        for hotkey in ["control", "x", "b", ""] {
            let json = "{\"console\":{\"hotkey\":\"" + hotkey + "\"}}"
            #expect(PulseConfig.decode(Data(json.utf8)).console.hotkey == hotkey)
        }
    }

}
