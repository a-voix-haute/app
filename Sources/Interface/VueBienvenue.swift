// Assistant de configuration, présenté au premier lancement.
//
// L'application n'a pas de fenêtre principale : sans cet assistant, rien
// n'indique à l'utilisateur ce qu'elle sait faire ni comment l'invoquer. Les
// étapes suivent l'ordre de mise en service — découvrir, choisir une voix,
// accorder l'autorisation, retenir les raccourcis.

import AppKit
import SwiftUI

struct VueBienvenue: View {

    /// Étapes de l'assistant, dans l'ordre où elles sont présentées.
    enum Etape: Int, CaseIterable {
        case presentation
        case voix
        case autorisation
        case raccourcis
        case fin

        var titre: String {
            switch self {
            case .presentation: return "Bienvenue"
            case .voix:         return "Votre voix"
            case .autorisation: return "Autorisation"
            case .raccourcis:   return "Raccourcis"
            case .fin:          return "Tout est prêt"
            }
        }
    }

    @State private var etape: Etape = .presentation
    let surFermeture: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            contenu
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.top, 36)

            piedDePage
        }
        .frame(width: 560, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var contenu: some View {
        switch etape {
        case .presentation: EtapePresentation()
        case .voix:         EtapeVoix()
        case .autorisation: EtapeAutorisation()
        case .raccourcis:   EtapeRaccourcis()
        case .fin:          EtapeFin()
        }
    }

    // MARK: - Navigation

    private var piedDePage: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // Points de progression : plus lisibles qu'un compteur, et ils
                // montrent d'emblée la longueur de l'assistant.
                HStack(spacing: 6) {
                    ForEach(Etape.allCases, id: \.rawValue) { unePas in
                        Circle()
                            .fill(unePas == etape ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if etape != .presentation {
                    Button("Précédent") { reculer() }
                        .buttonStyle(.bordered)
                }

                if etape == .fin {
                    Button("Terminer") { surFermeture() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continuer") { avancer() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func avancer() {
        guard let suivante = Etape(rawValue: etape.rawValue + 1) else { return }
        withAnimation(.snappy(duration: 0.2)) { etape = suivante }
    }

    private func reculer() {
        guard let precedente = Etape(rawValue: etape.rawValue - 1) else { return }
        withAnimation(.snappy(duration: 0.2)) { etape = precedente }
    }
}

// MARK: - Présentation

private struct EtapePresentation: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)

            VStack(spacing: 8) {
                Text("À Voix Haute")
                    .font(.system(size: 26, weight: .semibold))

                Text("Écoutez n'importe quel texte, où qu'il se trouve.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Atout(
                    symbole: "gauge.with.dots.needle.bottom.50percent",
                    titre: "Vitesse ajustable en cours d'écoute",
                    detail: "De 0,5 à 3 fois, sans que la voix monte dans les aigus."
                )
                Atout(
                    symbole: "number",
                    titre: "Markdown nettoyé",
                    detail: "Ni croisillons, ni astérisques, ni adresses prononcées."
                )
                Atout(
                    symbole: "macwindow.on.rectangle",
                    titre: "Lecteur toujours visible",
                    detail: "Il reste au-dessus des autres fenêtres, même en plein écran."
                )
            }
            .padding(.top, 4)
        }
    }
}

private struct Atout: View {
    let symbole: String
    let titre: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbole)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Voix

private struct EtapeVoix: View {

    @State private var reglages = Reglages.partage
    @State private var moteur = MoteurSay()
    @State private var groupes: [(langue: String, voix: [VoixDisponible])] = []
    @State private var voixChoisie: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EnTeteEtape(
                symbole: "person.wave.2",
                titre: "Choisissez une voix",
                detail: "Les voix marquées Premium ou Améliorée sonnent nettement "
                      + "mieux que les voix compactes."
            )

            Picker("Voix", selection: $voixChoisie) {
                Text("Automatique (selon la langue du texte)").tag("")
                ForEach(groupes, id: \.langue) { groupe in
                    SwiftUI.Section(CatalogueVoix.nomLangue(groupe.langue)) {
                        ForEach(groupe.voix) { voix in
                            Text(voix.descriptionComplete).tag(voix.id)
                        }
                    }
                }
            }
            .onChange(of: voixChoisie) { _, nouvelle in
                reglages.definirVoix(nouvelle.isEmpty ? nil : nouvelle, pour: .say)
            }

            HStack {
                Button {
                    if let voix = groupes.flatMap(\.voix).first(where: { $0.id == voixChoisie }) {
                        CatalogueVoix.ecouterApercu(voix)
                    }
                } label: {
                    Label("Écouter un extrait", systemImage: "play.circle")
                }
                .disabled(voixChoisie.isEmpty)

                Button("Arrêter") { CatalogueVoix.arreterApercu() }

                Spacer()

                Button {
                    CatalogueVoix.ouvrirTelechargementVoix()
                } label: {
                    Label("En télécharger d'autres", systemImage: "arrow.down.circle")
                }
            }

            Text("Ce choix reste modifiable à tout moment dans les réglages.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            groupes = CatalogueVoix.parLangue(moteur)
            voixChoisie = reglages.voix(pour: .say) ?? ""
        }
        .onDisappear { CatalogueVoix.arreterApercu() }
    }
}

