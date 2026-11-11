require 'xcodeproj'

root = File.expand_path('..', __dir__)
path = File.join(root, 'PersonalFitness.xcodeproj')
abort 'Project already exists; refusing to overwrite it.' if File.exist?(path)
project = Xcodeproj::Project.new(path)
project.root_object.attributes['LastUpgradeCheck'] = '1600'
app = project.new_target(:application, 'PersonalFitness', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'PersonalFitnessTests', :ios, '17.0')
ui = project.new_target(:ui_test_bundle, 'PersonalFitnessUITests', :ios, '17.0')
ui.add_dependency(app)
tests.add_dependency(app)
config_ref = project.main_group.new_file('Configuration/PersonalFitness.xcconfig')

# Preserve on-disk logical folders in the project navigator.
def source_groups(project, root, folder, target)
  group = project.main_group.new_group(folder, folder)
  Dir.glob(File.join(root, folder, '**', '*.swift')).sort.each do |file|
    relative = file.delete_prefix(File.join(root, folder) + '/')
    parts = relative.split('/')
    leaf = parts.pop
    parent = parts.reduce(group) { |current, part| current.groups.find { |g| g.path == part } || current.new_group(part, part) }
    target.source_build_phase.add_file_reference(parent.new_file(leaf))
  end
  group
end
app_group = source_groups(project, root, 'PersonalFitness', app)
source_groups(project, root, 'PersonalFitnessTests', tests)
source_groups(project, root, 'PersonalFitnessUITests', ui)
resources = app_group.new_group('Resources', 'Resources')
app.resources_build_phase.add_file_reference(resources.new_file('Assets.xcassets'))
catalogs = resources.new_file('Catalogs')
catalogs.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(catalogs)
resources.new_file('Info.plist')
resources.new_file('PersonalFitness.entitlements')
app.add_system_framework('HealthKit')
app.add_system_framework('Charts')

[app, tests, ui].each do |target|
  target.build_configurations.each do |config|
    config.base_configuration_reference = config_ref
    config.build_settings.merge!({
      'SWIFT_VERSION' => '5.0',
      'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
      'TARGETED_DEVICE_FAMILY' => '1',
      'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
      'SUPPORTS_MACCATALYST' => 'NO',
      'CODE_SIGN_STYLE' => 'Automatic',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'SWIFT_EMIT_LOC_STRINGS' => 'YES'
    })
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => '$(APP_BUNDLE_IDENTIFIER)',
    'INFOPLIST_FILE' => 'PersonalFitness/Resources/Info.plist',
    'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'PersonalFitness reads the resting and active energy, steps, workouts, body weight, and optional sleep, HRV SDNN and resting-heart-rate data you choose to share for energy balance, fitness trends and transparent wellness estimates on this iPhone.',
    'CODE_SIGN_ENTITLEMENTS' => 'PersonalFitness/Resources/PersonalFitness.entitlements',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'MARKETING_VERSION' => '0.1.0',
    'CURRENT_PROJECT_VERSION' => '1'
  })
end
tests.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => '$(APP_BUNDLE_IDENTIFIER).Tests',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/PersonalFitness.app/PersonalFitness',
    'BUNDLE_LOADER' => '$(TEST_HOST)'
  })
end
ui.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => '$(APP_BUNDLE_IDENTIFIER).UITests',
    'TEST_TARGET_NAME' => 'PersonalFitness'
  })
end
project.root_object.attributes['TargetAttributes'] = {
  app.uuid => {'SystemCapabilities' => {'com.apple.HealthKit' => {'enabled' => 1}}},
  tests.uuid => {'TestTargetID' => app.uuid},
  ui.uuid => {'TestTargetID' => app.uuid}
}
project.files.each do |reference|
  next unless reference.path.end_with?('.framework')
  reference.path = "System/Library/Frameworks/#{File.basename(reference.path)}"
  reference.source_tree = 'SDKROOT'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests, launch_target: true)
scheme.add_build_target(ui, false)
scheme.add_test_target(ui)
scheme.save_as(path, 'PersonalFitness', true)

# Round-trip through the generator's parser and check membership and references.
loaded = Xcodeproj::Project.open(path)
raise 'Wrong targets' unless loaded.targets.map(&:name).sort == %w[PersonalFitness PersonalFitnessTests PersonalFitnessUITests]
loaded.targets.each do |target|
  target.source_build_phase.files_references.each do |ref|
    raise "Missing source #{ref.real_path}" unless File.file?(ref.real_path)
  end
end
raise 'Missing shared scheme' unless File.file?(File.join(path, 'xcshareddata/xcschemes/PersonalFitness.xcscheme'))
puts "Generated and structurally validated #{path}"
