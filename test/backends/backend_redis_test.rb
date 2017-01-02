# encoding: utf-8

require File.dirname(__FILE__) + '/../test_helper'
require_relative './backend_common_tests'

class BackendRedisTest < Test::Unit::TestCase
  include BackendCommonTests

  def setup
    begin
      @backend = ClassifierReborn::BayesRedisBackend.new
    rescue Redis::CannotConnectError => e
      omit(e)
    end
  end

  def cleanup
    @backend.instance_variable_get(:@redis).flushdb
  end
end
