require 'xcodeproj'
require 'fileutils'
require 'pathname'
root = File.expand_path('..', __dir__)
project_path = File.join(root, 'CloudPlay.xcodeproj')
abort '工程已存在；请在修改生成器后明确传入 --regenerate，避免覆盖手工修改。' if File.exist?(project_path) && !ARGV.include?('--regenerate')
project = Xcodeproj::Project.new(project_path)
app = project.new_target(:application, 'CloudPlay', :ios, '17.0')
share = project.new_target(:app_extension, 'CloudPlayShare', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'CloudPlayTests', :ios, '17.0')
ui_tests = project.new_target(:ui_test_bundle, 'CloudPlayUITests', :ios, '17.0')
ui_tests.add_dependency(app)
tests.add_dependency(app)
app.add_dependency(share)
project.build_configurations.each do |c|
 c.build_settings['SWIFT_VERSION'] = '5.0'
 c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
 c.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
 c.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'targeted'
 c.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
end
[[app,'App'],[share,'ShareExtension'],[tests,'Tests'],[ui_tests,'UITests']].each do |target,directory|
 group = project.main_group.new_group(directory, directory)
 Dir.glob(File.join(root, directory, '**', '*.swift')).sort.each do |path|
   relative=Pathname.new(path).relative_path_from(Pathname.new(File.join(root,directory))).to_s
   ref=group.new_file(relative)
   target.source_build_phase.add_file_reference(ref)
 end
 target.build_configurations.each do |c|
   c.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
   c.build_settings['SWIFT_VERSION'] = '5.0'
   c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
   c.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
   c.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
   c.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
 end
end
resources=project.main_group.new_group('Resources', 'App/Resources')
['Assets.xcassets','ThirdPartyNotices.txt','LGPL-2.1.txt'].each do |name|
 app.resources_build_phase.add_file_reference(resources.new_file(name))
end
app.build_configurations.each do |c|
 c.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'xyz.cloudplay.personal'
 c.build_settings['INFOPLIST_FILE'] = 'App/Resources/Info.plist'
 c.build_settings['MARKETING_VERSION'] = '1.0.0'
 c.build_settings['CURRENT_PROJECT_VERSION'] = '1'
 c.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)','@executable_path/Frameworks']
end
share.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'xyz.cloudplay.personal.share'
 c.build_settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
 c.build_settings['SKIP_INSTALL'] = 'YES'
 c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
 c.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']
end
tests.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'xyz.cloudplay.personal.tests'
 c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
 c.build_settings.delete('INFOPLIST_FILE')
 c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/CloudPlay.app/CloudPlay'
 c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
 c.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']
end
ui_tests.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'xyz.cloudplay.personal.uitests'
 c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
 c.build_settings['TEST_TARGET_NAME'] = 'CloudPlay'
end
embed=app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec='13'
ref=embed.add_file_reference(share.product_reference)
ref.settings={'ATTRIBUTES'=>['RemoveHeadersOnCopy']}
project.save
scheme=Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui_tests)
scheme.save_as(project_path,'CloudPlay',true)
puts 'Generated CloudPlay.xcodeproj with app, share extension and executable tests.'
