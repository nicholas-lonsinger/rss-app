import SwiftUI

/// Encapsulates the two Atom-related alert modifiers shared by `AddFeedView`
/// and `EditFeedView`: the "Atom feed available" prompt (Switch to Atom / Keep
/// RSS) and the "Atom feed unavailable" fallback notice (OK).
///
/// `atomAlternatePrompt` and `atomFallbackNotice` are mutually exclusive — the
/// view models ensure at most one is non-nil at a time.
struct AtomFeedAlerts: ViewModifier {
    @Binding var atomAlternatePrompt: AtomAlternatePrompt?
    @Binding var atomFallbackNotice: URL?
    let switchToAtom: (AtomAlternatePrompt) async -> Void
    let keepRSS: (AtomAlternatePrompt) -> Void
    /// Context used in the fallback message body.
    let actionVerb: ActionVerb

    enum ActionVerb {
        case added
        case saved

        var string: String {
            switch self {
            case .added: "added"
            case .saved: "saved"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "Atom feed available",
                isPresented: Binding(presentingIfNonNil: $atomAlternatePrompt),
                presenting: atomAlternatePrompt
            ) { prompt in
                // RATIONALE: We pass `prompt` directly into switchToAtom/keepRSS
                // rather than re-reading `atomAlternatePrompt` from the binding,
                // because SwiftUI clears the bound state as part of alert dismissal
                // — and the ordering between that setter and the button-action
                // closure is not guaranteed. If the setter fires first,
                // `atomAlternatePrompt` would be nil and the call site would have
                // no value to pass. The async Task in Switch to Atom makes the
                // window larger, but both paths share the same defense.
                Button("Switch to Atom") {
                    Task { await switchToAtom(prompt) }
                }
                Button("Keep RSS", role: .cancel) {
                    keepRSS(prompt)
                }
            } message: { prompt in
                Text("This site also publishes an Atom version of this feed at \(prompt.atomURL.absoluteString). Atom feeds often include richer metadata.")
            }
            .alert(
                "Atom feed unavailable",
                // Acknowledging the notice clears it; the view model's
                // didSet on atomFallbackNotice then signals sheet dismissal.
                isPresented: Binding(presentingIfNonNil: $atomFallbackNotice),
                presenting: atomFallbackNotice
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { atomURL in
                Text("The Atom feed at \(atomURL.absoluteString) couldn't be loaded. The RSS version has been \(actionVerb.string) instead.")
            }
    }
}

extension View {
    func atomFeedAlerts(
        atomAlternatePrompt: Binding<AtomAlternatePrompt?>,
        atomFallbackNotice: Binding<URL?>,
        switchToAtom: @escaping (AtomAlternatePrompt) async -> Void,
        keepRSS: @escaping (AtomAlternatePrompt) -> Void,
        actionVerb: AtomFeedAlerts.ActionVerb
    ) -> some View {
        modifier(AtomFeedAlerts(
            atomAlternatePrompt: atomAlternatePrompt,
            atomFallbackNotice: atomFallbackNotice,
            switchToAtom: switchToAtom,
            keepRSS: keepRSS,
            actionVerb: actionVerb
        ))
    }
}
