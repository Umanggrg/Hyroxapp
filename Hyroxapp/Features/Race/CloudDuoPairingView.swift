import SwiftUI

#if canImport(Supabase)

// Tier 2 (cloud-backed) counterpart to `DuoPairingView`. Same
// brand language and screen-flow shape; the differences are
// where the transports diverge:
//
//   • Host's "waiting" state shows a big 6-character pair code
//     instead of "Visible as <name>" — the partner has to know
//     the code, which they get over text / call / whatever.
//   • Guest's "joining" state shows a single text field for the
//     code instead of a discovered-peers list.
//   • Both sides use Supabase Realtime broadcast under the hood
//     instead of Multipeer; pairing is point-to-point rather
//     than nearby-network discovery.
//
// State branches mirror `CloudDuoCoordinator.CoordState`:
//   .idle                   → role picker
//   .hosting(transport)     → waiting screen with pair code
//   .joining(transport)     → code-entry screen
//   .ready(name, division)  → "Connected to X · ready to start"
struct CloudDuoPairingView: View {

    @Bindable var coordinator: CloudDuoCoordinator

    // Same callback shape DuoPairingView uses. Parent dismisses
    // the sheet and starts the race in duo mode when fired.
    var onReady: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Local state for the guest's code-entry field. Validated
    // via `DuoRoomCode.validate` before kicking off the join.
    @State private var enteredCode: String = ""
    @State private var joinError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HeroBackdrop(.calm)

                VStack(spacing: 24) {
                    Spacer(minLength: 12)

                    switch coordinator.state {
                    case .idle:
                        rolePicker
                    case .hosting(let transport):
                        hostingPanel(transport: transport)
                    case .joining(let transport):
                        joiningPanel(transport: transport)
                    case .ready(let partnerName, let partnerDivision):
                        readyPanel(
                            partnerName: partnerName,
                            partnerDivision: partnerDivision
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, Layout.screenMargin)
            }
            .navigationTitle("Cloud Duo")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                // Same teardown discipline as the Multipeer pairing
                // view — leaving without explicit Start cancels the
                // session so the duo_races row gets marked
                // 'abandoned' and the realtime channel drops.
                if case .ready = coordinator.state {
                    return
                }
                coordinator.cancel()
            }
        }
    }

    // MARK: - Role picker

    private var rolePicker: some View {
        VStack(spacing: 18) {
            heroIcon(
                symbol: "antenna.radiowaves.left.and.right",
                caption: "Race a partner anywhere"
            )

            VStack(spacing: 12) {
                actionButton(
                    title: "Host a Race",
                    subtitle: "Get a code your partner enters to join",
                    systemImage: "qrcode",
                    isPrimary: true
                ) {
                    Task { await coordinator.startHosting() }
                }

                actionButton(
                    title: "Enter a Code",
                    subtitle: "Join a race your partner is hosting",
                    systemImage: "keyboard",
                    isPrimary: false
                ) {
                    // Switch to the join flow. No network work
                    // yet — the actual SELECT + UPDATE fires
                    // when the user types a code and hits Go.
                    coordinator.beginJoinFlow()
                }
            }
        }
    }

    // MARK: - Hosting panel — show the code

    private func hostingPanel(transport: CloudDuoSession.State) -> some View {
        VStack(spacing: 22) {
            heroIcon(
                symbol: "antenna.radiowaves.left.and.right",
                caption: "Waiting for partner…"
            )

            // Big pair-code display. Monospaced for clarity (the
            // partner is reading + retyping); spaced groups of 3
            // characters help legibility ("ABC 123" not "ABC123").
            VStack(spacing: 6) {
                Text("Your pair code")
                    .capsLabelStyle()

                if let code = coordinator.session.pairCode {
                    Text(formattedCode(code))
                        .font(.system(size: 38, weight: .heavy, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .fill(Color.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                        .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                                )
                        )
                } else {
                    // Brief flash while the INSERT round-trips.
                    ProgressView()
                        .tint(Color.accent)
                        .padding(.vertical, 18)
                }
            }

            Text("Send this code to your partner. They'll tap **Enter a Code** on their phone and type it in.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Surface transport errors (e.g. couldn't reach
            // Supabase) inline. Other states (.creatingRoom,
            // .hostingRoom, .connected) self-explain via the
            // header.
            if case let .disconnected(reason?) = transport {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Insert a space after every 3 characters so a 6-char code
    // reads as two groups of 3. Easier on the eyes when the
    // partner is reading aloud over the phone.
    private func formattedCode(_ code: String) -> String {
        guard code.count == DuoRoomCode.length else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return code[..<mid] + " " + code[mid...]
    }

    // MARK: - Joining panel — code entry

    private func joiningPanel(transport: CloudDuoSession.State) -> some View {
        VStack(spacing: 18) {
            heroIcon(
                symbol: "keyboard",
                caption: "Enter your partner's code"
            )

            VStack(spacing: 8) {
                TextField("ABC 123", text: $enteredCode)
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .tracking(4)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .fill(Color.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                    .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .submitLabel(.go)
                    .onSubmit { attemptJoin() }

                if let joinError {
                    Text(joinError)
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
            }

            Button {
                attemptJoin()
            } label: {
                HStack(spacing: 8) {
                    if case .joiningRoom = transport {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.onAccent)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18, weight: .heavy))
                    }
                    Text("Join")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.accent, Color.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(DuoRoomCode.validate(enteredCode) == nil)
            .opacity(DuoRoomCode.validate(enteredCode) == nil ? 0.5 : 1.0)

            // Surface transport errors (e.g. code not found) inline.
            if case let .disconnected(reason?) = transport {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Validate, then dispatch to the coordinator. Visual feedback
    // for an invalid code goes through `joinError` so the user
    // sees a hint without an alert / sheet.
    private func attemptJoin() {
        guard let normalized = DuoRoomCode.validate(enteredCode) else {
            joinError = "Codes are 6 letters or numbers."
            return
        }
        joinError = nil
        Task { await coordinator.joinRoom(code: normalized) }
    }

    // MARK: - Ready panel

    private func readyPanel(partnerName: String, partnerDivision: Division) -> some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "checkmark.seal.fill", caption: "Paired")

            VStack(spacing: 4) {
                Text("Connected to")
                    .capsLabelStyle()
                Text(partnerName)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Text(partnerDivision.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Either of you can tap **Next Station** during the race. Times save to both your histories.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                onReady()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18, weight: .heavy))
                    Text("Start Duo Race")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.raceButtonHeight)
                .background(
                    LinearGradient(
                        colors: [Color.accent, Color.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.22),
                    radius: 18,
                    y: 0
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shared components (lifted from DuoPairingView)

    private func heroIcon(symbol: String, caption: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Color.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            .shadow(
                color: Color.accent.opacity(colorScheme == .dark ? 0.3 : 0.16),
                radius: 24,
                y: 0
            )

            Text(caption)
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.heavy))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isPrimary ? Color.onAccent.opacity(0.8) : Color.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.7)
            }
            .foregroundStyle(isPrimary ? Color.onAccent : Color.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(
                        isPrimary
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.accent, Color.accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Color.surface)
                    )
            )
            .shadow(
                color: isPrimary
                    ? Color.accent.opacity(colorScheme == .dark ? 0.30 : 0.16)
                    : Color.clear,
                radius: 16,
                y: 0
            )
        }
        .buttonStyle(.plain)
    }
}

#endif
