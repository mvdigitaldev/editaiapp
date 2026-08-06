#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pe_sdk_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pe_sdk_flutter'
  s.version          = '0.6.0'
  s.summary          = 'A new Flutter project.'
  s.description      = <<-DESC
A new Flutter project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # 1.4.0 foi publicado contra um BanubaDesignSystem que a Banuba nunca liberou
  # (símbolos Colors.surface* ausentes na 1.0.3) e crasha no launch. 1.4.1 fecha
  # os símbolos com DesignSystem 1.0.3 + BanubaUtilities 1.53.1.
  s.dependency 'BanubaPhotoEditorSDK', '1.4.1'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
