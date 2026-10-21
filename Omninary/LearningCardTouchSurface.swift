import SwiftUI
import UIKit

/// Observes a card touch without taking the scroll view's pan gesture away.
struct LearningCardTouchSurface: UIViewRepresentable {
    let isEditing: Bool
    let onOpen: () -> Void
    let onBeginEditing: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(surface: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.surface = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var surface: LearningCardTouchSurface
        private weak var activePress: UILongPressGestureRecognizer?
        private var startPoint: CGPoint?
        private var startTime: Date?
        private var movedBeforeHold = false
        private var enteredEditing = false
        private var movedCard = false
        private var holdWorkItem: DispatchWorkItem?

        init(surface: LearningCardTouchSurface) {
            self.surface = surface
        }

        @objc func handlePress(_ press: UILongPressGestureRecognizer) {
            switch press.state {
            case .began:
                activePress = press
                startPoint = press.location(in: nil)
                startTime = Date()
                movedBeforeHold = false
                enteredEditing = false
                movedCard = false
                if !surface.isEditing { scheduleHold() }
            case .changed:
                guard let startPoint else { return }
                let point = press.location(in: nil)
                let translation = CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y)
                let distance = hypot(translation.width, translation.height)
                if surface.isEditing || enteredEditing {
                    if distance >= 2 {
                        movedCard = true
                        surface.onDragChanged(translation)
                    }
                } else if distance > 12 {
                    movedBeforeHold = true
                    holdWorkItem?.cancel()
                }
            case .ended:
                holdWorkItem?.cancel()
                let duration = Date().timeIntervalSince(startTime ?? Date())
                if movedCard {
                    surface.onDragEnded()
                } else if !surface.isEditing && !enteredEditing && !movedBeforeHold {
                    if duration >= 0.8 {
                        surface.onBeginEditing()
                    } else {
                        surface.onOpen()
                    }
                }
                resetTouch()
            case .cancelled, .failed:
                holdWorkItem?.cancel()
                if movedCard { surface.onDragEnded() }
                resetTouch()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            !surface.isEditing && !enteredEditing
        }

        private func scheduleHold() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      let activePress = self.activePress,
                      activePress.state == .began || activePress.state == .changed,
                      !self.movedBeforeHold,
                      !self.enteredEditing else { return }
                self.enteredEditing = true
                self.surface.onBeginEditing()
            }
            holdWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        }

        private func resetTouch() {
            activePress = nil
            startPoint = nil
            startTime = nil
            holdWorkItem = nil
            movedBeforeHold = false
            enteredEditing = false
            movedCard = false
        }
    }
}
