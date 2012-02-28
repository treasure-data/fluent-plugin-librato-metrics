$:.push File.expand_path("../lib", __FILE__)
require 'fluent/test'
require 'fluent/plugin/out_librato_metrics'

class LibratoMetricsOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    user test
    token TEST

    # simple key-value metrics
    <metrics test1.**>
      name test1
      each_key key
      value_key value
      count_key count
    </metrics>

    # single-stream event count
    <metrics test2.**>
      name test2.count
    </metrics>

    # single-stream event sum
    <metrics test3.**>
      name test3.size
      value_key size
    </metrics>

    # single-stream event sum; value type is float
    <metrics test3.test4>
      name test4.elapsed
      value_key elapsed
      type float
    </metrics>
  ]

  TIME = Time.parse("2011-01-02 13:14:15 UTC").to_i

  def create_driver(tag="test", conf=CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::LibratoMetricsOutput, tag) do
      def write(chunk)
        chunk.read
      end
    end.configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal 'test', d.instance.user
    assert_equal 'TEST', d.instance.token
  end

  def test_format
    d = create_driver("test1.1")
    d.emit({"key"=>"a", "value"=>10, "count"=>2}, TIME)
    d.expect_format ["test1.a", TIME/60*60, 20].to_msgpack
    d.run

    d = create_driver("test2.2")
    d.emit({}, TIME)
    d.expect_format ["test2.count", TIME/60*60, 1].to_msgpack
    d.run

    d = create_driver("test3.3")
    d.emit({"size"=>2100}, TIME)
    d.expect_format ["test3.size", TIME/60*60, 2100].to_msgpack
    d.run

    d = create_driver("test3.test4")
    d.emit({"size"=>2400, "elapsed"=>10.0}, TIME)
    d.expect_format ["test3.size", TIME/60*60, 2400].to_msgpack
    d.expect_format ["test4.elapsed", TIME/60*60, 10.0].to_msgpack
    d.run
  end

end

