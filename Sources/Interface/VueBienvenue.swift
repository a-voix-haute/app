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
        case terminal
        case fin

        var titre: String {
            switch self {
            case .presentation: return tr("bienvenue.fenetre")
            case .voix:         return tr("bienvenue.voix.titre")
            case .autorisation: return tr("raccourci.autorisationTitre")
            case .raccourcis:   return tr("reglages.section.raccourci")
            case .terminal:     return tr("reglages.section.terminal")
            case .fin:          return tr("bienvenue.fin.titre")
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
        case .terminal:     EtapeTerminal()
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
                    Button(tr("bienvenue.precedent")) { reculer() }
                        .buttonStyle(.bordered)
                }

                if etape == .fin {
                    Button(tr("bienvenue.terminer")) { surFermeture() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("bienvenue.continuer")) { avancer() }
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
                Text(cle: "bienvenue.presentation.titre")
                    .font(.system(size: 26, weight: .semibold))

                Text(cle: "bienvenue.presentation.sousTitre")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Atout(
                    symbole: "gauge.with.dots.needle.bottom.50percent",
                    titre: tr("bienvenue.atout1.titre"),
                    detail: tr("bienvenue.atout1.detail")
                )
                Atout(
                    symbole: "number",
                    titre: tr("bienvenue.atout2.titre"),
                    detail: tr("bienvenue.atout2.detail")
                )
                Atout(
                    symbole: "macwindow.on.rectangle",
                    titre: tr("bienvenue.atout3.titre"),
                    detail: tr("bienvenue.atout3.detail")
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
                titre: tr("bienvenue.voix.titre"),
                detail: tr("bienvenue.voix.detail")
            )

            Picker(tr("voix.libelle"), selection: $voixChoisie) {
                Text(cle: "voix.automatique").tag("")
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
                    Label(tr("voix.ecouterExtrait"), systemImage: "play.circle")
                }
                .disabled(voixChoisie.isEmpty)

                Button(tr("voix.arreter")) { CatalogueVoix.arreterApercu() }

                Spacer()

                Button {
                    CatalogueVoix.ouvrirTelechargementVoix()
                } label: {
                    Label(tr("bienvenue.voix.telecharger"), systemImage: "arrow.down.circle")
                }
            }

            Text(cle: "bienvenue.voix.note")
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
                titre: tr("bienvenue.autorisation.titre"),
                detail: tr("bienvenue.autorisation.detail")
                      + "macOS demande une autorisation d'accessibilité."
            )

            HStack(spacing: 10) {
                Image(systemName: autorise ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(autorise ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(autorise ? "bienvenue.autorisation.accordee" : "bienvenue.autorisation.nonAccordee"))
                        .font(.system(size: 13, weight: .medium))
                    Text(tr(autorise
                         ? "bienvenue.autorisation.detailAccordee"
                         : "bienvenue.autorisation.detailNonAccordee"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !autorise {
                    Button(tr("bienvenue.autorisation.autoriser")) {
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
                    Text(cle: "bienvenue.autorisation.marche")
                        .font(.system(size: 12, weight: .medium))
                    Text(cle: "bienvenue.autorisation.etapes")
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

            Text(cle: "bienvenue.autorisation.facultative")
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
                titre: tr("bienvenue.raccourcis.titre"),
                detail: tr("bienvenue.raccourcis.detail")
            )

            VStack(alignment: .leading, spacing: 13) {
                Moyen(
                    symbole: "cursorarrow.click.2",
                    titre: tr("bienvenue.moyen1.titre"),
                    detail: tr("bienvenue.moyen1.detail")
                )
                Moyen(
                    symbole: "keyboard",
                    titre: tr("bienvenue.moyen2.titre"),
                    detail: tr("bienvenue.moyen2.detail")
                )
                Moyen(
                    symbole: "menubar.arrow.up.rectangle",
                    titre: tr("bienvenue.moyen3.titre"),
                    detail: tr("bienvenue.moyen3.detail")
                )
                Moyen(
                    symbole: "terminal",
                    titre: tr("bienvenue.moyen4.titre"),
                    detail: tr("bienvenue.moyen4.detail")
                )
            }

            Toggle(tr("bienvenue.raccourcis.activer"), isOn: Binding(
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

// MARK: - Terminal

private struct EtapeTerminal: View {

    @State private var revision = 0
    @State private var installes = 0

    private var detectes: [AssistantIA] {
        _ = revision
        return IntegrationIA.assistantsPresents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnTeteEtape(
                symbole: "terminal",
                titre: tr("bienvenue.terminal.titre"),
                detail: "Faites lire la réponse d'un assistant sans quitter le "
                      + "terminal."
            )

            if detectes.isEmpty {
                Text(cle: "terminal.aucun")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(detectes) { assistant in
                        HStack(spacing: 9) {
                            Image(systemName: assistant.commandeInstallee
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(assistant.commandeInstallee
                                                 ? AnyShapeStyle(.green)
                                                 : AnyShapeStyle(.tertiary))

                            Text(assistant.nom)
                                .font(.system(size: 13))

                            Spacer()

                            if assistant.commandeInstallee {
                                // Les compétences n'ont pas de commande à
                                // taper : l'assistant s'en saisit de lui-même.
                                Text(assistant.invocation.isEmpty
                                     ? tr("terminal.automatique")
                                     : assistant.invocation)
                                    .font(.system(
                                        size: 11,
                                        design: assistant.invocation.isEmpty ? .default : .monospaced
                                    ))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )

                Button {
                    installes = IntegrationIA.installerPartout()
                    revision += 1
                } label: {
                    Label(tr("bienvenue.terminal.installerPartout"), systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!detectes.contains { !$0.commandeInstallee })

                if installes > 0 {
                    Text(tr("bienvenue.terminal.installees", installes))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text(cle: "bienvenue.terminal.note")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear { revision += 1 }
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
                Text(cle: "bienvenue.fin.titre")
                    .font(.system(size: 22, weight: .semibold))

                Text(cle: "bienvenue.fin.detail")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(cle: "bienvenue.fin.essayerTitre")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(cle: "bienvenue.fin.essayer")
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
        nouvelle.title = tr("bienvenue.fenetre")
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
