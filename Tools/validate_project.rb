require 'xcodeproj'
require 'rexml/document'
require 'json'
require 'digest'

root = File.expand_path('..', __dir__)
path = File.join(root, 'PersonalFitness.xcodeproj')
project = Xcodeproj::Project.open(path)
raise 'Unexpected targets' unless project.targets.map(&:name).sort == %w[PersonalFitness PersonalFitnessTests PersonalFitnessUITests]
project.targets.each do |target|
  expected_paths = Dir.glob(File.join(root, target.name, '**', '*.swift')).map { |path| File.expand_path(path) }.sort
  sources = target.source_build_phase.files_references
  raise "Wrong membership in #{target.name}" unless sources.map { |ref| ref.real_path.to_s }.sort == expected_paths
  sources.each { |ref| raise "Missing #{ref.real_path}" unless File.file?(ref.real_path) }
  target.build_configurations.each do |config|
    raise 'Wrong deployment' unless config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] == '17.0'
    raise 'Missing configuration' unless File.file?(config.base_configuration_reference.real_path)
  end
end
app = project.targets.find { |target| target.name == 'PersonalFitness' }
raise 'Missing assets' unless app.resources_build_phase.files_references.any? { |ref| File.directory?(ref.real_path) && ref.path.end_with?('.xcassets') }
raise 'Missing offline catalog resource folder' unless app.resources_build_phase.files_references.any? { |ref| ref.path == 'Catalogs' && ref.last_known_file_type == 'folder' && File.directory?(ref.real_path) }
catalog_path = File.join(root, 'PersonalFitness/Resources/Catalogs')
report = JSON.parse(File.read(File.join(catalog_path, 'generation-report.json')))
report.fetch('files').each do |name, details|
  file = File.join(catalog_path, name)
  raise "Invalid catalog bytes: #{name}" unless File.size(file) == details.fetch('bytes') && Digest::SHA256.file(file).hexdigest == details.fetch('sha256')
end
raise 'Missing source notices' unless %w[NOTICE.txt EXERCISE_LICENSE.txt].all? { |name| File.file?(File.join(catalog_path, name)) }
raise 'Missing Charts' unless app.frameworks_build_phase.files_references.any? { |ref| ref.path == 'System/Library/Frameworks/Charts.framework' && ref.source_tree == 'SDKROOT' }
raise 'Missing HealthKit' unless app.frameworks_build_phase.files_references.any? { |ref| ref.path == 'System/Library/Frameworks/HealthKit.framework' && ref.source_tree == 'SDKROOT' }
scheme = REXML::Document.new(File.read(File.join(path, 'xcshareddata/xcschemes/PersonalFitness.xcscheme')))
raise 'Missing test scheme membership' unless REXML::XPath.first(scheme, '//TestableReference/BuildableReference').attributes['BlueprintIdentifier'] == project.targets.find { |target| target.name == 'PersonalFitnessTests' }.uuid
test_ids = REXML::XPath.match(scheme, '//TestableReference/BuildableReference').map { |ref| ref.attributes['BlueprintIdentifier'] }
expected_test_ids = project.targets.reject { |target| target == app }.map(&:uuid)
raise 'Missing test target in shared scheme' unless test_ids.sort == expected_test_ids.sort
['LaunchAction', 'ProfileAction'].each do |action|
  runnable = REXML::XPath.first(scheme, "//#{action}/BuildableProductRunnable/BuildableReference")
  raise "Missing runnable for #{action}" unless runnable && runnable.attributes['BlueprintIdentifier'] == app.uuid
end
puts 'PASS: targets, configuration, all source references, assets, HealthKit linkage, and shared scheme Test/Run/Profile actions.'
puts 'Compilation and device behavior are not checked by this script.'
