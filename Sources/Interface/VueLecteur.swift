// Contenu de la fenêtre du lecteur.
//
// La vue ne dessine aucun fond ni arrondi : c'est NSGlassEffectView qui porte
// le matériau Liquid Glass et le rayon des coins. Superposer un second arrondi
// ici produirait un liseré visible aux angles.

import SwiftUI

struct VueLecteur: View {

    @Bindable var lecteur: Lecteur

    let titre: String
    let surFermeture: () -> Void

    private var reglages: Reglages { Reglages.partage }

    /// Position montrée pendant un glissement sur la barre : tant que le doigt
    /// est posé, l'affichage suit le curseur et non la lecture.
    @State private var positionGlissee: Double?
    @State private var survolFermeture = false

    private var positionAffichee: Double {
        positionGlissee ?? lecteur.position
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            enTete
            barreProgression
            transport
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 13)
    }

    // MARK: - En-tête

    private var enTete: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, isActive: lecteur.etat == .enLecture)

            Text(titre)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button(action: surFermeture) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(survolFermeture ? .primary : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(.primary.opacity(survolFermeture ? 0.1 : 0))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { survolFermeture = $0 }
            .help("Fermer (Échap)")
        }
    }

    // MARK: - Progression

    private var barreProgression: some View {
        VStack(spacing: 4) {
            GeometryReader { geometrie in
                let largeur = geometrie.size.width
                let fraction = lecteur.duree > 0 ? positionAffichee / lecteur.duree : 0
                let position = max(0, min(largeur, largeur * fraction))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.12))
                        .frame(height: 5)

                    Capsule()
                        .fill(.tint)
                        .frame(width: position, height: 5)

                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .frame(width: 11, height: 11)
                        .offset(x: max(0, min(largeur - 11, position - 5.5)))
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { valeur in
                            guard lecteur.duree > 0 else { return }
                            let ratio = max(0, min(1, valeur.location.x / largeur))
                            positionGlissee = ratio * lecteur.duree
                        }
                        .onEnded { valeur in
                            guard lecteur.duree > 0 else { return }
                            let ratio = max(0, min(1, valeur.location.x / largeur))
                            lecteur.chercher(vers: ratio * lecteur.duree)
                            positionGlissee = nil
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(Lecteur.formaterDuree(positionAffichee))
                Spacer()
                Text(Lecteur.formaterDuree(lecteur.duree))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 0) {
            boutonIcone("gobackward.15", aide: "Reculer de 15 secondes (←)") {
                lecteur.decaler(de: -15)
            }

            boutonIcone(
                lecteur.etat == .enLecture ? "pause.fill" : "play.fill",
                taille: 18,
                aide: lecteur.etat == .enLecture ? "Pause (Espace)" : "Lecture (Espace)"
            ) {
                lecteur.basculerLecture()
            }
            .padding(.horizontal, 12)
            .contentTransition(.symbolEffect(.replace))

            boutonIcone("goforward.15", aide: "Avancer de 15 secondes (→)") {
                lecteur.decaler(de: 15)
            }

            Spacer()

            blocVitesse
        }
    }

    // MARK: - Vitesse

    /// Vrai quand la vitesse courante est déjà celle enregistrée par défaut.
    private var vitesseDejaParDefaut: Bool {
        abs(lecteur.vitesse - reglages.vitesseParDefaut) < 0.001
    }

    /// Réglage de la vitesse par paliers, avec enregistrement du défaut.
    ///
    /// Deux boutons distincts plutôt qu'un bouton cyclique : le sens de la
    /// correction est explicite, sans avoir à faire défiler toute la liste pour
    /// revenir d'un cran en arrière.
    private var blocVitesse: some View {
        HStack(spacing: 2) {
            boutonPalier(
                "minus",
                aide: "Ralentir (↓)",
                actif: lecteur.vitesse > Lecteur.vitessesDisponibles.first!
            ) {
                lecteur.vitessePrecedente()
            }

            Text(Lecteur.formaterVitesse(lecteur.vitesse))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(vitesseDejaParDefaut ? .secondary : .primary)
                .frame(minWidth: 38)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: lecteur.vitesse)

            boutonPalier(
                "plus",
                aide: "Accélérer (↑)",
                actif: lecteur.vitesse < Lecteur.vitessesDisponibles.last!
            ) {
                lecteur.vitesseSuivante()
            }

            boutonEnregistrer
                .padding(.leading, 3)
        }
    }

    /// Épingle la vitesse courante comme valeur par défaut des prochaines
    /// lectures. Désactivé lorsqu'elle l'est déjà.
    ///
    /// L'épingle pleine signale que la vitesse affichée est celle retenue :
    /// l'état est lisible sans avoir à ouvrir les réglages.
    private var boutonEnregistrer: some View {
        Button {
            reglages.vitesseParDefaut = lecteur.vitesse
        } label: {
            Image(systemName: vitesseDejaParDefaut ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(vitesseDejaParDefaut ? Color.accentColor : .secondary)
        .disabled(vitesseDejaParDefaut)
        .contentTransition(.symbolEffect(.replace))
        .help(vitesseDejaParDefaut
              ? "\(Lecteur.formaterVitesse(lecteur.vitesse)) est déjà la vitesse par défaut"
              : "Épingler \(Lecteur.formaterVitesse(lecteur.vitesse)) comme vitesse par défaut")
    }

    private func boutonPalier(
        _ symbole: String,
        aide: String,
        actif: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(actif ? .primary : .quaternary)
        .disabled(!actif)
        .help(aide)
    }

    private func boutonIcone(
        _ symbole: String,
        taille: CGFloat = 14,
        aide: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: taille, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: taille + 12, height: taille + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(aide)
    }
}
