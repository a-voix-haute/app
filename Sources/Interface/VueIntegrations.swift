// Panneau des intégrations aux assistants en ligne de commande.

import AppKit
import SwiftUI

struct VueIntegrations: View {

    /// Rafraîchi après chaque action pour refléter l'état du disque.
    @State private var revision = 0
    @State private var messageErreur: String?

    private var assistants: [AssistantIA] {
        _ = revision
        return IntegrationIA.assistants
    }

    var body: some View {
        Form {
            Section {
                if assistants.contains(where: \.estPresent) {
                    ForEach(assistants.filter(\.estPresent)) { assistant in
                        LigneAssistant(assistant: assistant) { rafraichir() }
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

            let absents = assistants.filter { !$0.estPresent }
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
                .disabled(!assistants.contains { $0.estPresent && !$0.commandeInstallee })

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
        revision += 1
        messageErreur = nil
    }
}

/// Une ligne du tableau : nom de l'assistant, état, bouton d'action.
private struct LigneAssistant: View {

    let assistant: AssistantIA
    let surChangement: () -> Void

    @State private var survole = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: assistant.commandeInstallee ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(assistant.commandeInstallee ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))

            VStack(alignment: .leading, spacing: 1) {
                Text(assistant.nom)
                    .font(.system(size: 13))

                Text(assistant.commandeInstallee
                     ? tr("terminal.installee", assistant.modeEmploi)
                     : tr("terminal.pasInstallee"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if assistant.commandeInstallee {
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
