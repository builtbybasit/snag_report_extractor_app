#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint directory_bookmarks.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'directory_bookmarks'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter plugin for handling directory bookmarks'
  s.description      = <<-DESC
A Flutter plugin for handling directory bookmarks and file operations with security-scoped bookmarks.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Sources live in the Swift Package Manager layout; the podspec references the
  # same files so both SPM and CocoaPods builds use one source of truth.
  s.source_files     = 'directory_bookmarks/Sources/directory_bookmarks/**/*.swift'
  s.dependency 'FlutterMacOS'

  s.platform         = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end