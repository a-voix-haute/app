// Fenêtre proposant une mise à jour.
//
// L'utilisateur voit ce qui change avant de décider : une mise à jour qui
// s'installe sans prévenir laisse toujours le doute sur ce qu'elle a modifié.

import AppKit
import SwiftUI

struct VueMiseAJour: View {

    let version: VersionDisponible
    let surFermeture: () -> Void

    @State private var verificateur = VerificateurMiseAJour.partage

    private var installationEnCours: Bool {
        switch verificateur.etat {
        case .telechargement, .pretAInstaller: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete
            Divider()
            notes
            Divider()
            piedDePage
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - En-tête

    private var enTete: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(cle: "maj.disponibleTitre")
                    .font(.system(size: 17, weight: .semibold))

                Text(tr("maj.versionEtTaille",
                        version.version,
                        Self.formaterTaille(version.taille)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(tr("maj.versionInstallee", VerificateurMiseAJour.versionInstallee))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Notes de version

    private var notes: some View {
        ScrollView {
            Text(notesNettoyees)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(20)
        }
        .frame(maxHeight: .infinity)
    }

    /// Notes débarrassées de leur balisage : le lecteur en profite déjà, la
    /// fenêtre aussi.
    private var notesNettoyees: String {
        let propre = NettoyeurMarkdown.nettoyer(version.notes)
        return propre.isEmpty ? tr("maj.aucuneNote") : propre
    }

    // MARK: - Pied de page

    private var piedDePage: some View {
        HStack(spacing: 12) {
            if case .telechargement = verificateur.etat {
                ProgressView()
                    .controlSize(.small)
                Text(cle: "maj.telechargementEnCours")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if case .pretAInstaller = verificateur.etat {
                ProgressView()
                    .controlSize(.small)
                Text(cle: "maj.installationEnCours")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(tr("maj.plusTard")) { surFermeture() }
                .buttonStyle(.bordered)
                .disabled(installationEnCours)

            Button(tr("maj.installer")) {
                Task { await verificateur.installer(version) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(installationEnCours)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Format

    private static func formaterTaille(_ octets: Int) -> String {
        let formateur = ByteCountFormatter()
        formateur.countStyle = .file
        formateur.allowedUnits = [.useKB, .useMB]
        return formateur.string(fromByteCount: Int64(octets))
    }
}

// MARK: - Fenêtre

@MainActor
final class FenetreMiseAJour {

    static let partage = FenetreMiseAJour()

    private var fenetre: NSWindow?

    private init() {}

    func afficher(version: VersionDisponible) {
        // Une seule fenêtre à la fois : la vérification périodique ne doit pas
        // en empiler une par jour.
        if fenetre != nil {
            fenetre?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vue = VueMiseAJour(version: version) { [weak self] in
            self?.fermer()
        }

        let nouvelle = NSWindow(contentViewController: NSHostingController(rootView: vue))
        nouvelle.title = tr("maj.fenetre")
        nouvelle.styleMask = [.titled, .closable]
        nouvelle.isReleasedWhenClosed = false
        nouvelle.setContentSize(NSSize(width: 480, height: 420))
        nouvelle.center()
        nouvelle.level = .floating

        fenetre = nouvelle
        nouvelle.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func fermer() {
        fenetre?.orderOut(nil)
        fenetre = nil
    }
}
