// Fenêtre de réglages, organisée en onglets.

import AppKit
import SwiftUI

struct VueReglages: View {
    var body: some View {
        TabView {
            OngletVoix()
                .tabItem { Label("Voix", systemImage: "waveform") }

            OngletLecture()
                .tabItem { Label("Lecture", systemImage: "play.circle") }

            OngletTexte()
                .tabItem { Label("Texte", systemImage: "text.alignleft") }
        }
        // Sans cette marge haute, la barre d'onglets vient toucher la barre de
        // titre de la fenêtre.
        .padding(.top, 12)
        .frame(width: 500, height: 450)
    }
}

// MARK: - Onglet Voix

private struct OngletVoix: View {

    @State private var reglages = Reglages.partage
    @State private var moteur = MoteurSay()
    @State private var groupes: [(langue: String, voix: [VoixDisponible])] = []
    @State private var voixChoisie: String?

    var body: some View {
        Form {
            Section {
                Picker("Voix", selection: Binding(
                    get: { voixChoisie ?? "" },
                    set: { nouvelle in
                        voixChoisie = nouvelle.isEmpty ? nil : nouvelle
                        reglages.definirVoix(nouvelle.isEmpty ? nil : nouvelle, pour: .say)
                    }
                )) {
                    Text("Automatique (selon la langue du texte)").tag("")
                    ForEach(groupes, id: \.langue) { groupe in
                        Section(CatalogueVoix.nomLangue(groupe.langue)) {
                            ForEach(groupe.voix) { voix in
                                Text(voix.descriptionComplete).tag(voix.id)
                            }
                        }
                    }
                }

                HStack {
                    Button {
                        if let identifiant = voixChoisie,
                           let voix = toutesLesVoix.first(where: { $0.id == identifiant }) {
                            CatalogueVoix.ecouterApercu(voix)
                        }
                    } label: {
                        Label("Écouter un extrait", systemImage: "play.circle")
                    }
                    .disabled(voixChoisie == nil)

                    Button("Arrêter") { CatalogueVoix.arreterApercu() }
                }
            } header: {
                Text("Voix de lecture")
            } footer: {
                Text("La voix automatique suit la langue détectée dans le texte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Slider(
                    value: Binding(
                        get: { Double(reglages.vitesseSyntheseBase) },
                        set: { reglages.vitesseSyntheseBase = Float($0) }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                ) {
                    Text("Débit de la voix")
                } minimumValueLabel: {
                    Text("lent").font(.caption2)
                } maximumValueLabel: {
                    Text("rapide").font(.caption2)
                }

                LabeledContent("Débit actuel") {
                    Text(String(format: "%.2f×", reglages.vitesseSyntheseBase))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Débit de synthèse")
            } footer: {
                Text("Réglage appliqué au moment de la synthèse. La vitesse "
                   + "ajustable dans le lecteur agit, elle, sur la lecture, "
                   + "sans altérer la hauteur de la voix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Détecter la langue automatiquement", isOn: Binding(
                    get: { reglages.detectionLangueAuto },
                    set: { reglages.detectionLangueAuto = $0 }
                ))

                Button {
                    CatalogueVoix.ouvrirTelechargementVoix()
                } label: {
                    Label("Télécharger d'autres voix…", systemImage: "arrow.down.circle")
                }
            } footer: {
                Text("Les voix Améliorées et Premium se téléchargent dans "
                   + "Réglages Système, rubrique Accessibilité puis Contenu "
                   + "énoncé. Les voix Siri restent réservées au système et ne "
                   + "sont accessibles à aucune application.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: charger)
        .onDisappear { CatalogueVoix.arreterApercu() }
    }

    private var toutesLesVoix: [VoixDisponible] {
        groupes.flatMap(\.voix)
    }

    private func charger() {
        groupes = CatalogueVoix.parLangue(moteur)
        voixChoisie = reglages.voix(pour: .say)
    }
}

// MARK: - Onglet Lecture

private struct OngletLecture: View {

    @State private var reglages = Reglages.partage

    var body: some View {
        Form {
            Section {
                Toggle("Démarrer la lecture automatiquement", isOn: Binding(
                    get: { reglages.demarrageAutomatique },
                    set: { reglages.demarrageAutomatique = $0 }
                ))

                Picker("Si une lecture est en cours", selection: Binding(
                    get: { reglages.comportementNouvelleLecture },
                    set: { reglages.comportementNouvelleLecture = $0 }
                )) {
                    ForEach(ComportementNouvelleLecture.allCases, id: \.self) { cas in
                        Text(cas.libelle).tag(cas)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!reglages.demarrageAutomatique)
            } header: {
                Text("Démarrage")
            } footer: {
                Text("Sans lecture en cours, une nouvelle demande démarre "
                   + "aussitôt. Sinon, elle suit la règle ci-dessus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    "Lecteurs simultanés : \(reglages.limiteLecteurs)",
                    value: Binding(
                        get: { reglages.limiteLecteurs },
                        set: { reglages.limiteLecteurs = $0 }
                    ),
                    in: 1...10
                )
            } footer: {
                Text("Au-delà de cette limite, le lecteur le plus ancien se "
                   + "ferme — d'abord ceux dont la lecture est terminée, puis "
                   + "ceux en pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Vitesse par défaut", selection: Binding(
                    get: { reglages.vitesseParDefaut },
                    set: { reglages.vitesseParDefaut = $0 }
                )) {
                    ForEach(Lecteur.vitessesDisponibles, id: \.self) { vitesse in
                        Text(Lecteur.formaterVitesse(vitesse)).tag(vitesse)
                    }
                }

                Picker("Avance et recul", selection: Binding(
                    get: { reglages.pasDecalage },
                    set: { reglages.pasDecalage = $0 }
                )) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { secondes in
                        Text("\(secondes) secondes").tag(secondes)
                    }
                }
            } header: {
                Text("Contrôles")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Onglet Texte

private struct OngletTexte: View {

    @State private var reglages = Reglages.partage

    var body: some View {
        Form {
            Section {
                Toggle("Nettoyer le balisage Markdown", isOn: Binding(
                    get: { reglages.nettoyageMarkdown },
                    set: { reglages.nettoyageMarkdown = $0 }
                ))
            } header: {
                Text("Préparation du texte")
            } footer: {
                Text("Retire les croisillons, astérisques, liens et tableaux "
                   + "pour que la voix ne les prononce pas. Les blocs de code "
                   + "sont annoncés sans être lus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Helper en ligne de commande") {
                    Text("lire").monospaced().foregroundStyle(.secondary)
                }
                LabeledContent("Journal") {
                    Text("~/Library/Logs/Lecteur.log")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Informations")
            } footer: {
                Text("Depuis le terminal : pbpaste | lire, lire fichier.md, "
                   + "ou lire --stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Fenêtre

/// Fenêtre de réglages, créée à la demande et conservée entre deux ouvertures.
@MainActor
final class FenetreReglages {

    static let partage = FenetreReglages()

    private var fenetre: NSWindow?

    private init() {}

    func afficher() {
        if let existante = fenetre {
            existante.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hebergeur = NSHostingController(rootView: VueReglages())
        let nouvelle = NSWindow(contentViewController: hebergeur)
        nouvelle.title = "Réglages de Lecteur"
        nouvelle.styleMask = [.titled, .closable, .miniaturizable]
        nouvelle.isReleasedWhenClosed = false
        // La barre de titre reste opaque et séparée du contenu : sans cela, le
        // TabView remonterait sous elle.
        nouvelle.titlebarAppearsTransparent = false
        nouvelle.setContentSize(NSSize(width: 500, height: 450))
        nouvelle.center()

        fenetre = nouvelle
        nouvelle.makeKeyAndOrderFront(nil)

        // L'application est de type accessoire : sans activation explicite, la
        // fenêtre s'ouvrirait derrière celle de l'application au premier plan.
        NSApp.activate(ignoringOtherApps: true)
    }
}
