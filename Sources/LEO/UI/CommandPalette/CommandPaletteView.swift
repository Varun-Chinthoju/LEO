import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var state: CommandPaletteController
    let onSubmit: (String) -> Void
    let onClose: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Ask LEO")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if !state.status.isEmpty {
                    Label(state.status, systemImage: state.status == "Failed" ? "exclamationmark.circle" : "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(state.status == "Failed" ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 7)

            HStack(spacing: 9) {
                if state.isVoiceListening {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.98, green: 0.28, blue: 0.63))
                                .frame(width: 6, height: 6)
                                .shadow(color: .pink.opacity(0.9), radius: 5)
                            Text("Listening…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        switch state.voicePhase {
                        case .listening:
                            SiriWaveform(level: state.voiceAudioLevel)
                        case .thinking:
                            ThinkingAnimation()
                        case .responding:
                            RespondingAnimation()
                        case .idle:
                            EmptyView()
                        }
                    }
                    .transition(.opacity)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                    TextField("What can I help with?", text: $state.text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($inputFocused)
                        .onSubmit { onSubmit(state.text) }
                        .onExitCommand(perform: onClose)
                }
            }

            if !state.response.isEmpty {
                Divider()
                    .padding(.top, 11)
                    .padding(.bottom, 10)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                    ScrollView(.vertical) {
                        Text(state.response)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                    .scrollIndicators(.automatic)
                    .accessibilityLabel("Full response")
                }
            }

            Divider()
                .padding(.top, state.response.isEmpty ? 13 : 14)
                .padding(.bottom, 8)
            HStack(spacing: 5) {
                Text("Ask about the current app or file")
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Button {
                    onSubmit(state.text)
                } label: {
                    Text("↵ Send")
                        .foregroundStyle(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("Esc Close")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10.5))
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if state.isVoiceListening {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.86))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.16),
                                        Color.purple.opacity(0.13),
                                        Color.pink.opacity(0.12)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    state.isVoiceListening
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.65), .purple.opacity(0.55), .pink.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(Color.primary.opacity(0.12)),
                    lineWidth: state.isVoiceListening ? 1 : 0.75
                )
        }
        .padding(1)
        .onAppear {
            // Defer one run-loop turn until the hosting panel is key; setting
            // focus synchronously during NSHostingView construction is ignored.
            DispatchQueue.main.async { inputFocused = true }
        }
    }
}

private struct SiriWaveform: View {
    let level: Double
    @State private var smoothedLevel = 0.08

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let energy = max(0.08, min(1, smoothedLevel))
            let voiceAmplitude = 1.5 + energy * 22.0

            Canvas { context, size in
                for lane in 0..<3 {
                    var path = Path()
                    let laneOffset = Double(lane) * 0.7
                    let amplitude = voiceAmplitude * (lane == 1 ? 1.0 : 0.55)
                    for x in stride(from: 0.0, through: size.width, by: 3.0) {
                        let progress = x / max(size.width, 1)
                        let envelope = sin(progress * .pi).magnitude
                        // Keep the carrier continuous; only its amplitude
                        // should respond to the microphone, preventing the
                        // waveform from snapping into a different shape.
                        let carrier = sin((progress * 17.0) + (time * 5.0) + laneOffset)
                            + (0.28 * sin((progress * 31.0) - (time * 2.4) + laneOffset))
                        let y = (size.height / 2) + carrier * amplitude * envelope
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let gradient = Gradient(colors: [
                        Color.cyan.opacity(lane == 1 ? 0.95 : 0.45),
                        Color.blue.opacity(lane == 1 ? 0.95 : 0.5),
                        Color.purple.opacity(lane == 1 ? 0.98 : 0.55),
                        Color.pink.opacity(lane == 1 ? 0.95 : 0.5)
                    ])
                    context.stroke(
                        path,
                        with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                        lineWidth: lane == 1 ? 2.3 : 1.0
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .shadow(color: .purple.opacity(0.55), radius: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Microphone listening")
            .accessibilityValue("Audio level \(Int(level * 100)) percent")
        }
        .onChange(of: level) { _, newValue in
            let target = max(0.08, min(1, newValue))
            withAnimation(.easeOut(duration: 0.12)) {
                smoothedLevel += (target - smoothedLevel) * 0.35
            }
        }
    }
}

private struct ThinkingAnimation: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = 8.0 + ((sin(time * 2.2) + 1) * 2.0)

                for ring in 0..<3 {
                    let radius = baseRadius + (Double(ring) * 6.0)
                    var orbit = Path()
                    orbit.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees((time * 80.0) + Double(ring * 100)),
                        endAngle: .degrees((time * 80.0) + Double(ring * 100) + 240),
                        clockwise: false
                    )
                    context.stroke(
                        orbit,
                        with: .linearGradient(
                            Gradient(colors: [.cyan, .blue, .purple, .pink]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: size.height)
                        ),
                        style: StrokeStyle(lineWidth: ring == 0 ? 2.2 : 1.0, lineCap: .round)
                    )
                }

                let glow = 7.0 + ((sin(time * 3.5) + 1) * 3.0)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - glow / 2, y: center.y - glow / 2, width: glow, height: glow)),
                    with: .color(.white.opacity(0.9))
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .shadow(color: .purple.opacity(0.8), radius: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Thinking")
        }
    }
}

private struct RespondingAnimation: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                var path = Path()
                for x in stride(from: 0.0, through: size.width, by: 3.0) {
                    let progress = x / max(size.width, 1)
                    let envelope = sin(progress * .pi).magnitude
                    let wave = sin(progress * 22.0 - time * 8.0)
                    let y = (size.height / 2) + wave * (4.0 + (envelope * 10.0))
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [.cyan, .blue, .purple, .pink]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    lineWidth: 2.5
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .shadow(color: .blue.opacity(0.7), radius: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("LEO is responding")
        }
    }
}
