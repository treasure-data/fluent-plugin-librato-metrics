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


class LibratoMetricsOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('librato_metrics', self)

  require 'net/http'
  require "#{File.dirname(__FILE__)}/out_librato_metrics_mixin"
  include MetricsMixin

  config_param :user, :string
  config_param :token, :string
  config_param :source, :string, :default => nil

  def initialize
    super
  end

  def configure(conf)
    super
  end

  def format(tag, time, record)
    out = ''.force_encoding('ASCII-8BIT')
    each_metrics(tag, time, record) {|d|
      name = d.name
      if d.each_keys.empty?
        key = name
      else
        key = "#{name}.#{d.keys.join('.')}"
      end
      partitioned_time = time / 60 * 60
      [key, partitioned_time, d.value*d.count].to_msgpack(out)
    }
    out
  end

  def write(chunk)
    counters = {}  #=> {partitioned_time => {name => CounterAggregator}}
    gauges = {}    #=> {partitioned_time => {name => GaugeAggregator}}

    chunk.msgpack_each {|key,partitioned_time,value|
      if m = /^counter\.(.*)$/.match(key)
        name = m[1]
        ((counters[partitioned_time] ||= {})[name] ||= CounterAggregator.new).add(value)
      elsif m = /^gauge\.(.*)$/.match(key)
        name = m[1]
        ((gauges[partitioned_time] ||= {})[name] ||= GaugeAggregator.new).add(value)
      else
        name = key
        ((gauges[partitioned_time] ||= {})[name] ||= GaugeAggregator.new).add(value)
      end
    }

    #http = Net::HTTP.new('metrics-api.librato.com', 80)
    http = Net::HTTP.new('metrics-api.librato.com', 443)
    http.use_ssl = true
    #http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # TODO verify
    http.cert_store = OpenSSL::X509::Store.new
    header = {}

    begin
      {'counters'=>counters, 'gauges'=>gauges}.each_pair {|type,partitions|
        partitions.each_pair {|partitioned_time,name_aggrs|
          req = Net::HTTP::Post.new('/v1/metrics', header)
          req.basic_auth @user, @token

          params = {
            'measure_time' => partitioned_time.to_s,
          }
          params['source'] = @source if @source

          name_aggrs.each_with_index {|(name,aggr),i|
            params["#{type}[#{i}][name]"] = name
            params["#{type}[#{i}][value]"] = aggr.get.to_s
          }

          $log.trace { "librato metrics: #{params.inspect}" }
          req.set_form_data(params)
          res = http.request(req)

          # TODO error handling
          if res.code != "200"
            $log.warn "librato_metrics: #{res.code}: #{res.body}"
          end
        }
      }
    ensure
      http.finish if http.started?
    end
  end


  # max(value) aggregator
  class CounterAggregator
    def initialize
      @value = 0
    end

    def add(value)
      @value = value if @value < value
    end

    def get
      # librato metrics's counter only supports integer:
      # 'invalid value for Integer(): "0.06268015"'
      @value.to_i
    end
  end

  # avg(value) aggregator
  class GaugeAggregator
    def initialize
      @value = 0
      @num = 0
    end

    def add(value)
      @value += value
      @num += 1
    end

    def get
      @value / @num
    end
  end
end


end
