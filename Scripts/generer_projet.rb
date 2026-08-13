#!/usr/bin/env ruby
# frozen_string_literal: true

# Génère Lecteur.xcodeproj à partir de l'arborescence Sources/.
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
CHEMIN_PROJET = RACINE + 'Lecteur.xcodeproj'

IDENTIFIANT_APP = 'fr.dimitri.Lecteur'
VERSION_MIN_MACOS = '14.0'
VERSION_SWIFT = '5.0'

# Réglages communs à toutes les cibles.
REGLAGES_COMMUNS = {
  'MACOSX_DEPLOYMENT_TARGET' => VERSION_MIN_MACOS,
  'SWIFT_VERSION' => VERSION_SWIFT,
  'ALWAYS_SEARCH_USER_PATHS' => 'NO',
  'CLANG_ENABLE_OBJC_ARC' => 'YES',
  'ENABLE_STRICT_OBJC_MSGSEND' => 'YES',
  # Signature ad-hoc : l'autorisation Accessibilité est liée à la signature,
  # une identité stable évite de la redemander à chaque compilation.
  'CODE_SIGN_IDENTITY' => '-',
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

cible_app = projet.new_target(:application, 'Lecteur', :osx, VERSION_MIN_MACOS)

groupe_sources = projet.new_group('Sources', 'Sources')
fichiers_app = []
ajouter_arborescence(groupe_sources, RACINE + 'Sources', fichiers_app)
cible_app.add_file_references(fichiers_app)

cible_app.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_NAME' => 'Lecteur',
    'PRODUCT_BUNDLE_IDENTIFIER' => IDENTIFIANT_APP,
    'INFOPLIST_FILE' => 'Sources/App/Info.plist',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '0.1.0',
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
  cible_tests = projet.new_target(:unit_test_bundle, 'LecteurTests', :osx, VERSION_MIN_MACOS)

  groupe_tests = projet.new_group('Tests', 'Tests')
  fichiers_tests = []
  ajouter_arborescence(groupe_tests, RACINE + 'Tests', fichiers_tests)
  cible_tests.add_file_references(fichiers_tests)

  cible_tests.build_configurations.each do |config|
    config.build_settings.merge!(
      'PRODUCT_NAME' => 'LecteurTests',
      'PRODUCT_BUNDLE_IDENTIFIER' => "#{IDENTIFIANT_APP}.tests",
      'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/Lecteur.app/Contents/MacOS/Lecteur',
      'BUNDLE_LOADER' => '$(TEST_HOST)',
      # Sans Info.plist explicite, la signature du bundle de tests échoue.
      'GENERATE_INFOPLIST_FILE' => 'YES'
    )
  end

  cible_tests.add_dependency(cible_app)
  puts "  cible LecteurTests : #{fichiers_tests.count} fichier(s)"
end

# --- Ressources hors code ---------------------------------------------------

groupe_ressources = projet.new_group('Ressources', 'Ressources')
groupe_ressources.new_reference('Sources/App/Info.plist')

projet.save

puts "  cible Lecteur : #{fichiers_app.count} fichier(s) Swift"
puts "  cible lire    : #{fichiers_cli.count} fichier(s) Swift"
puts "Terminé : #{CHEMIN_PROJET}"
