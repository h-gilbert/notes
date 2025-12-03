import SwiftUI
import UIKit

// MARK: - Clear Background for FullScreenCover

struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct ClearBackgroundViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ClearBackgroundView())
    }
}

extension View {
    func clearModalBackground() -> some View {
        modifier(ClearBackgroundViewModifier())
    }

    /// Applies conditional modifiers to a view
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Applies a modifier only on iOS 17+
    @ViewBuilder
    func iOS17Only<Transform: View>(_ transform: (Self) -> Transform) -> some View {
        if #available(iOS 17, *) {
            transform(self)
        } else {
            self
        }
    }

    /// Hides the view conditionally
    @ViewBuilder
    func hidden(_ isHidden: Bool) -> some View {
        if isHidden {
            self.hidden()
        } else {
            self
        }
    }
}

// MARK: - Haptic Feedback

extension View {
    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func hapticNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    func hapticSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
