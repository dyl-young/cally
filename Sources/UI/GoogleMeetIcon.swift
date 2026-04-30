import SwiftUI

/// Renders the Google Meet icon from the bundled vector asset (Resources/Assets.xcassets/GoogleMeet).
struct GoogleMeetIcon: View {
    var size: CGFloat = 16

    var body: some View {
        Image("GoogleMeet")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Google Meet")
    }
}

#Preview {
    HStack(spacing: 12) {
        GoogleMeetIcon(size: 12)
        GoogleMeetIcon(size: 16)
        GoogleMeetIcon(size: 24)
        GoogleMeetIcon(size: 48)
    }
    .padding()
}
