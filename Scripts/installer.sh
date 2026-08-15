#!/bin/bash
# Installe À Voix Haute dans /Applications.
#
#     Scripts/installer.sh                 installation complète
#     Scripts/installer.sh --sans-demarrage  sans lancement à l'ouverture de session
#     Scripts/installer.sh --desinstaller    retire tout
#
# Chaque option accepte aussi sa forme anglaise — `--uninstall`,
# `--no-startup` —, et la commande installée répond dans les six langues de
# l'application : `lire`, `read-aloud`, `leer`, `vorlesen`, `leggi`, `ler`.
#
# Ces alias sont permanents et non liés à la langue du système. C'est
# délibéré : une commande notée dans un script ou une documentation doit
# fonctionner sur toutes les machines, or un identifiant qui suivrait la langue
# du poste casserait dès qu'il en change.
#
# Les messages, eux, suivent bien la langue du Mac — ce sont des textes à lire,
# non des identifiants à taper. La distinction gouverne tout le projet.
#
# L'application est installée sous son nom accentué — « À Voix Haute.app » —
# tandis que son exécutable reste « AVoixHaute », sans accent : macOS distingue
# le nom du bundle de celui du binaire, et seul le premier est visible.

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOM_INSTALLE="À Voix Haute.app"
DESTINATION="/Applications/$NOM_INSTALLE"
DOSSIER_HELPERS="$HOME/.local/bin"

# Noms sous lesquels la commande répond, un par langue de l'application.
#
# « read-aloud » et non « read » : `read` est une primitive de bash et de zsh,
# et une primitive l'emporte toujours sur un fichier du PATH — le lien serait
# silencieusement sans effet, pire qu'absent. « leggi » et « ler » ne se
# heurtent à rien, « leer » et « vorlesen » non plus.
NOMS_HELPER=(lire read-aloud leer vorlesen leggi ler)
AGENT="$HOME/Library/LaunchAgents/app.avoixhaute.player.plist"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

# --- Langue -----------------------------------------------------------------
#
# Les messages suivent la langue du système, comme le reste de l'application.
# Un script shell n'a accès ni à `tr()` ni aux catalogues du bundle : la table
# ci-dessous en tient lieu.
#
# `AppleLanguages` plutôt que `$LANG` : c'est la préférence que macOS applique
# à l'application elle-même, là où `$LANG` dépend du terminal et peut être
# absent. Le repli est le français, langue de développement du projet.

# `AVOIXHAUTE_LANGUE` force la langue, ce que la préférence système ne permet
# pas de faire sans la modifier pour tout le Mac. Utile pour vérifier une
# traduction, et sans effet quand la variable est absente.
LANGUE="${AVOIXHAUTE_LANGUE:-$(defaults read -g AppleLanguages 2>/dev/null \
    | sed -n '2p' | tr -d ' ",' | cut -c1-2)}"
case "$LANGUE" in
    en|es|de|it|pt) ;;
    *) LANGUE=fr ;;
esac

# Rend le message identifié par $1 dans la langue courante.
#
# Les accolades `${!nom}` déréférencent une variable dont le nom est calculé :
# `msg titre_desinstallation` lit `M_en_titre_desinstallation` ou, à défaut,
# `M_fr_titre_desinstallation`.
msg() {
    local cle="M_${LANGUE}_$1" repli="M_fr_$1"
    printf '%s' "${!cle:-${!repli}}"
}

