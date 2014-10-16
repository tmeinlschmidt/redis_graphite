#!/usr/bin/env ruby

require 'yaml'
require 'ostruct'
require 'rubygems'
require 'bundler/setup'

require 'graphite-api'
require 'graphite-api/core_ext/numeric'

module ConfigFile

  def self.load_yaml(object)
    return case object
    when Hash
      object = object.clone
      object.each do |key, value|
      object[key] = load_yaml(value)
    end
    OpenStruct.new(object)
    when Array
      object = object.clone
      object.map! { |i| load_yaml(i) }
    else
      object
    end
  end

end

module Collector

  class Poll

    def initialize
      settings = ConfigFile.load_yaml(
        YAML.load_file(File.dirname(Pathname.new(__FILE__).realpath)+'/config.yml'))

      graphite = settings.graphite
      raise 'Missing graphite config' if graphite.nil?

      params = { graphite: "#{graphite.host}:#{graphite.port}", prefix: [graphite.prefix]}

      hosts = settings.redis.servers#.map(&:marshall_dump)
      hosts.each do |host|
        puts "#{host.server} #{host.host}:#{host.port} #{host.databases}"
      end
      data_to_fetch = settings.metrics

      @graphite = GraphiteAPI.new( params )
      c = @graphite

      Zscheduler.every(settings.general.poll) do
        begin

          hosts.each do |host|
            data_to_process = {}
            databases = {}
            data = `#{settings.redis.cli} -h #{host.host} -p #{host.port} info`.each_line do |line|
              next if line =~ /^#/
              key, val = line.chomp.split(/:/)
              if hosts[0].databases.include?(key)
                databases[key] = Hash[*val.split(/,/).map{|v| v.split(/=/)}.flatten]
              else
                data_to_process[key] = val
              end
            end
            data_to_fetch.each do |section|
              section.variables.each do |var|
                c.metrics("#{host.server}.#{section.section}.#{var}" => data_to_process[var])
              end
            end
            databases.each do |db, stats|
              stats.each do |key, value|
                c.metrics("#{host.server}.database.#{db}.#{key}" => value)
              end
            end
          end

        rescue Exception => e
          raise 'Exception'
        end
      end
      Zscheduler.join
    end

  end

  service = Collector::Poll.new

end
