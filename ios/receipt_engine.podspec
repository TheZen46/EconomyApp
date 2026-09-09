Pod::Spec.new do |s|
  s.name             = 'receipt_engine'
  s.version          = '1.0.0'
  s.summary          = 'High-performance on-device VLM receipt scanning and inference engine'
  s.description      = <<-DESC
Native C++ inference and image preprocessing engine accelerated with SIMD, OpenMP, Metal, and Accelerate.
                       DESC
  s.homepage         = 'https://github.com/taidy/receipt_engine'
  s.license          = { :type => 'MIT', :text => 'Copyright (c) 2026 tAIdy' }
  s.author           = { 'tAIdy Team' => 'team@taidy.com' }
  s.source           = { :path => '.' }
  s.source_files     = '../native/src/**/*.{h,hpp,c,cpp}'
  s.public_header_files = '../native/src/**/*.h'
  
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'
  
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-O3 -ffast-math -DGGML_USE_METAL=1',
  }
  
  s.frameworks = 'Metal', 'Accelerate', 'Foundation', 'LocalAuthentication'
  s.libraries = 'c++'
end