# Français — langue de référence, toujours définie : elle sert de repli à
# chaque clé qu'une traduction n'aurait pas.
M_fr_option_inconnue="Option inconnue :"
M_fr_desinstallation="Désinstallation…"
M_fr_agent_retire="agent de démarrage retiré"
M_fr_helpers_retires="commandes retirées"
M_fr_app_retiree="application retirée"
M_fr_desinstallation_finie="Désinstallation terminée."
M_fr_accessibilite_retirer="L'autorisation Accessibilité est à retirer manuellement dans"
M_fr_accessibilite_chemin="Réglages Système → Confidentialité et sécurité → Accessibilité."
M_fr_compilation="Compilation…"
M_fr_compilation_echec="Erreur : compilation impossible."
M_fr_installation_de="Installation de"
M_fr_arret_instance="arrêt de l'instance en cours"
M_fr_installee_dans="installée dans /Applications"
M_fr_helper_lie="commande liée :"
M_fr_service_enregistre="service « Lire à voix haute » enregistré"
M_fr_ancien_agent_retire="ancien agent de démarrage retiré"
M_fr_demarrage_active="lancement à l'ouverture de session activé"
M_fr_migration1="Mise à jour depuis la 1.x : l'identifiant de l'application a changé."
M_fr_migration2="Vos réglages ont été repris, mais macOS voit une application nouvelle :"
M_fr_migration3="l'autorisation Accessibilité est à réaccorder dans"
M_fr_migration4="Sans elle, le raccourci ⌃⌥L lit le presse-papiers au lieu de la sélection."
M_fr_installation_finie="Installation terminée, application lancée."
M_fr_installation_sans_demarrage="Installation terminée, mais l'application n'a pas démarré."
M_fr_consultez="Consultez ~/Library/Logs/AVoixHaute.log"
M_fr_usage="Usage :"
M_fr_usage_menu="icône ⌁ dans la barre de menus"
M_fr_usage_service="sélection + clic droit → Services → « Lire à voix haute »"
M_fr_usage_raccourci="raccourci ⌃⌥L sur une sélection"
M_fr_usage_terminal="terminal : pbpaste | lire, lire fichier.md, lire --stop"
M_fr_ajouter_path="Ajoutez ~/.local/bin à votre PATH pour la commande lire :"

M_en_option_inconnue="Unknown option:"
M_en_desinstallation="Uninstalling…"
M_en_agent_retire="login item removed"
M_en_helpers_retires="commands removed"
M_en_app_retiree="application removed"
M_en_desinstallation_finie="Uninstall complete."
M_en_accessibilite_retirer="The Accessibility permission must be removed manually in"
M_en_accessibilite_chemin="System Settings → Privacy & Security → Accessibility."
M_en_compilation="Building…"
M_en_compilation_echec="Error: build failed."
M_en_installation_de="Installing"
M_en_arret_instance="stopping the running instance"
M_en_installee_dans="installed in /Applications"
M_en_helper_lie="command linked:"
M_en_service_enregistre="“Read aloud” service registered"
M_en_ancien_agent_retire="previous login item removed"
M_en_demarrage_active="launch at login enabled"
M_en_migration1="Upgrading from 1.x: the application identifier has changed."
M_en_migration2="Your settings were carried over, but macOS sees a new application:"
M_en_migration3="the Accessibility permission must be granted again in"
M_en_migration4="Without it, ⌃⌥L reads the clipboard instead of the selection."
M_en_installation_finie="Installation complete, application launched."
M_en_installation_sans_demarrage="Installation complete, but the application did not start."
M_en_consultez="See ~/Library/Logs/AVoixHaute.log"
M_en_usage="Usage:"
M_en_usage_menu="⌁ icon in the menu bar"
M_en_usage_service="selection + right-click → Services → “Read aloud”"
M_en_usage_raccourci="⌃⌥L shortcut on a selection"
M_en_usage_terminal="terminal: pbpaste | read-aloud, read-aloud file.md, read-aloud --stop"
M_en_ajouter_path="Add ~/.local/bin to your PATH to use the command:"

