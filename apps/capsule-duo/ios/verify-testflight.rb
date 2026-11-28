# Confirms this exact upload in App Store Connect. Never prints authentication data.
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'
encode = ->(value) { Base64.urlsafe_encode64(value, padding: false) }
now = Time.now.to_i
header = encode.call(JSON.generate(alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'))
claims = encode.call(JSON.generate(iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 600, aud: 'appstoreconnect-v1'))
input = "#{header}.#{claims}"
key = OpenSSL::PKey.read(File.binread(ARGV.fetch(0)))
signature = OpenSSL::ASN1.decode(key.sign('SHA256', input)).value.map { |p| p.value.to_s(2).rjust(32, "\x00") }.join
token = "#{input}.#{encode.call(signature)}"
get = lambda do |path, params|
  uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
  uri.query = URI.encode_www_form(params)
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
  abort("App Store Connect confirmation failed: HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body).fetch('data')
end
app = get.call('apps', {'filter[bundleId]'=>ENV.fetch('CD_BUNDLE')}).first
abort('App record unavailable during upload confirmation.') unless app
version = "#{ENV.fetch('GITHUB_RUN_NUMBER')}.#{ENV.fetch('GITHUB_RUN_ATTEMPT')}"
result = nil
15.times do |attempt|
  build = get.call('builds', {'filter[app]'=>app.fetch('id'), 'filter[version]'=>version, 'limit'=>'5'}).first
  if build
    status = build.fetch('attributes').fetch('processingState')
    result = {bundle: ENV.fetch('CD_BUNDLE'), version: version, build_id: build.fetch('id'), processing_state: status}
    abort('Apple marked the uploaded build invalid.') if %w[INVALID FAILED].include?(status)
    if status == 'VALID'
      details = get.call("builds/#{build.fetch('id')}/buildBetaDetail", {})
      result[:internal_build_state] = details.fetch('attributes').fetch('internalBuildState')
      result[:internal_available] = result[:internal_build_state] == 'IN_BETA_TESTING'
    end
    File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'capsule-duo-testflight-status.json'), JSON.pretty_generate(result))
    puts "Confirmed App Store Connect build #{version}: #{status}; internal testing: #{result[:internal_build_state] || 'processing'}"
    if status == 'VALID' && result[:internal_available]
      File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') { |f| f.puts("Dear Tomorrow build **#{version}**: Apple processing **VALID**, internal TestFlight **IN_BETA_TESTING**.") }
      exit(0)
    end
  end
  sleep(20) if attempt < 14
end
if result && result[:processing_state] == 'VALID'
  puts "Apple processing completed; internal availability is not yet confirmed (#{result[:internal_build_state]})."
  File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') { |f| f.puts("Dear Tomorrow build **#{version}** processed successfully. Internal state: **#{result[:internal_build_state]}**; tester availability remains unconfirmed.") }
  exit(0)
end
abort('Upload returned, but Apple processing has not completed. TestFlight availability is unconfirmed.')
