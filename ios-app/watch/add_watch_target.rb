# מוסיף לפרויקט ה-Xcode את אפליקציית השעון (SetWatch Watch App) ומטמיע אותה באפליקציית האייפון.
# אפשר להריץ שוב ושוב: אם ה-Target כבר קיים, רק מעדכן קבצים והגדרות.
require 'xcodeproj'

ROOT = File.expand_path('../ios/App', __dir__)
PROJ = File.join(ROOT, 'App.xcodeproj')
NAME = 'SetWatch Watch App'
BUNDLE = 'com.setapp.workout.watchkitapp'

project = Xcodeproj::Project.open(PROJ)
app = project.targets.find { |t| t.name == 'App' } or abort('לא נמצא Target בשם App')
team = app.build_configurations.map { |c| c.build_settings['DEVELOPMENT_TEAM'] }.compact.first
team ||= (project.root_object.attributes['TargetAttributes'] || {}).dig(app.uuid, 'DevelopmentTeam')
version = app.build_configurations.map { |c| c.build_settings['MARKETING_VERSION'] }.compact.first || '1.0'

watch = project.targets.find { |t| t.name == NAME }
created = watch.nil?
watch ||= project.new_target(:application, NAME, :watchos, '10.0', nil, :swift)
# Swift מקשר את Foundation לבד. קישור קבוע לנתיב SDK מסוים נשבר בגרסת Xcode אחרת
watch.frameworks_build_phase.files.to_a.each do |bf|
  ref = bf.file_ref
  watch.frameworks_build_phase.remove_build_file(bf)
  ref.remove_from_project if ref && ref.respond_to?(:path) && ref.path.to_s.include?('.sdk/')
end

watch.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE
  s['SDKROOT'] = 'watchos'
  s['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  s['TARGETED_DEVICE_FAMILY'] = '4'
  s['SWIFT_VERSION'] = '5.0'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['INFOPLIST_FILE'] = "#{NAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS'] = "#{NAME}/SetWatch.entitlements"
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = team if team
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['SKIP_INSTALL'] = 'YES'
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  s['ENABLE_PREVIEWS'] = 'YES'
  s.delete('IPHONEOS_DEPLOYMENT_TARGET')
  s.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
  s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
end

# קבצים
group = project.main_group.children.find { |g| g.display_name == NAME } || project.main_group.new_group(NAME, NAME)
dir = File.join(ROOT, NAME)
# קבצים שנמחקו מהתיקייה יוצאים גם מהפרויקט
group.files.to_a.each do |ref|
  next if File.exist?(File.join(dir, ref.path))
  watch.source_build_phase.remove_file_reference(ref)
  ref.remove_from_project
end
Dir.glob(File.join(dir, '*.swift')).sort.each do |f|
  base = File.basename(f)
  ref = group.files.find { |x| x.path == base } || group.new_reference(base)
  watch.source_build_phase.add_file_reference(ref, true)
end
assets = group.files.find { |x| x.path == 'Assets.xcassets' } || group.new_reference('Assets.xcassets')
watch.resources_build_phase.add_file_reference(assets, true)
%w[Info.plist SetWatch.entitlements].each { |f| group.files.find { |x| x.path == f } || group.new_reference(f) }

# הטמעה באפליקציית האייפון
app.add_dependency(watch) unless app.dependencies.any? { |d| d.target == watch }
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Watch Content' }
unless embed
  embed = app.new_copy_files_build_phase('Embed Watch Content')
  embed.dst_subfolder_spec = '16'
  embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
end
unless embed.files_references.include?(watch.product_reference)
  bf = embed.add_file_reference(watch.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeaderOnCopy'] }
end

attrs = (project.root_object.attributes['TargetAttributes'] ||= {})
attrs[watch.uuid] = (attrs[watch.uuid] || {}).merge('CreatedOnToolsVersion' => '16.0')
attrs[watch.uuid]['DevelopmentTeam'] = team if team

project.save

# סכמה להרצה על השעון מתוך Xcode
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(watch, nil, launch_target: true)
scheme.save_as(PROJ, NAME, true)

puts created ? "   ✓ נוצר Target חדש: #{NAME}" : "   ✓ ה-Target כבר קיים, עודכן"
puts "   ✓ Team: #{team || 'לא נמצא (לבחור ב-Xcode)'} | גרסה #{version}"
