#!/usr/bin/env ruby
# frozen_string_literal: true

# Génère AVoixHaute.xcodeproj à partir de l'arborescence Sources/.
#
# Ce script est la source de vérité de la structure du projet : le .xcodeproj
# est versionné pour rester ouvrable dans Xcode, mais il peut être régénéré à
# tout moment par :
#
#     ruby Scripts/generer_projet.rb
#
# Les fichiers Swift ajoutés dans Sources/ sont pris en compte automatiquement,
# sans intervention dans Xcode.

require 'xcodeproj'
require 'pathname'

RACINE = Pathname.new(__dir__).parent.expand_path
CHEMIN_PROJET = RACINE + 'AVoixHaute.xcodeproj'

IDENTIFIANT_APP = 'fr.dimitri.AVoixHaute'
VERSION_MIN_MACOS = '14.0'
VERSION_SWIFT = '5.0'

# Version affichée par l'application. Le workflow de publication la dérive du
# tag Git, de sorte qu'un tag v1.2.0 produise une application se déclarant en
# 1.2.0 — sans quoi le numéro figé dans ce script mentirait à l'utilisateur.
VERSION_APP = ENV.fetch('LECTEUR_VERSION', '1.0.0')

# Numéro de compilation : le numéro d'exécution du workflow, ou 1 en local.
VERSION_COMPILATION = ENV.fetch('LECTEUR_COMPILATION', '1')

# Signature : une identité de développement stable évite de réaccorder
# l'autorisation Accessibilité après chaque compilation. Ces valeurs peuvent
# être remplacées par les variables d'environnement du même nom, et retomber
# sur une signature ad-hoc ('-') sur une machine sans certificat.
#
# L'identité est désignée par son empreinte SHA-1 : les noms génériques comme
# « Apple Development » sont résolus par Xcode en « Mac Development », qui ne
# correspond à aucun certificat installé ici.
IDENTITE_SIGNATURE = ENV.fetch(
  'LECTEUR_IDENTITE',
  '3D909274B7703CD03F2B29D33E6A9757817B3143'
)
EQUIPE_DEVELOPPEMENT = ENV.fetch('LECTEUR_EQUIPE', '')

# Réglages communs à toutes les cibles.
REGLAGES_COMMUNS = {
  'MACOSX_DEPLOYMENT_TARGET' => VERSION_MIN_MACOS,
  'SWIFT_VERSION' => VERSION_SWIFT,
  'ALWAYS_SEARCH_USER_PATHS' => 'NO',
  'CLANG_ENABLE_OBJC_ARC' => 'YES',
  'ENABLE_STRICT_OBJC_MSGSEND' => 'YES',
  # L'autorisation Accessibilité est liée à la signature : avec une signature
  # ad-hoc, chaque compilation produit une identité différente et macOS révoque
  # l'autorisation. Une identité de développement stable évite d'avoir à la
  # redonner. Sans certificat disponible, régler IDENTITE_SIGNATURE sur '-'.
  'CODE_SIGN_IDENTITY' => IDENTITE_SIGNATURE,
  'CODE_SIGN_STYLE' => 'Manual',
  'DEVELOPMENT_TEAM' => EQUIPE_DEVELOPPEMENT,
  'CODE_SIGNING_REQUIRED' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'YES',
  # Le bac à sable est volontairement désactivé : Process (say), le socket Unix
  # hors conteneur et CGEventPost y sont interdits.
  'ENABLE_APP_SANDBOX' => 'NO',
  'ENABLE_HARDENED_RUNTIME' => 'NO'
}.freeze

puts "Génération de #{CHEMIN_PROJET.basename}…"

CHEMIN_PROJET.rmtree if CHEMIN_PROJET.exist?
projet = Xcodeproj::Project.new(CHEMIN_PROJET)

# --- Configurations de compilation -----------------------------------------

projet.build_configurations.each do |config|
  config.build_settings.merge!(REGLAGES_COMMUNS)
  if config.name == 'Debug'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
    config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
  else
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
    config.build_settings['SWIFT_COMPILATION_MODE'] = 'wholemodule'
  end
end

# --- Aides ------------------------------------------------------------------

# Reproduit l'arborescence d'un dossier dans le navigateur de projet, et
# renvoie les fichiers .swift trouvés.
def ajouter_arborescence(groupe_parent, dossier, fichiers_collectes)
  dossier.children.sort.each do |entree|
    if entree.directory?
      sous_groupe = groupe_parent.new_group(entree.basename.to_s, entree.basename.to_s)
      ajouter_arborescence(sous_groupe, entree, fichiers_collectes)
    elsif entree.extname == '.swift'
      reference = groupe_parent.new_reference(entree.basename.to_s)
      fichiers_collectes << reference
    end
  end
end

# --- Cible application ------------------------------------------------------

cible_app = projet.new_target(:application, 'AVoixHaute', :osx, VERSION_MIN_MACOS)

