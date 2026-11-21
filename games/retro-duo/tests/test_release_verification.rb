# Offline API contract tests: delayed indexing, existing access, rejected assignment,
# invalid processing, and a misconfigured group must never report release success.
require 'openssl'
require 'net/http'
require 'json'
require 'tmpdir'
require 'stringio'

module ReleaseFixture
  class << self
    attr_accessor :mode, :assigned, :build_reads, :posts
    def reset(mode)
      self.mode, self.assigned, self.build_reads, self.posts = mode, false, 0, 0
    end
    def response(message)
      path = URI(message.path).path.sub('/v1/', '')
      data = case path
      when 'apps' then [{'id'=>'app'}]
      when 'betaGroups/603ae54c-1b85-4dc9-b780-b38468202e4e'
        {'attributes'=>{'isInternalGroup'=>mode != :external_group}}
      when 'betaGroups/603ae54c-1b85-4dc9-b780-b38468202e4e/app' then {'id'=>mode == :wrong_app ? 'other' : 'app'}
      when 'builds'
        self.build_reads += 1
        if mode == :unindexed || (mode == :delayed && build_reads <= 8)
          []
        else
          [{'id'=>'build', 'attributes'=>{'processingState'=>mode == :invalid ? 'INVALID' : (mode == :processing ? 'PROCESSING' : 'VALID')}}]
        end
      when 'betaGroups/603ae54c-1b85-4dc9-b780-b38468202e4e/relationships/builds'
        if message.is_a?(Net::HTTP::Post)
          self.posts += 1
          raise 'Wrong assignment payload' unless JSON.parse(message.body) == {'data'=>[{'type'=>'builds','id'=>'build'}]}
          return make(403, {}) if mode == :denied
          self.assigned = mode != :not_in_group
          return make(204, nil)
        end
        assigned || mode == :existing ? [{'id'=>'build','type'=>'builds'}] : []
      when 'builds/build/buildBetaDetail' then {'attributes'=>{'internalBuildState'=>'IN_BETA_TESTING'}}
      else raise "Unexpected API request: #{path}"
      end
      make(200, {'data'=>data})
    end
    def make(code, body)
      klass = {200=>Net::HTTPOK, 204=>Net::HTTPNoContent, 403=>Net::HTTPForbidden}.fetch(code)
      response = klass.new('1.1', code.to_s, 'Fixture')
      response.body = body.nil? ? '' : JSON.generate(body)
      response.instance_variable_set(:@read, true)
      response
    end
  end
end
module Net
  class HTTP
    def self.start(*)
      connection = Object.new
      def connection.request(message); ReleaseFixture.response(message); end
      yield connection
    end
  end
end
module Kernel
  def sleep(*); end
end

script = File.expand_path('../ios/verify-testflight.rb', __dir__)
Dir.mktmpdir do |directory|
  key_path = File.join(directory, 'test.p8')
  File.write(key_path, OpenSSL::PKey::EC.generate('prime256v1').to_pem)
  ENV.update('ASC_KEY_ID'=>'FIXTURE', 'ASC_ISSUER_ID'=>'fixture', 'RD_BUNDLE'=>'com.ctnetworkstudios.retroduo',
             'GITHUB_RUN_NUMBER'=>'99', 'GITHUB_RUN_ATTEMPT'=>'1', 'RUNNER_TEMP'=>directory,
             'GITHUB_STEP_SUMMARY'=>File.join(directory, 'summary'))
  ARGV.replace([key_path])
  [:delayed, :existing, :denied, :invalid, :external_group, :wrong_app, :unindexed, :processing, :not_in_group].each do |mode|
    ReleaseFixture.reset(mode)
    status_file = File.join(directory, 'retro-duo-testflight-status.json')
    File.delete(status_file) if File.exist?(status_file)
    saved_out, saved_err = $stdout, $stderr
    $stdout, $stderr = StringIO.new, StringIO.new
    code = nil
    begin
      load script
    rescue SystemExit => error
      code = error.status
    ensure
      $stdout, $stderr = saved_out, saved_err
    end
    success = [:delayed, :existing].include?(mode)
    raise "Unexpected exit for #{mode}: #{code}" unless success ? code == 0 : code != 0
    if success
      result = JSON.parse(File.read(status_file))
      raise 'Tester access must be verified' unless result['tester_access_verified'] && result['internal_build_state'] == 'IN_BETA_TESTING'
      raise 'Existing assignment must be idempotent' if mode == :existing && ReleaseFixture.posts != 0
      raise 'Delayed build must receive exactly one assignment' if mode == :delayed && ReleaseFixture.posts != 1
    end
    puts "PASS #{mode}"
  end
end
