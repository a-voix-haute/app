// Contenu de la fenêtre du lecteur.

import SwiftUI

struct VueLecteur: View {

    @Bindable var lecteur: Lecteur

    let titre: String
    let surFermeture: () -> Void

    /// Position montrée pendant un glissement sur la barre : tant que le doigt
    /// est posé, l'affichage suit le curseur et non la lecture.
    @State private var positionGlissee: Double?
    @State private var survolFermeture = false

    private var positionAffichee: Double {
        positionGlissee ?? lecteur.position
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            enTete
            barreProgression
            transport
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(fond)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Fond

    private var fond: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    // MARK: - En-tête

    private var enTete: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(titre)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button(action: surFermeture) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(survolFermeture ? .primary : .tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { survolFermeture = $0 }
            .help("Fermer (Échap)")
        }
    }

    // MARK: - Progression

    private var barreProgression: some View {
        VStack(spacing: 3) {
            GeometryReader { geometrie in
                let largeur = geometrie.size.width
                let fraction = lecteur.duree > 0 ? positionAffichee / lecteur.duree : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(largeur, largeur * fraction)), height: 4)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, min(largeur - 9, largeur * fraction - 4.5)))
                        .shadow(radius: 1)
                }
                .frame(height: 12)
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
            .frame(height: 12)

            HStack {
                Text(Lecteur.formaterDuree(positionAffichee))
                Spacer()
                Text(Lecteur.formaterDuree(lecteur.duree))
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(.tertiary)
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
                taille: 17,
                aide: lecteur.etat == .enLecture ? "Pause (Espace)" : "Lecture (Espace)"
            ) {
                lecteur.basculerLecture()
            }
            .padding(.horizontal, 14)

            boutonIcone("goforward.15", aide: "Avancer de 15 secondes (→)") {
                lecteur.decaler(de: 15)
            }

            Spacer()

            Button {
                lecteur.vitesseSuivante()
            } label: {
                Text(Lecteur.formaterVitesse(lecteur.vitesse))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lecteur.vitesse == 1.0 ? Color.secondary : Color.accentColor)
                    .frame(minWidth: 36, minHeight: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(lecteur.vitesse == 1.0 ? 0.06 : 0.12))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Vitesse de lecture (↑ ↓)")
        }
    }

    private func boutonIcone(
        _ symbole: String,
        taille: CGFloat = 13,
        aide: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: taille, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: taille + 10, height: taille + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(aide)
    }
}

/// Pont vers NSVisualEffectView, absent de SwiftUI sur macOS.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let vue = NSVisualEffectView()
        vue.material = material
        vue.blendingMode = blendingMode
        vue.state = .active
        return vue
    }

    func updateNSView(_ vue: NSVisualEffectView, context: Context) {
        vue.material = material
        vue.blendingMode = blendingMode
    }
}