M_es_option_inconnue="Opción desconocida:"
M_es_desinstallation="Desinstalando…"
M_es_agent_retire="ítem de inicio retirado"
M_es_helpers_retires="comandos retirados"
M_es_app_retiree="aplicación retirada"
M_es_desinstallation_finie="Desinstalación terminada."
M_es_accessibilite_retirer="El permiso de Accesibilidad debe retirarse manualmente en"
M_es_accessibilite_chemin="Ajustes del Sistema → Privacidad y seguridad → Accesibilidad."
M_es_compilation="Compilando…"
M_es_compilation_echec="Error: la compilación ha fallado."
M_es_installation_de="Instalando"
M_es_arret_instance="deteniendo la instancia en curso"
M_es_installee_dans="instalada en /Applications"
M_es_helper_lie="comando enlazado:"
M_es_service_enregistre="servicio «Leer en voz alta» registrado"
M_es_ancien_agent_retire="ítem de inicio anterior retirado"
M_es_demarrage_active="inicio al abrir sesión activado"
M_es_migration1="Actualización desde 1.x: el identificador de la aplicación ha cambiado."
M_es_migration2="Sus ajustes se han conservado, pero macOS ve una aplicación nueva:"
M_es_migration3="el permiso de Accesibilidad debe concederse de nuevo en"
M_es_migration4="Sin él, ⌃⌥L lee el portapapeles en vez de la selección."
M_es_installation_finie="Instalación terminada, aplicación iniciada."
M_es_installation_sans_demarrage="Instalación terminada, pero la aplicación no se ha iniciado."
M_es_consultez="Consulte ~/Library/Logs/AVoixHaute.log"
M_es_usage="Uso:"
M_es_usage_menu="icono ⌁ en la barra de menús"
M_es_usage_service="selección + clic derecho → Servicios → «Leer en voz alta»"
M_es_usage_raccourci="atajo ⌃⌥L sobre una selección"
M_es_usage_terminal="terminal: pbpaste | leer, leer archivo.md, leer --stop"
M_es_ajouter_path="Añada ~/.local/bin a su PATH para usar el comando:"

M_de_option_inconnue="Unbekannte Option:"
M_de_desinstallation="Deinstallation…"
M_de_agent_retire="Anmeldeobjekt entfernt"
M_de_helpers_retires="Befehle entfernt"
M_de_app_retiree="Programm entfernt"
M_de_desinstallation_finie="Deinstallation abgeschlossen."
M_de_accessibilite_retirer="Die Bedienungshilfen-Berechtigung muss manuell entfernt werden in"
M_de_accessibilite_chemin="Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen."
M_de_compilation="Kompilierung…"
M_de_compilation_echec="Fehler: Kompilierung fehlgeschlagen."
M_de_installation_de="Installation von"
M_de_arret_instance="laufende Instanz wird beendet"
M_de_installee_dans="in /Applications installiert"
M_de_helper_lie="Befehl verknüpft:"
M_de_service_enregistre="Dienst „Vorlesen“ registriert"
M_de_ancien_agent_retire="früheres Anmeldeobjekt entfernt"
M_de_demarrage_active="Start bei der Anmeldung aktiviert"
M_de_migration1="Aktualisierung von 1.x: die Programmkennung hat sich geändert."
M_de_migration2="Ihre Einstellungen wurden übernommen, doch macOS sieht ein neues Programm:"
M_de_migration3="die Bedienungshilfen-Berechtigung muss erneut erteilt werden in"
M_de_migration4="Ohne sie liest ⌃⌥L die Zwischenablage statt der Auswahl."
M_de_installation_finie="Installation abgeschlossen, Programm gestartet."
M_de_installation_sans_demarrage="Installation abgeschlossen, aber das Programm ist nicht gestartet."
M_de_consultez="Siehe ~/Library/Logs/AVoixHaute.log"
M_de_usage="Verwendung:"
M_de_usage_menu="⌁ Symbol in der Menüleiste"
M_de_usage_service="Auswahl + Rechtsklick → Dienste → „Vorlesen“"
M_de_usage_raccourci="Kurzbefehl ⌃⌥L auf einer Auswahl"
M_de_usage_terminal="Terminal: pbpaste | vorlesen, vorlesen datei.md, vorlesen --stop"
M_de_ajouter_path="Fügen Sie ~/.local/bin zu Ihrem PATH hinzu, um den Befehl zu nutzen:"

