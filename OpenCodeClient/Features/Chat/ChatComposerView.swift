import SwiftUI

struct ChatComposerView: View {
    let model: ChatViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            statusLine

            HStack(alignment: .bottom, spacing: 2) {
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(
                            width: AppTheme.minimumHitTarget,
                            height: AppTheme.minimumHitTarget
                        )
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel("Add attachment")
                .accessibilityHint("Attachments are not available yet.")
                .accessibilityIdentifier("chat-add")

                TextField(
                    model.recorder.state == .recording ? "Listening…" : "Message OpenCode",
                    text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                    axis: .vertical
                )
                .focused($isFocused)
                .lineLimit(1...6)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .disabled(model.isSending)
                .accessibilityIdentifier("chat-composer")
                .onSubmit {
                    guard model.canSend else { return }
                    Task { await model.send() }
                }

                voiceButton

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(model.canSend ? AppTheme.signal : .secondary)
                        .frame(
                            width: AppTheme.minimumHitTarget,
                            height: AppTheme.minimumHitTarget
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("chat-send")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .padding(.horizontal, AppTheme.compactPadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.isDeleted {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("This conversation was deleted on the server.")
                Spacer()
            }
            .statusLineStyle()
        } else if model.submissionOutcomeUncertain {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                Text("Request outcome unknown")
                Spacer()
            }
            .statusLineStyle()
        } else if model.isCreatingSession {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Creating conversation…")
                Spacer()
            }
            .statusLineStyle()
        } else if model.recorder.state == .recording {
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
            .statusLineStyle()
        } else if model.isTranscribing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing with FluidVoice…")
                Spacer()
                Button("Cancel") { model.cancelVoiceWork() }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .statusLineStyle()
        } else if model.status.isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AppTheme.signal)
                Text("OpenCode is working")
                Spacer()
                Button("Stop", role: .destructive) {
                    Task { await model.abort() }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Stop agent")
            }
            .statusLineStyle()
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
            .foregroundStyle(model.recorder.state == .recording ? .red : AppTheme.signal)
            .frame(width: AppTheme.minimumHitTarget, height: AppTheme.minimumHitTarget)
        }
        .buttonStyle(.plain)
        .disabled(model.isTranscribing || model.isSending)
        .accessibilityLabel(model.recorder.state == .recording ? "Stop recording" : "Dictate with Voice")
        .accessibilityIdentifier("chat-microphone")
    }
}

private extension View {
    func statusLineStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}
