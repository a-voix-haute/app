// Fenêtre de réglages, organisée en onglets.

import AppKit
import SwiftUI

/// Sections des réglages.
private enum SectionReglages: String, CaseIterable, Identifiable {
    case voix, lecture, raccourci, texte

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .voix:      return "Voix"
        case .lecture:   return "Lecture"
        case .raccourci: return "Raccourci"
        case .texte:     return "Texte"
        }
    }

    var symbole: String {
        switch self {
        case .voix:      return "waveform"
        case .lecture:   return "play.circle"
        case .raccourci: return "command"
        case .texte:     return "text.alignleft"
        }
    }
}

// Barre de sections dessinée à la main plutôt qu'un Picker segmenté : ce
// dernier trace un séparateur entre ses segments non sélectionnés, ce qui
// donnait des traits verticaux parasites entre les libellés.
struct VueReglages: View {

    @State private var section: SectionReglages = .voix

    var body: some View {
        VStack(spacing: 0) {
            barreSections

            Divider()

            Group {
                switch section {
                case .voix:      OngletVoix()
                case .lecture:   OngletLecture()
                case .raccourci: OngletRaccourci()
                case .texte:     OngletTexte()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 480)
    }

    private var barreSections: some View {
        HStack(spacing: 4) {
            ForEach(SectionReglages.allCases) { uneSection in
                BoutonSection(
                    section: uneSection,
                    actif: uneSection == section
                ) {
                    withAnimation(.snappy(duration: 0.15)) { section = uneSection }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

/// Un onglet de la barre de sections.
private struct BoutonSection: View {

    let section: SectionReglages
    let actif: Bool
    let action: () -> Void

    @State private var survole = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: section.symbole)
                    .font(.system(size: 16, weight: .regular))
                Text(section.libelle)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(actif ? Color.accentColor : Color.primary.opacity(0.75))
            .frame(width: 78, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fondCourant)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { survole = $0 }
    }

    private var fondCourant: Color {
        if actif { return Color.accentColor.opacity(0.14) }
        return survole ? Color.primary.opacity(0.06) : .clear
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

// MARK: - Onglet Raccourci

private struct OngletRaccourci: View {

    @State private var reglages = Reglages.partage
    @State private var autorise = CaptureSelection.estAutorisee
    @State private var conflit = false

    /// Combinaison retenue, identifiée par son libellé.
    private var combinaisonCourante: String {
        RaccourciGlobal.description(
            codeTouche: reglages.raccourciCodeTouche,
            modificateurs: reglages.raccourciModificateurs
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Activer le raccourci global", isOn: Binding(
                    get: { reglages.raccourciGlobalActif },
                    set: { actif in
                        reglages.raccourciGlobalActif = actif
                        conflit = actif && !RaccourciGlobal.partage.activer()
                        if !actif { RaccourciGlobal.partage.desactiver() }
                    }
                ))

                Picker("Combinaison", selection: Binding(
                    get: { combinaisonCourante },
                    set: { libelle in
                        guard let choix = RaccourciGlobal.combinaisonsProposees
                            .first(where: { $0.libelle == libelle }) else { return }
                        reglages.raccourciCodeTouche = choix.code
                        reglages.raccourciModificateurs = choix.modificateurs
                        conflit = reglages.raccourciGlobalActif
                            && !RaccourciGlobal.partage.activer()
                    }
                )) {
                    ForEach(RaccourciGlobal.combinaisonsProposees, id: \.libelle) { proposition in
                        Text(proposition.libelle).tag(proposition.libelle)
                    }
                }
                .disabled(!reglages.raccourciGlobalActif)

                if conflit {
                    Label(
                        "Cette combinaison est déjà utilisée par une autre application.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            } header: {
                Text("Raccourci clavier")
            } footer: {
                Text("Lit le texte sélectionné dans l'application au premier "
                   + "plan, quelle qu'elle soit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Accessibilité") {
                    Label(
                        autorise ? "Autorisé" : "Non autorisé",
                        systemImage: autorise ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(autorise ? .green : .orange)
                }

                if !autorise {
                    Button {
                        CaptureSelection.demanderAutorisation()
                        CaptureSelection.ouvrirReglagesAccessibilite()
                    } label: {
                        Label("Ouvrir les réglages d'Accessibilité…", systemImage: "lock.open")
                    }
                }

                Button("Vérifier à nouveau") {
                    autorise = CaptureSelection.estAutorisee
                }

                Toggle("Restaurer le presse-papiers après lecture", isOn: Binding(
                    get: { reglages.restaurerPressePapiers },
                    set: { reglages.restaurerPressePapiers = $0 }
                ))
            } header: {
                Text("Autorisation")
            } footer: {
                Text("La capture de la sélection passe par une copie simulée, "
                   + "ce que macOS n'autorise qu'aux applications inscrites en "
                   + "Accessibilité. Sans cette autorisation, le raccourci lit "
                   + "le presse-papiers.\n\nL'autorisation est attachée à "
                   + "l'emplacement de l'application : une copie lancée depuis "
                   + "un autre dossier que Applications est vue par macOS comme "
                   + "une application distincte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { autorise = CaptureSelection.estAutorisee }
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
                    Text("~/Library/Logs/AVoixHaute.log")
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

        // La marge sous la barre de titre est portée par la vue hôte : appliquée
        // au TabView lui-même, elle décalerait son fond et ferait apparaître le
        // bord de la vue sous forme de traits gris le long des onglets.
        hebergeur.view.wantsLayer = true

        let nouvelle = NSWindow(contentViewController: hebergeur)
        nouvelle.title = "Réglages d’À Voix Haute"
        nouvelle.styleMask = [.titled, .closable, .miniaturizable]
        nouvelle.isReleasedWhenClosed = false
        nouvelle.titlebarAppearsTransparent = false
        nouvelle.setContentSize(NSSize(width: 500, height: 460))
        nouvelle.center()

        fenetre = nouvelle
        nouvelle.makeKeyAndOrderFront(nil)

        // L'application est de type accessoire : sans activation explicite, la
        // fenêtre s'ouvrirait derrière celle de l'application au premier plan.
        NSApp.activate(ignoringOtherApps: true)
    }
}
