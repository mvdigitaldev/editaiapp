Pod::Spec.new do |s|
  s.name             = 'beauty_mediapipe'
  s.version          = '0.1.0'
  s.summary          = 'MediaPipe Face/Pose bridge for Editai'
  s.description      = 'Flutter plugin for MediaPipe Face Landmarker'
  s.homepage         = 'https://editai.app'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Editai' => 'dev@editai.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '0.10.21'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