groupe_sources = projet.new_group('Sources', 'Sources')
fichiers_app = []
ajouter_arborescence(groupe_sources, RACINE + 'Sources', fichiers_app)
cible_app.add_file_references(fichiers_app)

cible_app.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_NAME' => 'AVoixHaute',
    'PRODUCT_BUNDLE_IDENTIFIER' => IDENTIFIANT_APP,
    'INFOPLIST_FILE' => 'Sources/App/Info.plist',
    'CURRENT_PROJECT_VERSION' => VERSION_COMPILATION,
    'MARKETING_VERSION' => VERSION_APP,
    # main.swift impose le mode script : pas d'attribut @main.
    'SWIFT_MAIN_FILE_IS_TOP_LEVEL_CODE' => 'YES',
    'COMBINE_HIDPI_IMAGES' => 'YES'
  )
end

# --- Cible outil en ligne de commande --------------------------------------

cible_cli = projet.new_target(:command_line_tool, 'lire', :osx, VERSION_MIN_MACOS)

groupe_cli = projet.new_group('SourcesCLI', 'SourcesCLI')
fichiers_cli = []
ajouter_arborescence(groupe_cli, RACINE + 'SourcesCLI', fichiers_cli)
cible_cli.add_file_references(fichiers_cli)

cible_cli.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_NAME' => 'lire',
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{IDENTIFIANT_APP}.cli",
    'SKIP_INSTALL' => 'YES'
  )
end

# Le binaire CLI est embarqué dans le bundle de l'app, d'où il sera lié vers
# ~/.local/bin par Scripts/installer_helper.sh.
cible_app.add_dependency(cible_cli)
phase_copie = cible_app.new_copy_files_build_phase('Copier le helper CLI')
phase_copie.symbol_dst_subfolder_spec = :resources
phase_copie.add_file_reference(cible_cli.product_reference)

# --- Cible de tests ---------------------------------------------------------

if (RACINE + 'Tests').children.any? { |f| f.extname == '.swift' }
  cible_tests = projet.new_target(:unit_test_bundle, 'AVoixHauteTests', :osx, VERSION_MIN_MACOS)

  groupe_tests = projet.new_group('Tests', 'Tests')
  fichiers_tests = []
  ajouter_arborescence(groupe_tests, RACINE + 'Tests', fichiers_tests)
  cible_tests.add_file_references(fichiers_tests)

  cible_tests.build_configurations.each do |config|
    config.build_settings.merge!(
      'PRODUCT_NAME' => 'AVoixHauteTests',
      'PRODUCT_BUNDLE_IDENTIFIER' => "#{IDENTIFIANT_APP}.tests",
      'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/AVoixHaute.app/Contents/MacOS/AVoixHaute',
      'BUNDLE_LOADER' => '$(TEST_HOST)',
      # Sans Info.plist explicite, la signature du bundle de tests échoue.
      'GENERATE_INFOPLIST_FILE' => 'YES'
    )
  end

  cible_tests.add_dependency(cible_app)
  puts "  cible AVoixHauteTests : #{fichiers_tests.count} fichier(s)"
end

# --- Ressources hors code ---------------------------------------------------

# Le chemin du groupe étant déjà « Ressources », les références qu'il contient
# sont relatives à ce dossier.
groupe_ressources = projet.new_group('Ressources', 'Ressources')

# L'icône est copiée dans le bundle ; CFBundleIconFile la désigne par son nom.
icone = RACINE + 'Ressources/AVoixHaute.icns'
if icone.exist?
  reference_icone = groupe_ressources.new_reference('AVoixHaute.icns')
  cible_app.resources_build_phase.add_file_reference(reference_icone)
  puts '  icône incluse'
end

# Catalogues de traduction. Chaque dossier .lproj est ajouté tel quel : Xcode
# reproduit l'arborescence dans le bundle, et macOS choisit le catalogue selon
# les préférences de langue du système.
langues = Dir.glob("#{RACINE}/Ressources/*.lproj").map { |d| File.basename(d, '.lproj') }.sort
langues.each do |langue|
  %w[Localizable.strings InfoPlist.strings].each do |fichier|
    chemin = RACINE + "Ressources/#{langue}.lproj/#{fichier}"
    next unless chemin.exist?
    reference = groupe_ressources.new_reference("#{langue}.lproj/#{fichier}")
    cible_app.resources_build_phase.add_file_reference(reference)
  end
end

unless langues.empty?
  # Sans cette liste, macOS n'annonce qu'une seule langue et ignore les autres
  # catalogues, même présents dans le bundle.
  projet.root_object.known_regions = (langues + ['Base']).uniq
  puts "  traductions : #{langues.join(', ')}"
end

projet.save

puts "  cible AVoixHaute : #{fichiers_app.count} fichier(s) Swift"
puts "  cible lire    : #{fichiers_cli.count} fichier(s) Swift"
puts "Terminé : #{CHEMIN_PROJET}"
