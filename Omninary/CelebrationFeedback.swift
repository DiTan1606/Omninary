import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class CelebrationFeedbackPlayer {
    static let shared = CelebrationFeedbackPlayer()

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private init() {}

    func play() {
        stop()

        if OmniSoundSettings.hapticsEnabled {
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.success)
        }
        guard OmniSoundSettings.effectsEnabled else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)

            let sampleRate = 44_100.0
            let duration = 1.25
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(sampleRate * duration)
                  ),
                  let samples = buffer.floatChannelData?[0] else {
                return
            }

            buffer.frameLength = buffer.frameCapacity
            let notes: [(start: Double, duration: Double, frequency: Double)] = [
                (0.00, 0.28, 523.25),
                (0.18, 0.30, 659.25),
                (0.38, 0.34, 783.99),
                (0.62, 0.58, 1_046.50)
            ]

            for frame in 0..<Int(buffer.frameLength) {
                let time = Double(frame) / sampleRate
                var value = 0.0

                for note in notes {
                    let localTime = time - note.start
                    guard localTime >= 0, localTime <= note.duration else { continue }

                    let progress = localTime / note.duration
                    let attack = min(localTime / 0.025, 1)
                    let release = pow(max(1 - progress, 0), 1.7)
                    let envelope = attack * release
                    let fundamental = sin(2 * .pi * note.frequency * localTime)
                    let harmonic = sin(2 * .pi * note.frequency * 2 * localTime) * 0.18
                    value += (fundamental + harmonic) * envelope
                }

                samples[frame] = Float(max(min(value * 0.22, 1), -1))
            }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer)
            player.play()

            audioEngine = engine
            playerNode = player
        } catch {
            // The success haptic still provides feedback when audio is unavailable.
        }
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct CelebrationConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var isAnimating = true

    private let particles = CelebrationParticle.makeParticles(count: 90)
    private let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .yellow]

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startDate)

                    for particle in particles {
                        let time = elapsed - particle.delay
                        guard time >= 0, time <= particle.lifetime else { continue }

                        let animationTime = CGFloat(time)
                        let x = CGFloat(particle.originX) * size.width
                            + CGFloat(particle.horizontalVelocity) * animationTime
                        let y = size.height - 60
                            - CGFloat(particle.verticalVelocity) * animationTime
                            + 0.5 * CGFloat(particle.gravity) * animationTime * animationTime
                        guard x > -30, x < size.width + 30, y < size.height + 30 else { continue }

                        let rotation = Angle.degrees(particle.rotationSpeed * time)
                        let rect = CGRect(
                            x: -CGFloat(particle.width) / 2,
                            y: -CGFloat(particle.height) / 2,
                            width: CGFloat(particle.width),
                            height: CGFloat(particle.height)
                        )

                        context.drawLayer { layer in
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: rotation)

                            if particle.isCircular {
                                layer.fill(
                                    Path(ellipseIn: rect),
                                    with: .color(colors[particle.colorIndex % colors.count])
                                )
                            } else {
                                layer.fill(
                                    Path(roundedRect: rect, cornerRadius: 2),
                                    with: .color(colors[particle.colorIndex % colors.count])
                                )
                            }
                        }
                    }
                }
            }
            .onAppear {
                startDate = Date()
                isAnimating = true
            }
            .task {
                try? await Task.sleep(nanoseconds: 3_600_000_000)
                isAnimating = false
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct CelebrationParticle {
    let originX: Double
    let horizontalVelocity: Double
    let verticalVelocity: Double
    let gravity: Double
    let delay: Double
    let lifetime: Double
    let rotationSpeed: Double
    let width: Double
    let height: Double
    let colorIndex: Int
    let isCircular: Bool

    static func makeParticles(count: Int) -> [CelebrationParticle] {
        (0..<count).map { index in
            let launchesFromLeft = index.isMultiple(of: 2)
            let spread = fraction(index, salt: 1)
            let heightVariation = fraction(index, salt: 2)
            let sizeVariation = fraction(index, salt: 3)

            return CelebrationParticle(
                originX: launchesFromLeft ? 0.08 : 0.92,
                horizontalVelocity: (launchesFromLeft ? 1 : -1) * (55 + spread * 190),
                verticalVelocity: 390 + heightVariation * 270,
                gravity: 420 + fraction(index, salt: 4) * 90,
                delay: fraction(index, salt: 5) * 0.45,
                lifetime: 2.4 + fraction(index, salt: 6) * 0.8,
                rotationSpeed: -360 + fraction(index, salt: 7) * 720,
                width: 6 + sizeVariation * 7,
                height: index.isMultiple(of: 3) ? 6 + sizeVariation * 6 : 11 + sizeVariation * 9,
                colorIndex: index,
                isCircular: index.isMultiple(of: 4)
            )
        }
    }

    private static func fraction(_ index: Int, salt: Int) -> Double {
        let value = (Double(index) * 0.618_033_988_75 + Double(salt) * 0.137).truncatingRemainder(dividingBy: 1)
        return value >= 0 ? value : value + 1
    }
}
