use_frameworks!

target 'WSDL2Swift' do
  platform :osx, '10.11'
  pod 'AEXML'
  pod 'Stencil'
  pod 'Commander'
end

target 'iOSWSDL2Swift' do
  platform :ios, '9.0'
  pod 'WSDL2Swift', path: './'

  target 'iOSWSDL2SwiftTests' do
    inherit! :complete

    pod 'JetToTheFuture', '>= 0.4.0-beta.1'
    pod 'Toki', '>= 0.5'
  end
end
