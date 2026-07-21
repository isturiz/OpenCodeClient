import SwiftUI

struct ChatComposerView: View {
    let model: ChatViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            statusLine

            HStack(alignment: .bottom, spacing: 10) {
                voiceButton

                TextField(
                    model.recorder.state == .recording ? "Listening…" : "Message OpenCode",
                    text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                    axis: .vertical
                )
                .focused($isFocused)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("chat-composer")
                .onSubmit {
                    guard model.canSend else { return }
                    Task { await model.send() }
                }

                if model.status.isBusy {
                    Button {
                        Task { await model.abort() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: AppTheme.minimumHitTarget, height: AppTheme.minimumHitTarget)
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                    .accessibilityLabel("Stop agent")
                }

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: AppTheme.minimumHitTarget, height: AppTheme.minimumHitTarget)
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.signal)
                .disabled(!model.canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("chat-send")
            }
        }
        .padding(.horizontal, AppTheme.compactPadding)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.recorder.state == .recording {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("Listening")
                Spacer()
                Text(model.recorder.duration, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
                Text("sec")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if model.isTranscribing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing with FluidVoice…")
                Spacer()
                Button("Cancel") { model.cancelVoiceWork() }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if model.status.isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AppTheme.signal)
                Text("OpenCode is working")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var voiceButton: some View {
        Button {
            Task { await model.toggleVoiceRecording() }
        } label: {
            ZStack {
                if model.isTranscribing {
                    ProgressView()
                } else if model.recorder.state == .recording {
                    VoiceBars(isActive: true, level: model.recorder.level)
                        .frame(width: 22, height: 26)
                } else {
                    Image(systemName: "mic")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(width: AppTheme.minimumHitTarget, height: AppTheme.minimumHitTarget)
        }
        .buttonStyle(.glass)
        .tint(model.recorder.state == .recording ? .red : AppTheme.signal)
        .disabled(model.isTranscribing)
        .accessibilityLabel(model.recorder.state == .recording ? "Stop recording" : "Dictate with FluidVoice")
        .accessibilityIdentifier("chat-microphone")
    }
}