M_it_option_inconnue="Opzione sconosciuta:"
M_it_desinstallation="Disinstallazione…"
M_it_agent_retire="elemento di login rimosso"
M_it_helpers_retires="comandi rimossi"
M_it_app_retiree="applicazione rimossa"
M_it_desinstallation_finie="Disinstallazione completata."
M_it_accessibilite_retirer="L'autorizzazione Accessibilità va rimossa manualmente in"
M_it_accessibilite_chemin="Impostazioni di Sistema → Privacy e sicurezza → Accessibilità."
M_it_compilation="Compilazione…"
M_it_compilation_echec="Errore: compilazione non riuscita."
M_it_installation_de="Installazione di"
M_it_arret_instance="arresto dell'istanza in corso"
M_it_installee_dans="installata in /Applications"
M_it_helper_lie="comando collegato:"
M_it_service_enregistre="servizio «Leggi ad alta voce» registrato"
M_it_ancien_agent_retire="precedente elemento di login rimosso"
M_it_demarrage_active="avvio all'accesso attivato"
M_it_migration1="Aggiornamento da 1.x: l'identificatore dell'applicazione è cambiato."
M_it_migration2="Le impostazioni sono state riprese, ma macOS vede una nuova applicazione:"
M_it_migration3="l'autorizzazione Accessibilità va concessa di nuovo in"
M_it_migration4="Senza di essa, ⌃⌥L legge gli appunti invece della selezione."
M_it_installation_finie="Installazione completata, applicazione avviata."
M_it_installation_sans_demarrage="Installazione completata, ma l'applicazione non si è avviata."
M_it_consultez="Consultare ~/Library/Logs/AVoixHaute.log"
M_it_usage="Uso:"
M_it_usage_menu="icona ⌁ nella barra dei menu"
M_it_usage_service="selezione + clic destro → Servizi → «Leggi ad alta voce»"
M_it_usage_raccourci="scorciatoia ⌃⌥L su una selezione"
M_it_usage_terminal="terminale: pbpaste | leggi, leggi file.md, leggi --stop"
M_it_ajouter_path="Aggiungete ~/.local/bin al vostro PATH per usare il comando:"

M_pt_option_inconnue="Opção desconhecida:"
M_pt_desinstallation="Desinstalação…"
M_pt_agent_retire="item de arranque removido"
M_pt_helpers_retires="comandos removidos"
M_pt_app_retiree="aplicação removida"
M_pt_desinstallation_finie="Desinstalação concluída."
M_pt_accessibilite_retirer="A autorização de Acessibilidade deve ser removida manualmente em"
M_pt_accessibilite_chemin="Definições do Sistema → Privacidade e segurança → Acessibilidade."
M_pt_compilation="Compilação…"
M_pt_compilation_echec="Erro: compilação falhou."
M_pt_installation_de="Instalação de"
M_pt_arret_instance="a parar a instância em curso"
M_pt_installee_dans="instalada em /Applications"
M_pt_helper_lie="comando ligado:"
M_pt_service_enregistre="serviço «Ler em voz alta» registado"
M_pt_ancien_agent_retire="item de arranque anterior removido"
M_pt_demarrage_active="arranque na sessão activado"
M_pt_migration1="Actualização a partir da 1.x: o identificador da aplicação mudou."
M_pt_migration2="As suas definições foram retomadas, mas o macOS vê uma aplicação nova:"
M_pt_migration3="a autorização de Acessibilidade deve ser concedida de novo em"
M_pt_migration4="Sem ela, ⌃⌥L lê a área de transferência em vez da selecção."
M_pt_installation_finie="Instalação concluída, aplicação iniciada."
M_pt_installation_sans_demarrage="Instalação concluída, mas a aplicação não arrancou."
M_pt_consultez="Consulte ~/Library/Logs/AVoixHaute.log"
M_pt_usage="Utilização:"
M_pt_usage_menu="ícone ⌁ na barra de menus"
M_pt_usage_service="selecção + clique direito → Serviços → «Ler em voz alta»"
M_pt_usage_raccourci="atalho ⌃⌥L numa selecção"
M_pt_usage_terminal="terminal: pbpaste | ler, ler ficheiro.md, ler --stop"
M_pt_ajouter_path="Adicione ~/.local/bin ao seu PATH para usar o comando:"

AVEC_DEMARRAGE=true
DESINSTALLER=false

for argument in "$@"; do
    case "$argument" in
        --sans-demarrage|--no-startup) AVEC_DEMARRAGE=false ;;
        --desinstaller|--uninstall)    DESINSTALLER=true ;;
        *) echo "$(msg option_inconnue) $argument" >&2; exit 1 ;;
    esac
done

# --- Désinstallation --------------------------------------------------------

