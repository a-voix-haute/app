// Réglages du moteur distant : clés, modèle, voix, consommation.
//
// Panneau distinct des autres réglages parce qu'il engage deux choses que les
// voix du système n'engagent pas — un compte facturé, et la sortie du texte
// hors de la machine. L'interface le dit plutôt que de le supposer connu.

import AppKit
import SwiftUI

struct VueMoteurDistant: View {

    @State private var reglages = Reglages.partage

    /// Clés et clé active : elles vivent dans le trousseau et l'index, hors
    /// de portée de l'observation — la vue les capture et les rafraîchit.
    @State private var cles: [CleAPI] = []
    @State private var cleActive: CleAPI?

    /// Feuille d'ajout ou de modification.
    @State private var feuilleOuverte = false

    /// Clé en cours de renommage ; `nil` pour un ajout.
    @State private var cleEnEdition: CleAPI?
    @State private var messageTest: String?
    @State private var testEnCours = false

    @State private var consommation: [(cle: String, appels: Int, caracteres: Int)] = []

    var body: some View {
        Form {
            sectionClés
            sectionModeleEtVoix
            sectionConsommation
        }
        .formStyle(.grouped)
        .onAppear(perform: rafraichir)
        .sheet(isPresented: $feuilleOuverte) {
            FeuilleCleAPI(cle: nil) { rafraichir() }
        }
        .sheet(item: $cleEnEdition) { cle in
            FeuilleCleAPI(cle: cle) { rafraichir() }
        }
    }

    // MARK: - Clés

