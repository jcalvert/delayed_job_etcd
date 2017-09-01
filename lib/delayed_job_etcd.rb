require "delayed_job_etcd/version"
require 'active_support'
require 'delayed_job'
require 'delayed/backend/etcd'
require 'etcdv3'
require 'securerandom'
require 'json'

Delayed::Worker.backend = :etcd

module Delayed
  class Worker
    class << self
      attr_accessor :etcd
    end
  end
end

