import SwiftUI
import WidgetKit

// Entry point for the Widget Extension target. Declares every
// widget the extension publishes — currently just the race-timer
// Live Activity.
//
// This file lives in the HyroxappWidget/ folder which becomes
// the Widget Extension target. Add file to widget target
// membership when creating the target via Xcode UI; do NOT add
// it to the main app target (it'd duplicate @main entry points
// and fail to link).
//
// Adding more widgets later (home-screen widgets, control-
// center toggles): just append them to the WidgetBundle's body.
@main
struct HyroxappWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaceLiveActivity()
    }
}
