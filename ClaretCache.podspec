Pod::Spec.new do |s|
  s.name         = 'ClaretCache'
  s.summary      = 'High performance cache framework for iOS.'
  s.version      = '0.0.1'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'iTeaTime(技术清谈)' => 'luohanchenyilong@163.com' }
  s.social_media_url = 'https://github.com/iteatimeteam/ClaretCache'
  s.homepage     = 'https://github.com/iteatimeteam/ClaretCache'
  s.platform     = :ios, '6.0'
  s.ios.deployment_target = '6.0'
  s.source       = { :git => 'https://github.com/iteatimeteam/ClaretCache.git', :tag => s.version.to_s }
  
  s.requires_arc = true
  s.source_files = 'ClaretCache/*.{h,m}'
  s.public_header_files = 'ClaretCache/*.{h}'
  
  s.libraries = 'sqlite3'
  s.frameworks = 'UIKit', 'CoreFoundation', 'QuartzCore' 

end
