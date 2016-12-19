use_frameworks!

target 'WSDL2Swift' do
  pod 'AEXML'
  pod 'Stencil'
  pod 'Commander'
end

target 'iOSWSDL2Swift' do
  pod 'WSDL2Swift', path: './'

  target 'iOSWSDL2SwiftTests' do
    inherit! :search_paths

    pod 'JetToTheFuture'
    pod 'Mockingjay'
    pod 'OHHTTPStubs/NSURLSession', '~> 5.2'
  end
end