    private var sectionClés: some View {
        Section {
            if cles.isEmpty {
                Text(cle: "openai.aucuneCle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cles) { cle in
                    HStack(spacing: 9) {
                        Image(systemName: cle.id == cleActive?.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(cle.id == cleActive?.id
                                             ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))

                        Text(cle.nom).font(.system(size: 13))
                        Spacer()

                        if cle.id != cleActive?.id {
                            Button(tr("openai.utiliser")) {
                                ClesAPI.definirActive(cle)
                                rafraichir()
                            }
                            .controlSize(.small)
                        }
                    }
                    .contentShape(Rectangle())
                    // Double-clic pour renommer : la convention macOS pour
                    // une liste éditable.
                    .onTapGesture(count: 2) { cleEnEdition = cle }
                }
            }

            // Boutons d'ajout et de retrait sous la liste, comme les tables
            // des Réglages Système.
            HStack(spacing: 6) {
                // Largeur imposée : « minus » est plus étroit que « plus », et
                // les deux boutons paraîtraient sinon de tailles différentes.
                Button {
                    cleEnEdition = nil
                    feuilleOuverte = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }

                Button {
                    if let active = cleActive {
                        ClesAPI.supprimer(active)
                        rafraichir()
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 14, height: 14)
                }
                .disabled(cleActive == nil)

                Spacer()

                if cleActive != nil {
                    if testEnCours { ProgressView().controlSize(.small) }
                    Button(tr("openai.tester")) { tester() }
                        .controlSize(.small)
                        .disabled(testEnCours)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let messageTest {
                Text(messageTest)
                    .font(.caption)
                    .foregroundStyle(messageTest.hasPrefix("✓") ? .green : .orange)
            }
        } header: {
            Text(cle: "openai.clesTitre")
        } footer: {
            Text(cle: "openai.noteCles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Modèle et voix

    private var sectionModeleEtVoix: some View {
        Section {
            Picker(tr("openai.modele"), selection: Binding(
                get: { reglages.modeleOpenAI },
                set: { reglages.modeleOpenAI = $0 }
            )) {
                ForEach(MoteurOpenAI.Modele.allCases, id: \.self) { modele in
                    Text(modele.libelle).tag(modele)
                }
            }
        } header: {
            Text(cle: "openai.syntheseTitre")
        } footer: {
            Text(cle: "openai.noteModele")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Consommation

    private var sectionConsommation: some View {
        Section {
            if consommation.isEmpty {
                Text(cle: "openai.aucunAppel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(consommation, id: \.cle) { ligne in
                    LabeledContent(ligne.cle) {
                        Text(tr("openai.consommationLigne", ligne.appels, ligne.caracteres))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                JournalAppelsAPI.ouvrirDansFinder()
            } label: {
                Label(tr("openai.ouvrirJournal"), systemImage: "doc.text")
            }
        } header: {
            Text(cle: "openai.consommationTitre")
        } footer: {
            Text(cle: "openai.noteConsommation")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func rafraichir() {
        cles = ClesAPI.toutes()
        cleActive = ClesAPI.active()
        consommation = JournalAppelsAPI.resume(depuis: JournalAppelsAPI.debutDuMois)
    }

    /// Valide la clé par une synthèse minimale.
    ///
    /// Deux mots suffisent : la requête coûte une fraction de centime et
    /// répond par la même erreur qu'un vrai appel si la clé est mauvaise.
    private func tester() {
        testEnCours = true
        messageTest = nil

        Task { @MainActor in
            defer { testEnCours = false }
            do {
                let moteur = MoteurOpenAI()
                let choisie = reglages.voix(pour: .openAI)
                guard let voix = moteur.voixDisponibles().first(where: { $0.id == choisie })
                        ?? moteur.voixDisponibles().first else { return }
                let fichier = try await moteur.synthetiser(
                    texte: tr("openai.texteTest"),
                    voix: voix,
                    vitesseBase: 1.0,
                    progression: { _ in }
                )
                GestionnaireFichiersTemp.supprimer(fichier)
                messageTest = "✓ " + tr("openai.testReussi")
                rafraichir()
            } catch {
                messageTest = error.localizedDescription
            }
        }
    }

}

// MARK: - Feuille d'ajout et de modification

/// Saisie d'une clé, en feuille modale.
///
/// Une feuille plutôt que des champs dans le formulaire : les champs de
/// saisie s'accordent mal à la mise en page d'un `Form` macOS, et la clé ne
/// se saisit qu'une fois — elle n'a pas à occuper la place en permanence.
private struct FeuilleCleAPI: View {

    /// Clé à renommer, ou `nil` pour un ajout.
    let cle: CleAPI?
    let surValidation: () -> Void

    @Environment(\.dismiss) private var fermer

    @State private var nom = ""
    @State private var secret = ""

    /// Le secret est-il affiché en clair ?
    ///
    /// `SecureField` refuse le collage dans un `Form` : une clé d'API se
    /// colle toujours, jamais ne se tape. Un champ ordinaire masqué par
    /// défaut, avec une bascule, est le compromis retenu — c'est aussi ce que
    /// font les gestionnaires de mots de passe.
    @State private var secretVisible = false

    private var estModification: Bool { cle != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(cle: estModification ? "openai.modifierCle" : "openai.ajouterCle")
                .font(.system(size: 15, weight: .semibold))

            Form {
                TextField(tr("openai.nomCle"), text: $nom,
                          prompt: Text(cle: "openai.nomExemple"))

                // Le secret n'est pas redemandé lors d'un simple renommage :
                // il est déjà dans le trousseau, et l'afficher serait inutile
                // autant qu'imprudent.
                if !estModification {
                    LabeledContent(tr("openai.secretCle")) {
                        HStack(spacing: 6) {
                            Group {
                                if secretVisible {
                                    TextField("", text: $secret,
                                              prompt: Text(verbatim: "sk-…"))
                                } else {
                                    SecureField("", text: $secret,
                                                prompt: Text(verbatim: "sk-…"))
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button {
                                secretVisible.toggle()
                            } label: {
                                Image(systemName: secretVisible ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(tr(secretVisible ? "openai.masquer" : "openai.afficher"))

                            Button {
                                if let colle = NSPasteboard.general.string(forType: .string) {
                                    secret = colle.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .buttonStyle(.borderless)
                            .help(tr("openai.coller"))
                        }
                    }
                }
            }
            .formStyle(.columns)

            if !estModification {
                Text(cle: "openai.noteSaisie")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(tr("raccourci.alertePlusTard")) { fermer() }
                    .keyboardShortcut(.cancelAction)

                Button(tr(estModification ? "openai.enregistrer" : "openai.ajouter")) {
                    valider()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!peutValider)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { nom = cle?.nom ?? "" }
    }

    private var peutValider: Bool {
        estModification
            ? !nom.trimmingCharacters(in: .whitespaces).isEmpty
            : !secret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func valider() {
        let nomRetenu = nom.trimmingCharacters(in: .whitespaces).isEmpty
            ? tr("openai.cleSansNom")
            : nom.trimmingCharacters(in: .whitespaces)

        if let cle {
            ClesAPI.renommer(cle, en: nomRetenu)
        } else {
            ClesAPI.enregistrer(nom: nomRetenu, secret: secret)
        }
        surValidation()
        fermer()
    }
}
