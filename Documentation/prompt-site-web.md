# Prompt pour Bolt — site web d'À Voix Haute

Copiez tout ce qui suit la ligne de séparation dans Bolt.

---

Crée une landing page d'une seule page pour **À Voix Haute**, une application
macOS native qui lit n'importe quel texte à voix haute dans un lecteur audio
flottant.

## Stack technique

React + TypeScript + Vite, Tailwind CSS, Framer Motion pour les animations.
Aucune bibliothèque de composants : tout est écrit sur mesure. Le site doit être
statique, déployable sur Netlify ou Vercel.

## Ton et positionnement

Ce n'est pas une application grand public tape-à-l'œil. C'est un utilitaire
précis, pour des gens qui lisent beaucoup et veulent écouter à la place. Le ton
est **sobre, technique, assuré** — celui de Rectangle, Ice, Shottr ou Raycast à
ses débuts. Pas de superlatifs, pas d'émojis, pas de « révolutionnaire ».
L'argument porte parce qu'il est précis, pas parce qu'il crie.

Le site est **entièrement en français**, avec une typographie française correcte :
espaces insécables avant `: ; ! ?`, guillemets « … », apostrophes typographiques
’ et non '.

## Identité visuelle

- Couleur d'accent : dégradé de `#5E5CE6` vers `#3634A3` (violet-indigo, repris
  de l'icône de l'application)
- Fond : sombre par défaut, quasi noir `#0A0A0F`, avec une variante claire
  commutable par un bouton discret en en-tête. Le choix est mémorisé et suit
  `prefers-color-scheme` par défaut.
- Typographie : Inter ou la pile système `-apple-system, BlinkMacSystemFont`.
  Titres serrés (`tracking-tight`), corps de texte aéré (`leading-relaxed`).
- Beaucoup d'espace blanc. Largeur de contenu maximale 1100 px, centrée.
- Coins arrondis généreux (12 à 20 px), ombres portées douces et colorées plutôt
  que grises.
- Les animations sont **discrètes** : apparitions au défilement avec un léger
  décalage vertical, transitions de 200 à 300 ms. Rien qui rebondisse.

## Structure de la page

### 1. En-tête fixe

Barre translucide avec flou d'arrière-plan (`backdrop-blur`), qui se densifie
au défilement. À gauche le logo et le nom ; à droite deux liens d'ancrage
(« Fonctionnalités », « Installation »), le commutateur de thème, et un bouton
de téléchargement compact.

### 2. Section héros

**Titre :** Écoutez n’importe quel texte, où qu’il se trouve.

**Sous-titre :** Un lecteur audio flottant pour macOS, dont la vitesse s’ajuste
en cours d’écoute — sans que la voix parte dans les aigus.

Deux boutons : « Télécharger pour macOS » (principal, dégradé violet) et
« Voir comment ça marche » (secondaire, contour discret, ancre vers la
démonstration). Sous les boutons, en petit et en gris : « macOS 14 ou ultérieur
· Apple silicon et Intel · 956 Ko ».

À droite ou en dessous, une **reproduction du lecteur en HTML/CSS** — pas une
image. Reproduis fidèlement :

```
┌────────────────────────────────────────────┐
│  ⌁  rapport-hebdomadaire.md            ✕   │
│  ━━━━━━━━━●─────────────────────────────   │
│  1:24                                4:07  │
│  ⟲15      ▶      15⟳       −  1,5×  +  📌  │
└────────────────────────────────────────────┘
```

Fond translucide très sombre avec flou, coins arrondis à 22 px, fine bordure
claire à 8 % d'opacité, ombre portée violette diffuse. La barre de progression
est violette, la pastille blanche. Anime doucement la progression en boucle, et
fais varier la vitesse affichée entre 1×, 1,5× et 2× toutes les quelques
secondes. L'icône ⌁ pulse légèrement pendant la « lecture ».

### 3. Le problème — c'est le cœur du site

Titre : **macOS sait déjà lire à voix haute. Mal.**

Explique en deux paragraphes courts que le raccourci système « Énoncer la
sélection » fixe la vitesse au moment de la synthèse : impossible de l'ajuster
en cours d'écoute, et accélérer déforme la voix.

Puis une **démonstration visuelle du chiffre**, qui doit être le moment fort de
la page. Deux colonnes comparées :

| | Raccourci système | À Voix Haute |
|---|---|---|
| À vitesse normale | 76 Hz | 76 Hz |
| À 2,5× | **151 Hz** | **76 Hz** |

Représente-le par deux formes d'onde animées en SVG : à gauche une onde dont la
fréquence double visiblement quand on passe à 2,5× — les crêtes se resserrent,
et la couleur vire vers un orange d'alerte ; à droite une onde dont l'espacement
reste identique, seule la vitesse de défilement change, en violet.

Ajoute un curseur de vitesse que le visiteur peut manipuler de 0,5× à 3× : les
deux ondes réagissent en direct. C'est ce qui fera comprendre le problème en
trois secondes.

Sous le graphique, une note en petit : « Fréquence fondamentale mesurée sur la
même phrase, voix Thomas. »

### 4. Fonctionnalités

Titre : **Ce que ça change**

