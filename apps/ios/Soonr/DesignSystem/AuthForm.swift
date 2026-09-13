import SwiftUI

/// Sits on a clear row so it reads as a header rather than another card.
struct AuthHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Carries its own message, which puts it against the field it describes; a
/// shared section footer cannot once a form has more than one field.
struct AuthField<Content: View, Accessory: View>: View {
    let icon: String
    var message: String?
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                content

                accessory
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension AuthField where Accessory == EmptyView {
    init(icon: String, message: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(icon: icon, message: message, content: content) {
            EmptyView()
        }
    }
}

/// Mirrors a field's own status, so the icon and the message can never
/// disagree about what is wrong.
struct FieldStatusIndicator: View {
    let status: FieldStatus

    var body: some View {
        switch status {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Looks good")
        case .problem:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Needs attention")
        case .idle:
            EmptyView()
        }
    }
}

/// The primary action lives below the form rather than inside it: a `Button` in
/// a `Form` row is styled as a list row, which reads as disabled text rather
/// than the screen's main action.
///
/// It stays enabled while the form is incomplete. A greyed-out button cannot
/// say what is missing, cannot take focus, and is skipped by VoiceOver, so the
/// tap reports the problem instead.
struct AuthActions<Secondary: View>: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void
    @ViewBuilder let secondary: Secondary

    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Text(title)
                    .opacity(isBusy ? 0 : 1)
                    .frame(maxWidth: .infinity)
                    // An overlay, so the spinner cannot resize the button. In a
                    // large control it lays out large and the button grows with
                    // it.
                    .overlay {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                    }
            }
            .prominentButton()
            .controlSize(.large)
            .disabled(isBusy)

            secondary
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

/// Swaps between a secure and a plain field. Nothing in this stack can reset a
/// password, so being able to check what was typed matters more than usual.
struct PasswordField: View {
    let title: String
    @Binding var text: String
    let isVisible: Bool
    let contentType: UITextContentType

    var body: some View {
        Group {
            if isVisible {
                TextField(title, text: $text)
            } else {
                SecureField(title, text: $text)
            }
        }
        .textContentType(contentType)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}

struct PasswordVisibilityToggle: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash" : "eye")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isVisible ? "Hide password" : "Show password")
    }
}
