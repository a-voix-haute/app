// Fenêtre de réglages, organisée en onglets.

import AppKit
import SwiftUI

/// Sections des réglages.
private enum SectionReglages: String, CaseIterable, Identifiable {
    case voix, lecture, raccourci, integrations, texte

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .voix:      return tr("reglages.section.voix")
        case .lecture:   return tr("reglages.section.lecture")
        case .raccourci: return tr("reglages.section.raccourci")
        case .integrations: return tr("reglages.section.terminal")
        case .texte:     return tr("reglages.section.texte")
        }
    }

    var symbole: String {
        switch self {
        case .voix:      return "waveform"
        case .lecture:   return "play.circle"
        case .raccourci: return "command"
        case .integrations: return "terminal"
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
                case .integrations: VueIntegrations()
                case .texte:     OngletTexte()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 490)
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
            .frame(width: 74, height: 50)
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
                Picker(tr("voix.libelle"), selection: Binding(
                    get: { voixChoisie ?? "" },
                    set: { nouvelle in
                        voixChoisie = nouvelle.isEmpty ? nil : nouvelle
                        reglages.definirVoix(nouvelle.isEmpty ? nil : nouvelle, pour: .say)
                    }
                )) {
                    Text(cle: "voix.automatique").tag("")
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
                        Label(tr("voix.ecouterExtrait"), systemImage: "play.circle")
                    }
                    .disabled(voixChoisie == nil)

                    Button(tr("voix.arreter")) { CatalogueVoix.arreterApercu() }
                }
            } header: {
                Text(cle: "voix.titre")
            } footer: {
                Text(cle: "voix.noteAutomatique")
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
                    Text(cle: "voix.debit")
                } minimumValueLabel: {
                    Text(cle: "voix.debitLent").font(.caption2)
                } maximumValueLabel: {
                    Text(cle: "voix.debitRapide").font(.caption2)
                }

                LabeledContent(tr("voix.debitActuel")) {
                    Text(String(format: "%.2f×", reglages.vitesseSyntheseBase))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(cle: "voix.debitTitre")
            } footer: {
                Text(cle: "voix.noteDebit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(tr("voix.detectionLangue"), isOn: Binding(
                    get: { reglages.detectionLangueAuto },
                    set: { reglages.detectionLangueAuto = $0 }
                ))

                Button {
                    CatalogueVoix.ouvrirTelechargementVoix()
                } label: {
                    Label(tr("voix.telecharger"), systemImage: "arrow.down.circle")
                }
            } footer: {
                Text(cle: "voix.noteTelecharger")
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
                Toggle(tr("lecture.demarrageAuto"), isOn: Binding(
                    get: { reglages.demarrageAutomatique },
                    set: { reglages.demarrageAutomatique = $0 }
                ))

                Picker(tr("lecture.siLectureEnCours"), selection: Binding(
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
                Text(cle: "lecture.demarrageTitre")
            } footer: {
                Text(cle: "lecture.noteDemarrage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    tr("lecture.limite", reglages.limiteLecteurs),
                    value: Binding(
                        get: { reglages.limiteLecteurs },
                        set: { reglages.limiteLecteurs = $0 }
                    ),
                    in: 1...10
                )
            } footer: {
                Text(cle: "lecture.noteLimite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(tr("lecture.vitesseParDefaut"), selection: Binding(
                    get: { reglages.vitesseParDefaut },
                    set: { reglages.vitesseParDefaut = $0 }
                )) {
                    ForEach(Lecteur.vitessesDisponibles, id: \.self) { vitesse in
                        Text(Lecteur.formaterVitesse(vitesse)).tag(vitesse)
                    }
                }

                Picker(tr("lecture.pasDecalage"), selection: Binding(
                    get: { reglages.pasDecalage },
                    set: { reglages.pasDecalage = $0 }
                )) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { secondes in
                        Text(tr("lecture.secondes", secondes)).tag(secondes)
                    }
                }
            } header: {
                Text(cle: "lecture.controlesTitre")
            }

            Section {
                Toggle(tr("lecture.fermetureAuto"), isOn: Binding(
                    get: { reglages.fermetureAutomatique },
                    set: { reglages.fermetureAutomatique = $0 }
                ))

                Picker(tr("lecture.delaiFermeture"), selection: Binding(
                    get: { reglages.delaiFermetureAutomatique },
                    set: { reglages.delaiFermetureAutomatique = $0 }
                )) {
                    ForEach(Reglages.delaisFermetureDisponibles, id: \.self) { secondes in
                        Text(libelleDelai(secondes)).tag(secondes)
                    }
                }
                .disabled(!reglages.fermetureAutomatique)
            } header: {
                Text(cle: "lecture.fermetureTitre")
            } footer: {
                Text(cle: "lecture.noteFermeture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Délai exprimé en secondes ou en minutes selon son ampleur.
    private func libelleDelai(_ secondes: Int) -> String {
        secondes < 60
            ? tr("lecture.secondes", secondes)
            : tr("lecture.minutes", secondes / 60)
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
                Toggle(tr("raccourci.activer"), isOn: Binding(
                    get: { reglages.raccourciGlobalActif },
                    set: { actif in
                        reglages.raccourciGlobalActif = actif
                        conflit = actif && !RaccourciGlobal.partage.activer()
                        if !actif { RaccourciGlobal.partage.desactiver() }
                    }
                ))

                Picker(tr("raccourci.combinaison"), selection: Binding(
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
                        tr("raccourci.conflit"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            } header: {
                Text(cle: "raccourci.titre")
            } footer: {
                Text(cle: "raccourci.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(tr("raccourci.accessibilite")) {
                    Label(
                        tr(autorise ? "raccourci.autorise" : "raccourci.nonAutorise"),
                        systemImage: autorise ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(autorise ? .green : .orange)
                }

                if !autorise {
                    Button {
                        CaptureSelection.demanderAutorisation()
                        CaptureSelection.ouvrirReglagesAccessibilite()
                    } label: {
                        Label(tr("raccourci.ouvrirReglages"), systemImage: "lock.open")
                    }
                }

                Button(tr("raccourci.verifier")) {
                    autorise = CaptureSelection.estAutorisee
                }

                Toggle(tr("raccourci.restaurerPressePapiers"), isOn: Binding(
                    get: { reglages.restaurerPressePapiers },
                    set: { reglages.restaurerPressePapiers = $0 }
                ))
            } header: {
                Text(cle: "raccourci.autorisationTitre")
            } footer: {
                Text(cle: "raccourci.noteAutorisation")
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

    /// Ouvre la licence embarquée dans l'éditeur de texte du système.
    ///
    /// Le fichier est copié hors du bundle : une application signée n'autorise
    /// pas qu'on ouvre son contenu depuis une autre application.
    private func ouvrirLicence() {
        guard let source = Bundle.main.path(forResource: "LICENSE", ofType: "txt") else { return }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("À Voix Haute — Licence.txt")

        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(atPath: source, toPath: destination.path)

        NSWorkspace.shared.open(destination)
    }

    /// Version publiée, suivie du numéro de compilation.
    ///
    /// Les deux viennent de l'Info.plist, alimenté par le tag Git au moment de
    /// la publication.
    static var versionComplete: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let compilation = info?["CFBundleVersion"] as? String ?? "?"
        return compilation == "1" ? version : "\(version) (\(compilation))"
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("texte.nettoyageMarkdown"), isOn: Binding(
                    get: { reglages.nettoyageMarkdown },
                    set: { reglages.nettoyageMarkdown = $0 }
                ))
            } header: {
                Text(cle: "texte.preparationTitre")
            } footer: {
                Text(cle: "texte.noteNettoyage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(tr("maj.automatique"), isOn: Binding(
                    get: { reglages.miseAJourAutomatique },
                    set: { actif in
                        reglages.miseAJourAutomatique = actif
                        if actif {
                            VerificateurMiseAJour.partage.demarrerSurveillance()
                        } else {
                            VerificateurMiseAJour.partage.arreterSurveillance()
                        }
                    }
                ))

                Button {
                    Task { await VerificateurMiseAJour.partage.verifier(silencieux: false) }
                } label: {
                    Label(tr("maj.rechercherMaintenant"), systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text(cle: "maj.fenetre")
            } footer: {
                Text(cle: "maj.noteAutomatique")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(tr("texte.version")) {
                    Text(Self.versionComplete)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent(tr("texte.helper")) {
                    Text("lire").monospaced().foregroundStyle(.secondary)
                }
                Button {
                    ouvrirLicence()
                } label: {
                    Label(tr("texte.voirLicence"), systemImage: "doc.text")
                }

                Button {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/a-voix-haute/app")!
                    )
                } label: {
                    Label(tr("texte.ouvrirDepot"), systemImage: "chevron.left.forwardslash.chevron.right")
                }

                LabeledContent(tr("texte.journal")) {
                    Text("~/Library/Logs/AVoixHaute.log")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text(cle: "texte.informationsTitre")
            } footer: {
                Text(cle: "texte.noteTerminal")
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
        nouvelle.title = tr("reglages.titre")
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
