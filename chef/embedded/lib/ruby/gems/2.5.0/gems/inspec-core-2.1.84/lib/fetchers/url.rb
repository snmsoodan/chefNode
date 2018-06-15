# encoding: utf-8
# author: Dominik Richter
# author: Christoph Hartmann

require 'uri'
require 'openssl'
require 'tempfile'
require 'open-uri'

module Fetchers
  class Url < Inspec.fetcher(1)
    MIME_TYPES = {
      'application/x-zip-compressed' => '.zip',
      'application/zip' => '.zip',
      'application/x-gzip' => '.tar.gz',
      'application/gzip' => '.tar.gz',
    }.freeze

    name 'url'
    priority 200

    def self.resolve(target, opts = {})
      if target.is_a?(Hash) && target.key?(:url)
        resolve_from_string(target[:url], opts)
      elsif target.is_a?(String)
        resolve_from_string(target, opts)
      end
    end

    def self.resolve_from_string(target, opts)
      uri = URI.parse(target)
      return nil if uri.nil? or uri.scheme.nil?
      return nil unless %{ http https }.include? uri.scheme
      target = transform(target)
      new(target, opts)
    rescue URI::Error
      nil
    end

    # Transforms a browser github/bitbucket url to github/bitbucket tar url
    # We distinguish between three different Github/Bitbucket URL types:
    #  - Master URL
    #  - Branch URL
    #  - Commit URL
    #
    # master url:
    # https://github.com/nathenharvey/tmp_compliance_profile/ is transformed to
    # https://github.com/nathenharvey/tmp_compliance_profile/archive/master.tar.gz
    # https://bitbucket.org/username/repo is transformed to
    # https://bitbucket.org/username/repo/get/master.tar.gz
    #
    # branch:
    # https://github.com/hardening-io/tests-os-hardening/tree/2.0 is transformed to
    # https://github.com/hardening-io/tests-os-hardening/archive/2.0.tar.gz
    # https://bitbucket.org/username/repo/branch/branchname is transformed to
    # https://bitbucket.org/username/repo/get/newbranch.tar.gz
    #
    # commit:
    # https://github.com/hardening-io/tests-os-hardening/tree/48bd4388ddffde68badd83aefa654e7af3231876
    # is transformed to
    # https://github.com/hardening-io/tests-os-hardening/archive/48bd4388ddffde68badd83aefa654e7af3231876.tar.gz
    # https://bitbucket.org/username/repo/commits/95ce1f83d5bbe9eec34c5973f6894617e8d6d8cc is transformed to
    # https://bitbucket.org/username/repo/get/95ce1f83d5bbe9eec34c5973f6894617e8d6d8cc.tar.gz

    GITHUB_URL_REGEX = %r{^https?://(www\.)?github\.com/(?<user>[\w-]+)/(?<repo>[\w-]+)(\.git)?(/)?$}
    GITHUB_URL_WITH_TREE_REGEX = %r{^https?://(www\.)?github\.com/(?<user>[\w-]+)/(?<repo>[\w-]+)/tree/(?<commit>[\w\.]+)(/)?$}
    BITBUCKET_URL_REGEX = %r{^https?://(www\.)?bitbucket\.org/(?<user>[\w-]+)/(?<repo>[\w-]+)(\.git)?(/)?$}
    BITBUCKET_URL_BRANCH_REGEX = %r{^https?://(www\.)?bitbucket\.org/(?<user>[\w-]+)/(?<repo>[\w-]+)/branch/(?<branch>[\w\.]+)(/)?$}
    BITBUCKET_URL_COMMIT_REGEX = %r{^https?://(www\.)?bitbucket\.org/(?<user>[\w-]+)/(?<repo>[\w-]+)/commits/(?<commit>[\w\.]+)(/)?$}

    def self.transform(target)
      transformed_target = if m = GITHUB_URL_REGEX.match(target) # rubocop:disable Lint/AssignmentInCondition
                             "https://github.com/#{m[:user]}/#{m[:repo]}/archive/master.tar.gz"
                           elsif m = GITHUB_URL_WITH_TREE_REGEX.match(target) # rubocop:disable Lint/AssignmentInCondition
                             "https://github.com/#{m[:user]}/#{m[:repo]}/archive/#{m[:commit]}.tar.gz"
                           elsif m = BITBUCKET_URL_REGEX.match(target) # rubocop:disable Lint/AssignmentInCondition
                             "https://bitbucket.org/#{m[:user]}/#{m[:repo]}/get/master.tar.gz"
                           elsif m = BITBUCKET_URL_BRANCH_REGEX.match(target) # rubocop:disable Lint/AssignmentInCondition
                             "https://bitbucket.org/#{m[:user]}/#{m[:repo]}/get/#{m[:branch]}.tar.gz"
                           elsif m = BITBUCKET_URL_COMMIT_REGEX.match(target) # rubocop:disable Lint/AssignmentInCondition
                             "https://bitbucket.org/#{m[:user]}/#{m[:repo]}/get/#{m[:commit]}.tar.gz"
                           end

      if transformed_target
        Inspec::Log.warn("URL target #{target} transformed to #{transformed_target}. Consider using the git fetcher")
        transformed_target
      else
        target
      end
    end

    attr_reader :files, :archive_path

    def initialize(url, opts)
      @target = url
      @insecure = opts['insecure']
      @token = opts['token']
      @config = opts
      @archive_path = nil
      @temp_archive_path = nil
    end

    def fetch(path)
      @archive_path ||= download_archive(path)
    end

    def resolved_source
      @resolved_source ||= { url: @target, sha256: sha256 }
    end

    def cache_key
      @archive_shasum ||= sha256
    end

    def to_s
      @target
    end

    private

    def sha256
      file = @archive_path || temp_archive_path
      OpenSSL::Digest::SHA256.digest(File.read(file)).unpack('H*')[0]
    end

    def file_type_from_remote(remote)
      content_type = remote.meta['content-type']
      file_type = MIME_TYPES[content_type]

      if file_type.nil?
        Inspec::Log.warn("Unrecognized content type: #{content_type}. Assuming tar.gz")
        file_type = '.tar.gz'
      end

      file_type
    end

    def temp_archive_path
      @temp_archive_path ||= if @config['server_type'] == 'automate2'
                               download_automate2_archive_to_temp
                             else
                               download_archive_to_temp
                             end
    end

    def download_automate2_archive_to_temp
      return @temp_archive_path if !@temp_archive_path.nil?

      Inspec::Log.debug("Fetching URL: #{@target}")
      json = {
        owner: @config['profile'][0],
        name: @config['profile'][1],
        version: @config['profile'][2],
      }.to_json

      uri = URI.parse(@target)
      opts = http_opts
      opts[:use_ssl] = uri.scheme == 'https'

      if @insecure
        opts[:verify_mode] = OpenSSL::SSL::VERIFY_NONE
      else
        opts[:verify_mode] = OpenSSL::SSL::VERIFY_PEER
      end

      req = Net::HTTP::Post.new(uri)
      opts.each do |key, value|
        req.add_field(key, value)
      end
      req.body = json
      res = Net::HTTP.start(uri.host, uri.port, opts) { |http|
        http.request(req)
      }

      @archive_type = '.tar.gz'
      archive = Tempfile.new(['inspec-dl-', @archive_type])
      archive.binmode
      archive.write(res.body)
      archive.rewind
      archive.close
      Inspec::Log.debug("Archive stored at temporary location: #{archive.path}")
      @temp_archive_path = archive.path
    end

    # Downloads archive to temporary file with side effect :( of setting @archive_type
    def download_archive_to_temp
      return @temp_archive_path if !@temp_archive_path.nil?
      Inspec::Log.debug("Fetching URL: #{@target}")
      remote = open(@target, http_opts)
      @archive_type = file_type_from_remote(remote) # side effect :(
      archive = Tempfile.new(['inspec-dl-', @archive_type])
      archive.binmode
      archive.write(remote.read)
      archive.rewind
      archive.close
      Inspec::Log.debug("Archive stored at temporary location: #{archive.path}")
      @temp_archive_path = archive.path
    end

    def download_archive(path)
      temp_archive_path
      final_path = "#{path}#{@archive_type}"
      FileUtils.mkdir_p(File.dirname(final_path))
      FileUtils.mv(temp_archive_path, final_path)
      Inspec::Log.debug("Fetched archive moved to: #{final_path}")
      @temp_archive_path = nil
      final_path
    end

    def http_opts
      opts = {}
      opts[:ssl_verify_mode] = OpenSSL::SSL::VERIFY_NONE if @insecure

      if @config['server_type'] =~ /automate/
        opts['chef-delivery-enterprise'] = @config['automate']['ent']
        if @config['automate']['token_type'] == 'dctoken'
          opts['x-data-collector-token'] = @config['token']
        else
          opts['chef-delivery-user'] = @config['user']
          opts['chef-delivery-token'] = @config['token']
        end
      elsif @token
        opts['Authorization'] = "Bearer #{@token}"
      end

      # Do not send any headers that have nil values.
      # Net::HTTP does not gracefully handle this situation.
      check_for_missing_values!(opts)

      opts
    end

    def check_for_missing_values!(opts)
      keys_missing_values = opts.keys.delete_if do |k|
        if opts[k].nil?
          false
        elsif opts[k].respond_to?(:empty?) && opts[k].empty?
          false
        else
          true
        end
      end
      raise 'Unable to fetch profile - the following HTTP headers have no value: ' \
        "#{keys_missing_values.join(', ')}" unless keys_missing_values.empty?
    end
  end
end
