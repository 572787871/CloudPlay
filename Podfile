platform :ios, '17.0'
install! 'cocoapods', :deterministic_uuids => true
project 'CloudPlay.xcodeproj'
target 'CloudPlay' do
  pod 'MobileVLCKit', '3.7.5'
  target 'CloudPlayTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
