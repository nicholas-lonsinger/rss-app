import SwiftUI

/// Encapsulates the two Atom-related alert modifiers shared by `AddFeedView`
/// and `EditFeedView`: the "Atom feed available" prompt (Switch to Atom / Keep
/// RSS) and the "Atom feed unavailable" fallback notice (OK).
struct AtomFeedAlerts: ViewModifier {
    @Binding var atomAlternatePrompt: AtomAlternatePrompt?
    let atomFallbackNotice: URL?
    let switchToAtom: (AtomAlternatePrompt) async -> Void
    let keepRSS: (AtomAlternatePrompt) -> Void
    let acknowledgeFallback: () -> Void
    /// Verb used in the fallback message body: "added" (AddFeedView) or
    /// "saved" (EditFeedView).
    let actionVerb: String

    func body(content: Content) -> some View {
        content
            .alert(
                "Atom feed available",
                isPresented: Binding(
                    get: { atomAlternatePrompt != nil },
                    set: { if !$0 { atomAlternatePrompt = nil } }
                ),
                presenting: atomAlternatePrompt
            ) { prompt in
                // RATIONALE: capture `prompt` synchronously here rather than
                // re-reading `atomAlternatePrompt` inside the Task. SwiftUI's
                // `.alert(isPresented:)` clears the bound state as the alert
                // dismisses, which races with the spawned Task and would cause
                // switchToAtom/keepRSS to see nil and no-op silently.
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
                isPresented: Binding(
                    get: { atomFallbackNotice != nil },
                    // Acknowledging the notice both clears it and signals
                    // the sheet to dismiss so the successfully-persisted feed
                    // becomes visible.
                    set: { if !$0 { acknowledgeFallback() } }
                ),
                presenting: atomFallbackNotice
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { atomURL in
                Text("The Atom feed at \(atomURL.absoluteString) couldn't be loaded. The RSS version has been \(actionVerb) instead.")
            }
    }
}

extension View {
    func atomFeedAlerts(
        atomAlternatePrompt: Binding<AtomAlternatePrompt?>,
        atomFallbackNotice: URL?,
        switchToAtom: @escaping (AtomAlternatePrompt) async -> Void,
        keepRSS: @escaping (AtomAlternatePrompt) -> Void,
        acknowledgeFallback: @escaping () -> Void,
        actionVerb: String
    ) -> some View {
        modifier(AtomFeedAlerts(
            atomAlternatePrompt: atomAlternatePrompt,
            atomFallbackNotice: atomFallbackNotice,
            switchToAtom: switchToAtom,
            keepRSS: keepRSS,
            acknowledgeFallback: acknowledgeFallback,
            actionVerb: actionVerb
        ))
    }
}