if $DESINSTALLER; then
    echo "$(msg desinstallation)"

    pkill -x "AVoixHaute" 2>/dev/null || true
    sleep 1

    # L'inscription à l'ouverture de session appartient désormais à
    # SMAppService : elle se retire par l'application, tant qu'elle est encore
    # installée. `sleep` laisse le temps du désenregistrement avant que
    # `pkill` plus bas ne coupe le processus.
    if [ -d "$DESTINATION" ]; then
        open -b app.avoixhaute.player --args --retirer-ouverture-session 2>/dev/null || true
        sleep 2
    fi

    # L'agent des versions 1.x et 2.0.x, quand il subsiste.
    if [ -f "$AGENT" ]; then
        launchctl unload "$AGENT" 2>/dev/null || true
        rm -f "$AGENT"
        echo "  $(msg agent_retire)"
    fi

    # Seuls les liens symboliques sont retirés : un fichier ordinaire portant
    # l'un de ces noms n'est pas le nôtre et ne nous appartient pas.
    retires=0
    for nom in "${NOMS_HELPER[@]}"; do
        if [ -L "$DOSSIER_HELPERS/$nom" ]; then
            rm -f "$DOSSIER_HELPERS/$nom"
            retires=$((retires + 1))
        fi
    done
    [ "$retires" -gt 0 ] && echo "  $(msg helpers_retires) ($retires)"

    if [ -d "$DESTINATION" ]; then
        "$LSREGISTER" -u "$DESTINATION" 2>/dev/null || true
        rm -rf "$DESTINATION"
        echo "  $(msg app_retiree)"
    fi

    rm -rf "$HOME/Library/Application Support/AVoixHaute"
    rm -f "$HOME/Library/Logs/AVoixHaute.log"
    rm -rf "$HOME/Library/Caches/app.avoixhaute.player"
    rm -rf "$HOME/Library/Caches/fr.dimitri.AVoixHaute"

    # Les deux identifiants sont purgés : celui d'aujourd'hui et celui d'avant
    # la 2.0.0. Le renommage précédent — « Lecteur » vers « À Voix Haute » —
    # avait laissé ses préférences derrière lui, faute de cette ligne.
    #
    # La suite de tests crée un domaine par exécution, « …tests.<UUID> » : sans
    # le motif, ils s'accumulent indéfiniment.
    for domaine in app.avoixhaute.player fr.dimitri.AVoixHaute fr.dimitri.Lecteur; do
        defaults delete "$domaine" 2>/dev/null || true
        rm -f "$HOME/Library/Preferences/$domaine.plist"
        rm -f "$HOME/Library/Preferences/$domaine".tests.*.plist
    done
    # `cfprefsd` garde les préférences en mémoire et réécrirait les fichiers
    # que l'on vient de supprimer.
    killall cfprefsd 2>/dev/null || true

    "$PBS" -flush 2>/dev/null || true

    echo
    echo "$(msg desinstallation_finie)"
    echo "$(msg accessibilite_retirer)"
    echo "$(msg accessibilite_chemin)"
    exit 0
fi

# --- Installation -----------------------------------------------------------

APP_SOURCE="$RACINE/build/Build/Products/Release/AVoixHaute.app"

# La compilation est systématique, et non conditionnée à l'absence de
# `build/`. Un dossier présent mais antérieur aux sources ferait installer une
# version périmée, que l'on testerait alors sans le savoir — le cas s'est
# produit avec les catalogues de traduction et le helper. `xcodebuild` sait de
# lui-même ne rien refaire quand rien n'a changé, le coût est donc nul.
#
# Corollaire : `xcodebuild … test` compile en Debug dans le même `build/` et
# laisse la cible Release dans un état intermédiaire. Lancer les tests puis
# installer sans repasser par ici copierait ce résultat partiel. Réinstaller
# après les tests, et non l'inverse.
echo "$(msg compilation)"
"$RACINE/Scripts/construire.sh"

if [ ! -d "$APP_SOURCE" ]; then
    echo "$(msg compilation_echec)" >&2
    exit 1
fi

# Accolades obligatoires : sans elles, bash agrège le caractère « … » qui suit
# au nom de la variable.
echo "$(msg installation_de) ${NOM_INSTALLE}…"

