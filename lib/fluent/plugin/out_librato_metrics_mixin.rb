#
# fluent-plugin-librato-metrics
#
# Copyright (C) 2011 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module Fluent


module LibratoMetricsOutput::MetricsMixin
  include Configurable

  def initialize
    super
    @metrics = []
  end

  attr_reader :metrics

  config_param :default_value_key, :string, :default => nil
  config_param :default_count_key, :string, :default => nil
  config_param :default_type, :string, :default => nil
  config_param :match_key, :string, :default => nil

  def configure(conf)
    super

    defaults = {
      'value_key' => @default_value_key,
      'count_key' => @default_count_key,
      'type' => @default_type,
    }

    conf.elements.select {|e|
      e.name == 'metrics'
    }.each {|e|
      defaults.each_pair {|k,v| e[k] = v if v != nil }
      add_metrics(e, e.arg)
    }

    if mk = @match_key
      @match_key_proc = Proc.new {|tag,record| record[mk] }
    else
      @match_key_proc = Proc.new {|tag,record| tag }
    end
  end

  def add_metrics(conf, pattern)
    m = Metrics.new(pattern)
    m.configure(conf)
    @metrics << m
  end

  class Data
    def initialize(metrics)
      @metrics = metrics
      @name = metrics.name
      @each_keys = metrics.each_keys
      @value_key = metrics.value_key
      @count_key = metrics.count_key
    end

    attr_reader :metrics
    attr_reader :name, :each_keys, :value_key, :count_key
    attr_accessor :keys, :value, :count
  end

  class Metrics
    include Configurable

    def initialize(pattern)
      super()
      if pattern && !pattern.empty?
        @pattern = MatchPattern.create(pattern)
      else
        @pattern = nil
      end
    end

    attr_reader :pattern

    config_param :name, :string

    config_param :each_key, :string, :default => nil
    attr_reader :each_keys  # parsed 'each_key'

    config_param :value_key, :string, :default => nil
    config_param :default_value, :string, :default => nil

    config_param :count_key, :string, :default => nil

    config_param :type, :default => :int do |val|
      case val
      when 'int'
        :int
      when 'float'
        :float
      else
        raise ConfigError, "unexpected 'type' parameter on metrics: expected int or float"
      end
    end

    config_param :match_key, :string, :default => nil

    attr_accessor :key_proc
    attr_accessor :value_proc
    attr_accessor :count_proc
    attr_accessor :match_proc

    def configure(conf)
      super

      if @each_key
        @each_keys = @each_key.split(',').map {|e| e.strip }
        @key_proc = create_combined_key_proc(@each_keys)
      else
        @each_keys = []
        use_keys = [@name]
        @key_proc = Proc.new {|record| use_keys }
      end

      case @type
      when :int
        if vk = @value_key
          dv = @default_value ? @default_value.to_i : nil
          @value_proc = Proc.new {|record| val = record[vk]; val ? val.to_i : dv }
        else
          dv = @default_value ? @default_value.to_i : 1
          @value_proc = Proc.new {|record| dv }
        end
      when :float
        if vk = @value_key
          dv = @default_value ? @default_value.to_f : nil
          @value_proc = Proc.new {|record| val = record[vk]; val ? val.to_f : dv }
        else
          dv = @default_value ? @default_value.to_f : 1.0
          @value_proc = Proc.new {|record| dv }
        end
      end

      if ck = @count_key
        @count_proc = Proc.new {|record| val = record[ck].to_i; val == 0 ? 1 : val }
      else
        @count_proc = Proc.new {|record| 1 }
      end

      if pt = @pattern
        @match_proc = Proc.new {|tag| pt.match(tag) }
      else
        @match_proc = Proc.new {|tag| true }
      end

      @data = Data.new(self)
    end

    def create_combined_key_proc(keys)
      if keys.length == 1
        key = keys[0]
        Proc.new {|record|
          val = record[key]
          val ? [val] : nil
        }
      else
        Proc.new {|record|
          keys.map {|key|
            val = record[key]
            break nil unless val
            val
          }
        }
      end
    end

    def evaluate(tag, time, record)
      return nil unless @match_proc.call(tag)

      data = @data

      keys = data.keys = @key_proc.call(record)
      return nil unless keys

      value = data.value = @value_proc.call(record)
      return nil unless value

      data.count = @count_proc.call(record)

      return data
    end
  end

  def each_metrics(tag, time, record, &block)
    mk = @match_key_proc.call(tag, record)
    return [] unless mk
    @metrics.map {|m|
      data = m.evaluate(mk, time, record)
      next unless data
      block.call(data)
    }
  end
end


## Example
#
#class MetricsOutput < Output
#  Plugin.register_output('metrics', self)
#
#  include MetricsMixin
#
#  def initialize
#    super
#  end
#
#  config_param :tag, :string, :default => nil
#  config_param :tag_prefix, :string, :default => nil
#
#  def configure(conf)
#    super
#
#    if constant_tag = @tag
#      @tag_proc = Proc.new {|name,tag| constant_tag }
#    elsif tag_prefix = @tag_prefix
#      @tag_proc = Proc.new {|name,tag| "#{tag_prefix}.#{name}.#{tag}" }
#    else
#      @tag_proc = Proc.new {|name,tag| "#{name}.#{tag}" }
#    end
#  end
#
#  def emit(tag, es, chain)
#    es.each {|time,record|
#      each_metrics(tag, time, record) {|m|
#        otag = @tag_proc.call(m.name, tag)
#        orecord = {
#          'name' => m.name,
#          'key' => m.keys.join(','),
#          'keys' => m.keys,
#          'key_hash' => Hash[ m.each_keys.zip(m.keys) ],
#          'value' => m.value,
#          'value_hash' => {m.value_key => m.value},
#          'count' => m.count,
#        }
#        Engine.emit(otag, time, orecord)
#      }
#    }
#    chain.next
#  end
#end


## Example
#
#require 'metrics'
#
#class ExampleAggregationOutput < BufferedOutput
#  Plugin.register_output('aggregation_example', self)
#
#  include MetricsMixin
#
#  def initialize
#    super
#  end
#
#  def configure(conf)
#    super
#
#    # do something ...
#  end
#
#  def format(tag, time, record)
#    # call each_metrics(tag, time,record):
#    each_metrics(tag, time, record) {|m|
#      # 'm.name' is always avaiable
#      name = m.name
#
#      # 'keys' is an array of record value if each_key option is specified.
#      # otherwise, 'keys' is same as [m.name]
#      key = m.keys.join(',')
#
#      if !m.each_keys.empty?
#        # you can create Hash of the record using 'm.each_keys'
#        key_hash = Hash[ m.each_keys.zip(m.keys) ]
#      else
#        # m.keys is [name]
#      end
#
#      if m.value_key
#        # value is parsed record value
#        value_hash = {m.value_key => m.value}
#      else
#        # m.value is 1 or 1.0
#      end
#
#      if m.count_key
#        # value is parsed record value
#        count_hash = {m.count_key => m.count}
#      else
#        # count is 1
#      end
#
#      # ...
#    }
#  end
#end


end
