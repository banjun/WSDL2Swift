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

LEGACY_SWIFT_PODS = %w(Stencil PathKit Commander)
def set_legacy_swift(installer)
  UI.warn "#{LEGACY_SWIFT_PODS.count} pods are marked as legacy swift: #{LEGACY_SWIFT_PODS}"

  installer.pods_project.targets.select {|t| LEGACY_SWIFT_PODS.include? t.name}.each do |target|
    pod_target = installer.pod_targets.find {|t| t.name == target.name}

    unless pod_target.uses_swift?
      UI.warn "#{target.name} does not use Swift."
      next
    end

    pushed_version = pod_target.root_spec.attributes_hash['pushed_with_swift_version'].to_i
    if pushed_version >= 4
      UI.warn "#{target.name} has pushed_with_swift_version #{pushed_version}."
    end

    target.build_configurations.each do |config|
      if pushed_version == 4
        config.build_settings['SWIFT_VERSION'] = '4.0' # Commander has swift version 4.0 that falls back to 3
      else
        config.build_settings['SWIFT_VERSION'] = '3.0'
      end
    end
  end
end

post_install do |installer|
  set_legacy_swift installer
end