// MARK: - Autorisation

private struct EtapeAutorisation: View {

    @State private var autorise = CaptureSelection.estAutorisee
    @State private var minuteur: Timer?

    /// L'application s'exécute-t-elle depuis le dossier Applications ?
    private static var installeeDansApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EnTeteEtape(
                symbole: "lock.shield",
                titre: "Lire la sélection",
                detail: "Pour lire le texte sélectionné dans une autre application, "
                      + "macOS demande une autorisation d'accessibilité."
            )

            HStack(spacing: 10) {
                Image(systemName: autorise ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(autorise ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(autorise ? "Autorisation accordée" : "Autorisation non accordée")
                        .font(.system(size: 13, weight: .medium))
                    Text(autorise
                         ? "Le raccourci lira le texte sélectionné."
                         : "Sans elle, le raccourci lit le presse-papiers.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !autorise {
                    Button("Autoriser…") {
                        CaptureSelection.demanderAutorisation()
                        CaptureSelection.ouvrirReglagesAccessibilite()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            )

            if !autorise {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dans la fenêtre qui s'ouvre :")
                        .font(.system(size: 12, weight: .medium))
                    Text("1. Trouvez « À Voix Haute » dans la liste\n"
                       + "2. Activez l'interrupteur à côté de son nom")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // L'autorisation est attachée à l'emplacement du bundle : une
                // copie lancée depuis un dossier de compilation reste vue comme
                // une autre application, même autorisation accordée par ailleurs.
                if !Self.installeeDansApplications {
                    Label(
                        "Cette copie n'est pas dans le dossier Applications. "
                        + "L'autorisation accordée à la version installée ne "
                        + "s'applique pas à elle.",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Cette étape est facultative : tout le reste fonctionne sans elle.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            // L'autorisation est accordée dans une autre fenêtre : on surveille
            // son état pour refléter le changement sans intervention.
            minuteur = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                MainActor.assumeIsolated {
                    autorise = CaptureSelection.estAutorisee
                }
            }
        }
        .onDisappear {
            minuteur?.invalidate()
            minuteur = nil
        }
    }
}

// MARK: - Raccourcis

private struct EtapeRaccourcis: View {

    @State private var reglages = Reglages.partage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EnTeteEtape(
                symbole: "command",
                titre: "Quatre façons de lancer une lecture",
                detail: "Choisissez celle qui convient au moment."
            )

            VStack(alignment: .leading, spacing: 13) {
                Moyen(
                    symbole: "cursorarrow.click.2",
                    titre: "Clic droit sur une sélection",
                    detail: "Services, puis « Lire à voix haute »."
                )
                Moyen(
                    symbole: "keyboard",
                    titre: "Raccourci ⌃⌥L",
                    detail: "Lit la sélection courante, depuis n'importe quelle application."
                )
                Moyen(
                    symbole: "menubar.arrow.up.rectangle",
                    titre: "Barre de menus",
                    detail: "L'icône en forme d'onde, pour lire le presse-papiers."
                )
                Moyen(
                    symbole: "terminal",
                    titre: "Terminal",
                    detail: "pbpaste | lire — ou lire document.md"
                )
            }

            Toggle("Activer le raccourci ⌃⌥L", isOn: Binding(
                get: { reglages.raccourciGlobalActif },
                set: { actif in
                    reglages.raccourciGlobalActif = actif
                    if actif {
                        RaccourciGlobal.partage.activer()
                    } else {
                        RaccourciGlobal.partage.desactiver()
                    }
                }
            ))
            .padding(.top, 2)

            Spacer()
        }
    }
}

private struct Moyen: View {
    let symbole: String
    let titre: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbole)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Fin

private struct EtapeFin: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Tout est prêt")
                    .font(.system(size: 22, weight: .semibold))

                Text("À Voix Haute vit dans votre barre de menus et démarre\n"
                   + "avec votre session.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pour essayer tout de suite")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Sélectionnez un paragraphe dans votre navigateur,\n"
                   + "puis appuyez sur ⌃⌥L.")
                    .font(.system(size: 13))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }
}

// MARK: - Éléments communs

private struct EnTeteEtape: View {
    let symbole: String
    let titre: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: symbole)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                Text(titre)
                    .font(.system(size: 19, weight: .semibold))
            }

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Fenêtre

@MainActor
final class FenetreBienvenue {

    static let partage = FenetreBienvenue()

    private var fenetre: NSWindow?

    private init() {}

    /// Affiche l'assistant si l'utilisateur ne l'a jamais vu.
    func afficherSiPremierLancement() {
        guard !Reglages.partage.assistantVu else { return }
        afficher()
    }

    func afficher() {
        if let existante = fenetre {
            existante.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hebergeur = NSHostingController(rootView: VueBienvenue { [weak self] in
            Reglages.partage.assistantVu = true
            self?.fermer()
        })

        let nouvelle = NSWindow(contentViewController: hebergeur)
        nouvelle.title = "Bienvenue"
        nouvelle.styleMask = [.titled, .closable]
        nouvelle.isReleasedWhenClosed = false
        nouvelle.setContentSize(NSSize(width: 560, height: 480))
        nouvelle.center()

        fenetre = nouvelle
        nouvelle.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func fermer() {
        fenetre?.orderOut(nil)
        fenetre = nil
    }
}
