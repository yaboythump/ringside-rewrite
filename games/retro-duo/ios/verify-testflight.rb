# Verify processing AND access for the existing internal tester group.
# No credentials, new testers, public links, or App Review submissions are created.
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

key = OpenSSL::PKey.read(File.binread(ARGV.fetch(0)))
encode = ->(value) { Base64.urlsafe_encode64(value, padding: false) }
request = lambda do |method, path, params = {}, data = nil, may_fail = false|
  now = Time.now.to_i
  header = encode.call(JSON.generate(alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'))
  claims = encode.call(JSON.generate(iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 300, aud: 'appstoreconnect-v1'))
  input = "#{header}.#{claims}"
  signature = OpenSSL::ASN1.decode(key.sign('SHA256', input)).value.map { |p| p.value.to_s(2).rjust(32, "\x00") }.join
  uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?
  message = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  message['Authorization'] = "Bearer #{input}.#{encode.call(signature)}"
  if data
    message['Content-Type'] = 'application/json'
    message.body = JSON.generate(data)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.request(message) }
  unless response.is_a?(Net::HTTPSuccess)
    abort("App Store Connect #{method.upcase} #{path} failed: HTTP #{response.code}") unless may_fail
    puts "App Store Connect #{method.upcase} #{path} answered HTTP #{response.code}; checking access again."
    return nil
  end
  response.code == '204' ? {} : JSON.parse(response.body)
end

app = request.call(:get, 'apps', {'filter[bundleId]'=>ENV.fetch('RD_BUNDLE')}).fetch('data').first
abort('App record unavailable during upload confirmation.') unless app
# This is the already authorized Retro Duo Internal group, not all app testers.
group_id = '603ae54c-1b85-4dc9-b780-b38468202e4e'
group = request.call(:get, "betaGroups/#{group_id}").fetch('data')
abort('Configured tester group is not internal.') unless group.fetch('attributes').fetch('isInternalGroup')
group_app = request.call(:get, "betaGroups/#{group_id}/app").fetch('data')
abort('Configured tester group belongs to a different app.') unless group_app.fetch('id') == app.fetch('id')
version = "#{ENV.fetch('GITHUB_RUN_NUMBER')}.#{ENV.fetch('GITHUB_RUN_ATTEMPT')}"
status_file = File.join(ENV.fetch('RUNNER_TEMP'), 'retro-duo-testflight-status.json')
result = {bundle: ENV.fetch('RD_BUNDLE'), version: version, group_id: group_id, tester_access_verified: false}
assigned = false
# Apple may index an uploaded binary after several minutes. Refresh JWT per call.
45.times do |attempt|
  build = request.call(:get, 'builds', {'filter[app]'=>app.fetch('id'), 'filter[version]'=>version, 'limit'=>'5'}).fetch('data').first
  if build
    state = build.fetch('attributes').fetch('processingState')
    result.merge!(build_id: build.fetch('id'), processing_state: state)
    File.write(status_file, JSON.pretty_generate(result))
    puts "App Store Connect build #{version}: #{state} (check #{attempt + 1}/45)"
    abort('Apple marked the uploaded build invalid.') if %w[INVALID FAILED].include?(state)
    if state == 'VALID'
      members = request.call(:get, "betaGroups/#{group_id}/relationships/builds", {'limit'=>'200'})
      accessible = members.fetch('data').any? { |item| item.fetch('id') == build.fetch('id') }
      unless accessible || assigned
        # Apple can add a new build to the internal group on its own between the check above
        # and this request, and then answers 404; the checks below decide either way.
        if request.call(:post, "betaGroups/#{group_id}/relationships/builds", {}, {'data'=>[{'type'=>'builds', 'id'=>build.fetch('id')}]}, true)
          puts "Assigned build #{version} to the existing Retro Duo Internal group."
        end
        assigned = true
        members = request.call(:get, "betaGroups/#{group_id}/relationships/builds", {'limit'=>'200'})
        accessible = members.fetch('data').any? { |item| item.fetch('id') == build.fetch('id') }
      end
      detail = request.call(:get, "builds/#{build.fetch('id')}/buildBetaDetail").fetch('data').fetch('attributes')
      beta = detail.fetch('internalBuildState')
      result.merge!(internal_build_state: beta, tester_access_verified: accessible)
      File.write(status_file, JSON.pretty_generate(result))
      if accessible && %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].include?(beta)
        puts "Confirmed TestFlight build #{version}: #{state}; #{beta}; existing tester group access verified."
        File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') { |f| f.puts("Retro Duo **#{version}**: **#{state}**, **#{beta}**, **tester group access verified**.") }
        exit(0)
      end
      abort("TestFlight testing is blocked: #{beta}") if %w[MISSING_EXPORT_COMPLIANCE PROCESSING_EXCEPTION IN_EXPORT_COMPLIANCE_REVIEW EXPIRED].include?(beta)
    end
  else
    puts "Uploaded build #{version} is not indexed yet (check #{attempt + 1}/45)."
  end
  sleep(20) if attempt < 44
end
File.write(status_file, JSON.pretty_generate(result))
abort('Upload completed, but Apple processing or tester access is still unconfirmed after 15 minutes. Do not report this build as available.')
