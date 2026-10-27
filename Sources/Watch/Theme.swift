import SwiftUI
import UIKit

/// Palette taken from the iPhone Welcome App screens (dark navy background,
/// slate rows, blue-grey labels), so the watch feels like the same app.
enum Theme {
    static let background = Color(red: 0.12, green: 0.14, blue: 0.21)   // #1F2436
    static let header     = Color(red: 0.10, green: 0.12, blue: 0.18)   // #1A1F2E
    static let row        = Color(red: 0.20, green: 0.27, blue: 0.36)   // #33445C
    static let rowText    = Color(red: 0.66, green: 0.75, blue: 0.87)   // #A9C0DE
    static let sectionText = Color(red: 0.56, green: 0.63, blue: 0.74)  // #8FA0BD
    static let accent     = Color(red: 0.27, green: 0.53, blue: 0.95)
    static let success    = Color(red: 0.24, green: 0.78, blue: 0.45)
    static let failure    = Color(red: 0.92, green: 0.33, blue: 0.31)
}

/// "Relè" / "Posto esterno" section header, as in the iPhone app.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(Theme.sectionText)
            .textCase(nil)
    }
}

/// The square on the left of each relay row. Empty at rest (like the iPhone
/// app); fills to show progress / result of the last activation.
struct RelayStateBox: View {
    let state: WatchStore.ActivationState

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Theme.rowText, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
            .frame(width: 20, height: 20)
            .overlay { glyph }
    }

    private var fill: Color {
        switch state {
        case .success: return Theme.success
        case .failure: return Theme.failure
        default: return .clear
        }
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .working:
            ProgressView().scaleEffect(0.5).tint(Theme.rowText)
        case .success:
            Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
        case .failure:
            Image(systemName: "exclamationmark").font(.caption2.bold()).foregroundStyle(.white)
        case .idle:
            EmptyView()
        }
    }
}

/// Camera picture of an outdoor station, or the dark door-panel placeholder
/// the iPhone app shows when no picture is available.
struct StationPicture: View {
    let data: Data?

    var body: some View {
        ZStack {
            Theme.header
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Theme.row.opacity(0.6), lineWidth: 6)
                    .frame(width: 34, height: 64)
            }
        }
        .clipped()
    }
}
