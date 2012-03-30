#
# fluent-plugin-librato-metrics
#
# Copyright (C) 2011-2012 Sadayuki Furuhashi
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

  config_param :librato_user, :string
  config_param :librato_token, :string
  config_param :source, :string, :default => nil

  def initialize
    super
  end

  def configure(conf)
    super
  end

  class LibratoMetricsMetrics < Metrics
    config_param :source, :string, :default => nil
  end

  # override
  def new_metrics(conf, pattern)
    m = LibratoMetricsMetrics.new(pattern)
    m.configure(conf)
    m
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
      value = d.value * d.count
      source = d.metrics.source
      [key, partitioned_time, value, source].to_msgpack(out)
    }
    out
  end

  AggregationKey = Struct.new(:name, :time, :source)

  def write(chunk)
    counters = {}  #=> {AggregationKey => XxxAggregator}
    gauges = {}    #=> {AggregationKey => XxxAggregator}

    chunk.msgpack_each {|key,time,value,source|
      #if m = /^counter\.(.*)$/.match(key)
      #  # FIXME what's the actual behavior of counters?
      #  name = m[1]
      #  k = AggregationKey.new(name, time, source)
      #  (counters[k] ||= MaxAggregator.new).add(value)
      #elsif m = /^gauge\.(.*)$/.match(key)
      #  # FIXME what's the actual behavior of gauges?
      #  name = m[1]
      #  k = AggregationKey.new(name, time, source)
      #  (gauges[k] ||= AverageAggregator.new).add(value)
      #else
        name = key
        k = AggregationKey.new(name, time, source)
        (gauges[k] ||= SumAggregator.new).add(value)
      #end
    }

    #http = Net::HTTP.new('metrics-api.librato.com', 80)
    http = Net::HTTP.new('metrics-api.librato.com', 443)
    http.use_ssl = true
    #http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # TODO verify
    http.cert_store = OpenSSL::X509::Store.new
    header = {}

    begin
      {'counters'=>counters, 'gauges'=>gauges}.each_pair {|type,k_aggrs|
        # send upto 10 entries at once
        k_aggrs.each_slice(10) {|k_aggrs_slice|
          req = Net::HTTP::Post.new('/v1/metrics', header)
          req.basic_auth @librato_user, @librato_token

          params = {}
          params['source'] = @source if @source  # default source

          k_aggrs_slice.each_with_index {|(k,aggr),i|
            params["#{type}[#{i}][name]"] = k.name
            params["#{type}[#{i}][measure_time]"] = k.time.to_s
            params["#{type}[#{i}][source]"] = k.source if k.source
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
  class MaxAggregator
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

  # sum(value) aggregator
  class SumAggregator
    def initialize
      @value = 0
    end

    def add(value)
      @value += value
    end

    def get
      @value
    end
  end

  # avg(value) aggregator
  class AverageAggregator
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
