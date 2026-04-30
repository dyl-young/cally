import SwiftUI

/// Approximation of the Google Meet icon — a green rounded square with a stylised camera/play
/// glyph. Drawn in SwiftUI to avoid bundling a Google brand asset. Replace with the real PNG by
/// adding a "GoogleMeet" image set to Assets.xcassets and using `Image("GoogleMeet")` instead.
struct GoogleMeetIcon: View {
    var size: CGFloat = 16

    private let meetGreen = Color(red: 0.0, green: 0.51, blue: 0.32)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(meetGreen)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(.white)
                    .frame(width: size * 0.46, height: size * 0.46)

                MeetTail()
                    .fill(.white)
                    .frame(width: size * 0.18, height: size * 0.46)
                    .offset(x: -size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Google Meet")
    }
}

private struct MeetTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.2))
        p.closeSubpath()
        return p
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
