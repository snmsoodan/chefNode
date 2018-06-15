# encoding: utf-8
# Copyright 2015 Dominik Richter
# author: Dominik Richter
# author: Christoph Hartmann

require 'logger'
require 'thor'
require 'json'
require 'pp'
require 'utils/json_log'
require 'utils/latest_version'
require 'inspec/base_cli'
require 'inspec/plugins'
require 'inspec/runner_mock'
require 'inspec/env_printer'
require 'inspec/schema'

class Inspec::InspecCLI < Inspec::BaseCLI
  class_option :log_level, aliases: :l, type: :string,
               desc: 'Set the log level: info (default), debug, warn, error'

  class_option :log_location, type: :string,
               desc: 'Location to send diagnostic log messages to. (default: STDOUT or STDERR)'

  class_option :diagnose, type: :boolean,
    desc: 'Show diagnostics (versions, configurations)'

  desc 'json PATH', 'read all tests in PATH and generate a JSON summary'
  option :output, aliases: :o, type: :string,
    desc: 'Save the created profile to a path'
  option :controls, type: :array,
    desc: 'A list of controls to include. Ignore all other tests.'
  profile_options
  def json(target)
    o = opts.dup
    diagnose(o)
    o[:ignore_supports] = true
    o[:backend] = Inspec::Backend.create(target: 'mock://')
    o[:check_mode] = true

    profile = Inspec::Profile.for_target(target, o)
    info = profile.info
    # add in inspec version
    info[:generator] = {
      name: 'inspec',
      version: Inspec::VERSION,
    }
    dst = o[:output].to_s
    if dst.empty?
      puts JSON.dump(info)
    else
      if File.exist? dst
        puts "----> updating #{dst}"
      else
        puts "----> creating #{dst}"
      end
      fdst = File.expand_path(dst)
      File.write(fdst, JSON.dump(info))
    end
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'check PATH', 'verify all tests at the specified PATH'
  option :format, type: :string
  profile_options
  def check(path) # rubocop:disable Metrics/AbcSize
    o = opts.dup
    diagnose(o)
    o[:ignore_supports] = true # we check for integrity only
    o[:backend] = Inspec::Backend.create(target: 'mock://')
    o[:check_mode] = true

    # run check
    profile = Inspec::Profile.for_target(path, o)
    result = profile.check

    if o['format'] == 'json'
      puts JSON.generate(result)
    else
      %w{location profile controls timestamp valid}.each do |item|
        puts format('%-12s %s', item.to_s.capitalize + ':',
                    mark_text(result[:summary][item.to_sym]))
      end
      puts

      if result[:errors].empty? and result[:warnings].empty?
        puts 'No errors or warnings'
      else
        red    = "\033[31m"
        yellow = "\033[33m"
        rst    = "\033[0m"

        item_msg = lambda { |item|
          pos = [item[:file], item[:line], item[:column]].compact.join(':')
          pos.empty? ? item[:msg] : pos + ': ' + item[:msg]
        }
        result[:errors].each do |item|
          puts "#{red}  ✖  #{item_msg.call(item)}#{rst}"
        end
        result[:warnings].each do |item|
          puts "#{yellow}  !  #{item_msg.call(item)}#{rst}"
        end

        puts
        puts format('Summary:     %s%d errors%s, %s%d warnings%s',
                    red, result[:errors].length, rst,
                    yellow, result[:warnings].length, rst)
      end
    end
    exit 1 unless result[:summary][:valid]
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'vendor PATH', 'Download all dependencies and generate a lockfile in a `vendor` directory'
  option :overwrite, type: :boolean, default: false,
    desc: 'Overwrite existing vendored dependencies and lockfile.'
  def vendor(path = nil)
    o = opts.dup
    vendor_deps(path, o)
  end

  desc 'archive PATH', 'archive a profile to tar.gz (default) or zip'
  profile_options
  option :output, aliases: :o, type: :string,
    desc: 'Save the archive to a path'
  option :zip, type: :boolean, default: false,
    desc: 'Generates a zip archive.'
  option :tar, type: :boolean, default: false,
    desc: 'Generates a tar.gz archive.'
  option :overwrite, type: :boolean, default: false,
    desc: 'Overwrite existing archive.'
  option :ignore_errors, type: :boolean, default: false,
    desc: 'Ignore profile warnings.'
  def archive(path)
    o = opts.dup
    diagnose(o)

    o[:logger] = Logger.new(STDOUT)
    o[:logger].level = get_log_level(o.log_level)
    o[:backend] = Inspec::Backend.create(target: 'mock://')

    profile = Inspec::Profile.for_target(path, o)
    result = profile.check

    if result && !o[:ignore_errors] == false
      o[:logger].info 'Profile check failed. Please fix the profile before generating an archive.'
      return exit 1
    end

    # generate archive
    exit 1 unless profile.archive(o)
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'exec PATHS', 'run all test files at the specified PATH.'
  exec_options
  def exec(*targets)
    o = opts(:exec).dup
    diagnose(o)
    configure_logger(o)

    runner = Inspec::Runner.new(o)
    targets.each { |target| runner.add_target(target) }

    exit runner.run
  rescue ArgumentError, RuntimeError, Train::UserError => e
    $stderr.puts e.message
    exit 1
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'detect', 'detect the target OS'
  target_options
  option :format, type: :string
  def detect
    o = opts(:detect).dup
    o[:command] = 'platform.params'
    (_, res) = run_command(o)
    if o['format'] == 'json'
      puts res.to_json
    else
      headline('Platform Details')
      puts Inspec::BaseCLI.detect(params: res, indent: 0, color: 36)
    end
  rescue ArgumentError, RuntimeError, Train::UserError => e
    $stderr.puts e.message
    exit 1
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'shell', 'open an interactive debugging shell'
  target_options
  option :command, aliases: :c,
    desc: 'A single command string to run instead of launching the shell'
  option :format, type: :string, default: nil, hide: true,
    desc: '[DEPRECATED] Please use --reporter - this will be removed in InSpec 3.0'
  option :reporter, type: :array,
    banner: 'one two:/output/file/path',
    desc: 'Enable one or more output reporters: cli, documentation, html, progress, json, json-min, json-rspec, junit'
  option :depends, type: :array, default: [],
    desc: 'A space-delimited list of local folders containing profiles whose libraries and resources will be loaded into the new shell'
  def shell_func
    o = opts(:shell).dup
    diagnose(o)
    o[:debug_shell] = true

    log_device = suppress_log_output?(o) ? nil : STDOUT
    o[:logger] = Logger.new(log_device)
    o[:logger].level = get_log_level(o.log_level)

    if o[:command].nil?
      runner = Inspec::Runner.new(o)
      return Inspec::Shell.new(runner).start
    end

    run_type, res = run_command(o)
    exit res unless run_type == :ruby_eval

    # No InSpec tests - just print evaluation output.
    res = (res.respond_to?(:to_json) ? res.to_json : JSON.dump(res)) if o['reporter']&.keys&.include?('json')
    puts res
    exit 0
  rescue RuntimeError, Train::UserError => e
    $stderr.puts e.message
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'env', 'Output shell-appropriate completion configuration'
  def env(shell = nil)
    p = Inspec::EnvPrinter.new(self.class, shell)
    p.print_and_exit!
  rescue StandardError => e
    pretty_handle_exception(e)
  end

  desc 'schema NAME', 'print the JSON schema', hide: true
  def schema(name)
    puts Inspec::Schema.json(name)
  rescue StandardError => e
    puts e
    puts "Valid schemas are #{Inspec::Schema.names.join(', ')}"
  end

  desc 'version', 'prints the version of this tool'
  option :format, type: :string
  def version
    if opts['format'] == 'json'
      v = { version: Inspec::VERSION }
      puts v.to_json
    else
      puts Inspec::VERSION
      # display outdated version
      latest = LatestInSpecVersion.new.latest
      if Gem::Version.new(Inspec::VERSION) < Gem::Version.new(latest)
        puts "\nYour version of InSpec is out of date! The latest version is #{latest}."
      end
    end
  end
  map %w{-v --version} => :version

  private

  def run_command(opts)
    runner = Inspec::Runner.new(opts)
    res = runner.eval_with_virtual_profile(opts[:command])
    runner.load

    return :ruby_eval, res if runner.all_rules.empty?
    return :rspec_run, runner.run_tests # rubocop:disable Style/RedundantReturn
  end
end

# Load all plugins on startup
ctl = Inspec::PluginCtl.new
ctl.list.each { |x| ctl.load(x) }

# load CLI plugins before the Inspec CLI has been started
Inspec::Plugins::CLI.subcommands.each { |_subcommand, params|
  Inspec::InspecCLI.register(
    params[:klass],
    params[:subcommand_name],
    params[:usage],
    params[:description],
    params[:options],
  )
}
