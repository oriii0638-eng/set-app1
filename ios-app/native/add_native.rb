# מוסיף לפרויקט ה-Xcode: הפלאגין של סט לאפליקציה, וה-Target של הווידג'טים (SetWidgets) עם מסך הנעילה.
# אפשר להריץ שוב ושוב.
require 'xcodeproj'

ROOT = File.expand_path('../ios/App', __dir__)
PROJ = File.join(ROOT, 'App.xcodeproj')
WNAME = 'SetWidgets'

project = Xcodeproj::Project.open(PROJ)
app = project.targets.find { |t| t.name == 'App' } or abort('לא נמצא Target בשם App')
team = app.build_configurations.map { |c| c.build_settings['DEVELOPMENT_TEAM'] }.compact.first
team ||= (project.root_object.attributes['TargetAttributes'] || {}).dig(app.uuid, 'DevelopmentTeam')
version = app.build_configurations.map { |c| c.build_settings['MARKETING_VERSION'] }.compact.first || '1.0'
family = app.build_configurations.map { |c| c.build_settings['TARGETED_DEVICE_FAMILY'] }.compact.first || '1,2'

def add_src(group, target, name)
  ref = group.files.find { |x| x.path == name } || group.new_reference(name)
  target.source_build_phase.add_file_reference(ref, true)
  ref
end

# 1. הפלאגין בתוך האפליקציה
app_group = project.main_group.children.find { |g| g.display_name == 'App' } or abort('לא נמצאה קבוצת App')
%w[SetNativePlugin.swift SetBridgeViewController.swift].each { |f| add_src(app_group, app, f) }

# 2. קובץ משותף לאפליקציה ולווידג'ט
shared = project.main_group.children.find { |g| g.display_name == 'Shared' } || project.main_group.new_group('Shared', 'Shared')
shared_ref = add_src(shared, app, 'SetActivityAttributes.swift')

# 3. ה-Target של הווידג'טים
w = project.targets.find { |t| t.name == WNAME }
created = w.nil?
w ||= project.new_target(:app_extension, WNAME, :ios, '17.0', nil, :swift)
w.frameworks_build_phase.files.to_a.each do |bf|
  ref = bf.file_ref
  w.frameworks_build_phase.remove_build_file(bf)
  ref.remove_from_project if ref && ref.respond_to?(:path) && ref.path.to_s.include?('.sdk/')
end
w.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.setapp.workout.widgets'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = family
  s['SWIFT_VERSION'] = '5.0'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['INFOPLIST_FILE'] = "#{WNAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS'] = "#{WNAME}/#{WNAME}.entitlements"
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = team if team
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
  s.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
  s.delete('ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME')
end
wgroup = project.main_group.children.find { |g| g.display_name == WNAME } || project.main_group.new_group(WNAME, WNAME)
Dir.glob(File.join(ROOT, WNAME, '*.swift')).sort.each { |f| add_src(wgroup, w, File.basename(f)) }
%w[Info.plist SetWidgets.entitlements].each { |f| wgroup.files.find { |x| x.path == f } || wgroup.new_reference(f) }
w.source_build_phase.add_file_reference(shared_ref, true)

# 4. הטמעה באפליקציה
app.add_dependency(w) unless app.dependencies.any? { |d| d.target == w }
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13'
  embed.dst_path = ''
end
unless embed.files_references.include?(w.product_reference)
  bf = embed.add_file_reference(w.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeaderOnCopy'] }
end

attrs = (project.root_object.attributes['TargetAttributes'] ||= {})
attrs[w.uuid] = (attrs[w.uuid] || {}).merge('CreatedOnToolsVersion' => '16.0')
attrs[w.uuid]['DevelopmentTeam'] = team if team

project.save
puts created ? "   ✓ נוצר Target חדש: #{WNAME}" : "   ✓ ה-Target #{WNAME} כבר קיים, עודכן"