# L'application ne doit pas tourner pendant son remplacement.
if pgrep -x "AVoixHaute" >/dev/null; then
    echo "  $(msg arret_instance)"
    pkill -x "AVoixHaute" || true
    sleep 1
fi

# `rm -rf` sans test préalable : sous `set -e`, un `[ -d … ] && rm` s'évaluant
# à faux vaut un échec et interromprait le script juste avant la copie.
rm -rf "$DESTINATION"
cp -R "$APP_SOURCE" "$DESTINATION"
echo "  $(msg installee_dans)"

# Le fichier de quarantaine ferait afficher un avertissement au premier
# lancement ; l'application vient d'être compilée localement, elle n'a pas
# transité par Internet.
xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true

# --- Helper en ligne de commande -------------------------------------------

mkdir -p "$DOSSIER_HELPERS"
for nom in "${NOMS_HELPER[@]}"; do
    ln -sf "$DESTINATION/Contents/Resources/lire" "$DOSSIER_HELPERS/$nom"
done
echo "  $(msg helper_lie) $DOSSIER_HELPERS/{$(IFS=,; echo "${NOMS_HELPER[*]}")}"

# --- Enregistrement système -------------------------------------------------

"$LSREGISTER" -f "$DESTINATION"
"$PBS" -flush 2>/dev/null || true
echo "  $(msg service_enregistre)"

# --- Lancement à l'ouverture de session ------------------------------------

# L'agent de la 1.x porte l'ancien identifiant : sans ce retrait, launchd
# continuerait de charger une définition pointant sur un bundle qui ne se
# déclare plus sous ce nom.
AGENT_HERITE="$HOME/Library/LaunchAgents/fr.dimitri.AVoixHaute.plist"
VENAIT_DE_LA_1X=false
if [ -f "$AGENT_HERITE" ]; then
    launchctl unload "$AGENT_HERITE" 2>/dev/null || true
    rm -f "$AGENT_HERITE"
    VENAIT_DE_LA_1X=true
    echo "  $(msg ancien_agent_retire)"
fi

if $AVEC_DEMARRAGE; then
    # L'inscription passe par l'application, qui appelle `SMAppService`, et non
    # par un agent posé ici. Les deux mécanismes coexisteraient sans se voir :
    # l'interrupteur des réglages interroge SMAppService et resterait décoché
    # malgré un agent bien installé.
    #
    # SMAppService a deux avantages sur l'agent : l'inscription figure dans
    # Réglages Système → Général → Ouverture, où l'utilisateur peut la retirer,
    # et l'application le sait — un agent désactivé là passerait inaperçu.
    #
    # Un agent hérité d'une version antérieure est retiré plus haut.
    open -b app.avoixhaute.player --args --inscrire-ouverture-session 2>/dev/null || true
    echo "  $(msg demarrage_active)"
fi

# --- Démarrage --------------------------------------------------------------

# `RunAtLoad` a déjà lancé l'application quand l'agent vient d'être chargé :
# un second `open` ne ferait qu'activer l'instance en cours, mais il brouille
# la lecture des messages. On ne lance donc que si rien ne tourne.
if ! pgrep -x "AVoixHaute" >/dev/null; then
    open "$DESTINATION"
fi

# Le premier lancement depuis /Applications demande quelques secondes : macOS
# vérifie la signature et enregistre le bundle avant de rendre la main.
DEMARREE=false
for _ in $(seq 1 10); do
    sleep 1
    if pgrep -x "AVoixHaute" >/dev/null; then
        DEMARREE=true
        break
    fi
done

echo
if $VENAIT_DE_LA_1X; then
    echo "$(msg migration1)"
    echo "$(msg migration2)"
    echo "$(msg migration3)"
    echo "$(msg accessibilite_chemin)"
    echo "$(msg migration4)"
    echo
fi

if $DEMARREE; then
    echo "$(msg installation_finie)"
else
    echo "$(msg installation_sans_demarrage)"
    echo "$(msg consultez)"
fi

echo
echo "$(msg usage)"
echo "  • $(msg usage_menu)"
echo "  • $(msg usage_service)"
echo "  • $(msg usage_raccourci)"
echo "  • $(msg usage_terminal)"
echo
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    echo "$(msg ajouter_path)"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
