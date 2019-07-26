Pod::Spec.new do |s|
  s.name         = 'ClaretCache'
  s.summary      = 'High performance cache framework for iOS.'
  s.version      = '0.0.1'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'iTeaTime(技术清谈)' => 'luohanchenyilong@163.com' }
  s.social_media_url = 'https://github.com/iteatimeteam/ClaretCache'
  s.homepage     = 'https://github.com/iteatimeteam/ClaretCache'
  s.source       = { :git => 'https://github.com/iteatimeteam/ClaretCache.git', :tag => s.version.to_s }
  
  s.platform     = :ios, '10.0'
  s.ios.deployment_target = '10.0'

  s.swift_version = '5.0'

  s.source_files = 'Sources/ClaretCache/*.swift'
  
  s.libraries = 'sqlite3'
  s.frameworks = 'UIKit', 'CoreFoundation', 'QuartzCore' 

end
