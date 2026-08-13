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
                    Text("Aucun assistant détecté sur cette machine.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Assistants détectés")
            } footer: {
                Text("Faites lire à voix haute la réponse d'un assistant, un "
                   + "fichier ou le presse-papiers, sans quitter le terminal."
                   + "\n\nCertains assistants s'invoquent par une commande, "
                   + "d'autres — Codex, Cursor — repèrent d'eux-mêmes qu'il "
                   + "faut lire : il suffit de le leur demander.")
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
                            Text("non installé")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Non détectés")
                } footer: {
                    Text("Ces assistants apparaîtront ici une fois installés.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    let nombre = IntegrationIA.installerPartout()
                    rafraichir()
                    messageErreur = nombre == 0
                        ? "Aucune installation effectuée."
                        : nil
                } label: {
                    Label("Installer partout", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(!assistants.contains { $0.estPresent && !$0.commandeInstallee })

                if let messageErreur {
                    Text(messageErreur)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("La commande `lire` doit être disponible dans le terminal : "
                   + "elle est installée avec l'application.")
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
                     ? "Installée — \(assistant.modeEmploi)"
                     : "Non installée")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if assistant.commandeInstallee {
                Button("Retirer") {
                    IntegrationIA.desinstaller(de: assistant)
                    surChangement()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Installer") {
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