Grille de six cartes, deux ou trois colonnes selon la largeur. Chaque carte a
une icône dessinée en SVG (trait fin, 24 px, couleur d'accent), un titre court
et deux lignes de texte.

1. **Vitesse ajustable en cours d’écoute** — De 0,5× à 3×, par paliers, sans
   que la hauteur de la voix bouge d’un hertz.
2. **Toujours au-dessus** — Le lecteur reste visible par-dessus les autres
   fenêtres, même en plein écran, et vous suit d’un bureau à l’autre.
3. **Markdown nettoyé** — Ni croisillons, ni astérisques, ni adresses
   prononcées. Les blocs de code sont annoncés, pas récités.
4. **Plusieurs lectures à la fois** — Lancez-en une seconde sans interrompre la
   première. Les règles de coexistence se règlent.
5. **La voix de votre choix** — Toutes les voix du système, triées par langue et
   par qualité, avec écoute d’un extrait avant de choisir.
6. **Rien à configurer** — Un assistant vous accompagne au premier lancement.
   Trois minutes, et c’est réglé.

### 5. Les six accès

Titre : **Six façons de lancer une lecture**

Liste alternant texte et illustration, ou grille compacte. Chaque entrée montre
le geste :

- **Clic droit** — Sélection, puis Services, puis « Lire à voix haute ».
  Fonctionne dans n’importe quelle application.
- **Raccourci clavier** — `⌃⌥L` sur une sélection, où que vous soyez.
- **Barre de menus** — L’icône en forme d’onde, pour lire le presse-papiers.
- **Terminal** — `pbpaste | lire`, `lire document.md`, `lire --stop`.
- **Assistants IA** — La commande s’installe en un clic dans douze assistants en
  ligne de commande : Claude Code, Codex, Cursor, Gemini, Grok et d’autres.
- **URL** — `open "lire://presse-papiers"`, pour vos propres automatisations.

Pour l'entrée Terminal, affiche un bloc de code stylé avec un point-virgule
clignotant, comme un vrai terminal.

### 6. Téléchargement

Section resserrée, centrée, avec un fond légèrement dégradé.

Titre : **Installez-le maintenant**

Bouton principal pointant vers `https://example.com/AVoixHaute.dmg` — je
remplacerai l'adresse. Sous le bouton, trois mentions rassurantes sur une ligne,
séparées par des points médians :

« Signé et notarisé par Apple · Aucun avertissement au lancement · Version 1.0.1 »

En dessous, trois étapes numérotées, sobres :

1. Ouvrez le fichier téléchargé
2. Glissez l’application dans le dossier Applications
3. Lancez-la — l’assistant fait le reste

### 7. Pied de page

Minimal. Le nom, une ligne « Application macOS native. Swift, AppKit, SwiftUI. »,
l'année, et le commutateur de thème s'il n'est pas dans l'en-tête.

## Exigences techniques

- **Accessibilité** : contrastes conformes AA, navigation au clavier complète,
  `aria-label` sur les contrôles interactifs, respect de
  `prefers-reduced-motion` — les animations se désactivent alors entièrement.
- **Responsive** : trois points de rupture. Sur mobile, le lecteur du héros passe
  sous le texte, la grille de fonctionnalités passe à une colonne, la
  comparaison des ondes s'empile.
- **Performance** : aucune image bitmap sauf l'icône de l'application. Tout le
  reste en SVG ou en CSS. Pas de police chargée depuis un CDN.
- **Métadonnées** : titre, description, Open Graph et Twitter Card complets,
  `lang="fr"`, favicon dérivé du logo.

## Le logo

Utilise ce SVG tel quel, sans le redessiner. C'est l'icône de l'application,
au format web : fond transparent hors du carré arrondi, aucune marge perdue.
Place-le dans `public/logo.svg`, sers-t'en dans l'en-tête, le pied de page et
comme favicon.

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="fond" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#5E5CE6"/>
      <stop offset="100%" stop-color="#3634A3"/>
    </linearGradient>
    <linearGradient id="lueur" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.28"/>
      <stop offset="55%" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>

  <rect width="1024" height="1024" rx="228" ry="228" fill="url(#fond)"/>
  <rect width="1024" height="1024" rx="228" ry="228" fill="url(#lueur)"/>

  <g fill="#FFFFFF" stroke="none">
    <rect x="221" y="443" width="65" height="138" rx="33"/>
    <rect x="342" y="373" width="65" height="278" rx="33"/>
    <rect x="463" y="280" width="65" height="464" rx="33"/>
    <rect x="584" y="373" width="65" height="278" rx="33"/>
    <rect x="705" y="443" width="65" height="138" rx="33"/>
  </g>
</svg>
```

Pour le favicon, décline-le aussi en PNG 32 et 180 pixels. Dans l'en-tête, une
taille de 28 à 32 px suffit ; dans la section de téléchargement, tu peux le
montrer en 96 px.

## Ce qu'il ne faut pas faire

- Pas de section « témoignages » ni de logos d'entreprises inventés
- Pas de chiffres inventés : les seuls chiffres réels sont 76 Hz, 151 Hz, 0,5× à
  3×, douze assistants, 956 Ko, macOS 14
- Pas de captures d'écran factices : tout ce qui ressemble à l'interface doit
  être reproduit en HTML et CSS
- Pas de curseur défilant automatique, pas de compteur animé, pas de particules
- Pas d'anglicismes évitables : « téléchargement » et non « download »,
  « fonctionnalités » et non « features »
