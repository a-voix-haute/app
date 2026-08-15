// Panneau des intégrations aux assistants en ligne de commande.

import AppKit
import SwiftUI

struct VueIntegrations: View {

    @State private var messageErreur: String?

    /// Assistants et, pour chacun, l'état de sa commande sur le disque.
    ///
    /// L'état est capturé ici plutôt que relu à l'affichage : `AssistantIA`
    /// est `Identifiable` et son `id` ne change pas quand le fichier
    /// apparaît, si bien que `ForEach` réutilisait les lignes sans les
    /// redessiner.
    @State private var assistants: [(assistant: AssistantIA, installee: Bool)] = []

    /// État de la commande et du lancement, capturés pour les mêmes raisons
    /// que ci-dessus : ils vivent hors de SwiftUI, sur le disque et dans
    /// LaunchServices.
    @State private var commandeInstallee = false
    @State private var dossierDansPath = true
    @State private var lancementActif = false
    @State private var approbationRequise = false

    var body: some View {
        Form {
            Section {
                Toggle(tr("installation.commande"), isOn: Binding(
                    get: { commandeInstallee },
                    set: { actif in
                        if actif {
                            InstallationSysteme.installerCommande()
                        } else {
                            InstallationSysteme.desinstallerCommande()
                        }
                        rafraichirInstallation()
                    }
                ))

                if commandeInstallee && !dossierDansPath {
                    // La commande existe mais reste introuvable : sans cette
                    // note, l'échec serait incompréhensible.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cle: "installation.pathAbsent")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(verbatim: "export PATH=\"$HOME/.local/bin:$PATH\"")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(tr("installation.ouvertureSession"), isOn: Binding(
                    get: { lancementActif },
                    set: { actif in
                        InstallationSysteme.definirLancementOuvertureSession(actif)
                        rafraichirInstallation()
                    }
                ))

                if approbationRequise {
                    Text(cle: "installation.approbationRequise")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(cle: "installation.titre")
            } footer: {
                Text(cle: "installation.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if assistants.contains(where: { $0.assistant.estPresent }) {
                    ForEach(assistants.filter { $0.assistant.estPresent }, id: \.assistant.id) { entree in
                        LigneAssistant(assistant: entree.assistant, installee: entree.installee) { rafraichir() }
                    }
                } else {
                    Text(cle: "terminal.aucun")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(cle: "terminal.detectes")
            } footer: {
                Text(cle: "terminal.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let absents = assistants.filter { !$0.assistant.estPresent }.map(\.assistant)
            if !absents.isEmpty {
                Section {
                    ForEach(absents) { assistant in
                        HStack {
                            Text(assistant.nom)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(cle: "terminal.nonInstalle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text(cle: "terminal.nonDetectes")
                } footer: {
                    Text(cle: "terminal.noteNonDetectes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    let nombre = IntegrationIA.installerPartout()
                    rafraichir()
                    messageErreur = nombre == 0
                        ? tr("terminal.aucuneInstallation")
                        : nil
                } label: {
                    Label(tr("terminal.installerPartout"), systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(!assistants.contains { $0.assistant.estPresent && !$0.installee })

                if let messageErreur {
                    Text(messageErreur)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(cle: "terminal.noteCommande")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { rafraichir() }
    }

    private func rafraichir() {
        assistants = IntegrationIA.assistants.map { ($0, $0.commandeInstallee) }
        rafraichirInstallation()
        messageErreur = nil
    }

    private func rafraichirInstallation() {
        commandeInstallee = InstallationSysteme.commandeInstallee
        dossierDansPath = InstallationSysteme.dossierDansPath
        lancementActif = InstallationSysteme.lancementOuvertureSession
        approbationRequise = InstallationSysteme.approbationRequise
    }
}

/// Une ligne du tableau : nom de l'assistant, état, bouton d'action.
private struct LigneAssistant: View {

    let assistant: AssistantIA
    /// État capturé par la vue parente, et non relu ici : voir `assistants`.
    let installee: Bool
    let surChangement: () -> Void

    @State private var survole = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: installee ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(installee ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))

            VStack(alignment: .leading, spacing: 1) {
                Text(assistant.nom)
                    .font(.system(size: 13))

                Text(installee
                     ? tr("terminal.installee", assistant.modeEmploi)
                     : tr("terminal.pasInstallee"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if installee {
                Button(tr("terminal.retirer")) {
                    IntegrationIA.desinstaller(de: assistant)
                    surChangement()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(tr("terminal.installer")) {
                    IntegrationIA.installer(dans: assistant)
                    surChangement()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
