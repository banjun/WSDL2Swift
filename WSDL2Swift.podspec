Pod::Spec.new do |s|
  s.name         = "WSDL2Swift"
  s.version      = "0.6.0"
  s.summary      = "Swift alternative to WSDL2ObjC making a SOAP request & parsing its response as defined in WSDL"
  s.description  = <<-DESC
  Swift alternative to WSDL2ObjC making a SOAP request & parsing its response as defined in WSDL.
  generate WSDL+(ServiceName).swift SOAP client by executing WSDL2Swift with WSDL and XSD xml files.
                   DESC
  s.homepage     = "https://github.com/banjun/WSDL2Swift"
  s.license      = "MIT"
  s.author             = { "BAN Jun" => "banjun@gmail.com" }
  s.social_media_url   = "https://twitter.com/banjun"
  s.ios.deployment_target = "9.0"
  s.osx.deployment_target = "10.11"
  s.source       = { :git => "https://github.com/banjun/WSDL2Swift.git", :tag => "#{s.version}" }
  s.source_files  = 'WSDL2Swift.swift', 'XMLParserObjCSwiftBridge.*'
  s.dependency "AEXML"
  s.dependency "BrightFutures"
  s.dependency "ISO8601"
end
