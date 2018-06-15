# encoding: utf-8
# copyright: 2015, Vulcano Security GmbH

module Inspec::Resources
  class Cmd < Inspec.resource(1)
    name 'command'
    supports platform: 'unix'
    supports platform: 'windows'
    desc 'Use the command InSpec audit resource to test an arbitrary command that is run on the system.'
    example "
      describe command('ls -al /') do
        its('stdout') { should match /bin/ }
        its('stderr') { should eq '' }
        its('exit_status') { should eq 0 }
      end

      command('ls -al /').exist? will return false. Existence of command should be checked this way.
      describe command('ls') do
        it { should exist }
      end
    "

    attr_reader :command

    def initialize(cmd)
      if cmd.nil?
        raise 'InSpec `command` was called with `nil` as the argument. This is not supported. Please provide a valid command instead.'
      end
      @command = cmd
    end

    def result
      @result ||= inspec.backend.run_command(@command)
    end

    def stdout
      result.stdout
    end

    def stderr
      result.stderr
    end

    def exit_status
      result.exit_status.to_i
    end

    def exist? # rubocop:disable Metrics/AbcSize
      # silent for mock resources
      return false if inspec.os.name.nil? || inspec.os.name == 'mock'

      if inspec.os.linux?
        res = if inspec.platform.name == 'alpine'
                inspec.backend.run_command("which \"#{@command}\"")
              else
                inspec.backend.run_command("bash -c 'type \"#{@command}\"'")
              end
      elsif inspec.os.windows?
        res = inspec.backend.run_command("Get-Command \"#{@command}\"")
      elsif inspec.os.unix?
        res = inspec.backend.run_command("type \"#{@command}\"")
      else
        warn "`command(#{@command}).exist?` is not supported on your OS: #{inspec.os[:name]}"
        return false
      end
      res.exit_status.to_i == 0
    end

    def to_s
      "Command #{@command}"
    end
  end
end
