require 'delayed_job'

module Delayed
  module Backend
    module Etcd
      class Job
        include Delayed::Backend::Base

        attr_accessor :priority, :run_at, :queue,
          :failed_at, :locked_at, :locked_by

        attr_accessor :handler, :last_error, :attempts
        attr_accessor :mod_revision
        attr_writer :id

        def self.prefix
          "delayed_job"
        end

        def prefix
          self.class.prefix
        end

        def self.all_keys
          Delayed::Worker.etcd.get(prefix, :range_end => "\0", :count_only => true).count
        end

        def self.after_fork
          Delayed::Worker.etcd = Etcdv3.new(:url => 'http://127.0.0.1:2379')
        end

        def self.delete_all
          Delayed::Worker.etcd.del(prefix, :range_end => "\0")
        end

        def self.count
          Delayed::Worker.etcd.get(prefix, :range_end => "\0", :count_only => true).count
        end

        def id
          @id ||= SecureRandom.uuid
        end

        def self.db_time_now
          Time.now
        end

        def initialize(options)
          @id = nil
          @priority = 0
          @run_at = nil
          @queue = nil
          @failed_at = nil
          @locked_at = nil
          @attempts = 0
          options.each {|k,v| send("#{k}=", v) }
        end

        def hash_representation
          keys = [:id, :priority, :run_at, :queue, :last_error,
                  :failed_at, :locked_at, :locked_by, :attempts]
          keys.inject({:payload_object => handler}) do |hash, key|
              value = self.send(key)
              if !value.nil?
                value = value.to_i if value.is_a?(Time)
                hash[key] = value
              end
              hash
          end
        end

        def save
          set_default_run_at
          Delayed::Worker.etcd.put key, hash_representation.to_json
          self
        end

        def worker_lock_name
          "#{prefix}_#{Worker.name}_lock_#{id}"
        end

        def save!
          save
        end

        def destroy
          Delayed::Worker.etcd.del key
        end

        def reload
          reset
          result = JSON.parse(Delayed::Worker.etcd.get(key).kvs.first.value).symbolize_keys
          self.priority = result[:priority].to_i
#          self.run_at = _run_at.nil? ? nil : Time.at(_run_at.to_i)
          self.queue = result[:queue]
  #        self.handler = _payload_object||YAML.dump(nil)
   #       self.failed_at = _failed_at.nil? ? nil : Time.at(_failed_at.to_i)
    #      self.locked_at = _locked_at.nil? ? nil : Time.at(_locked_at.to_i)
    #      self.locked_by = _locked_by
        #  self.attempts = _attempts.to_i
        #  self.last_error = _last_error
          self
        end

        def update_attributes(options)
          options.each {|k,v| send("#{k}=", v) }
          save
        end

        def self.get_worker_locks(worker_name)
          Delayed::Worker.etcd.get("#{prefix}_#{worker_name}", :range_end => "\0").kvs
        end

        def self.clear_locks!(worker_name)
          get_worker_locks(worker_name).each do |kv|
            job = JSON.parse(Delayedi::Worker.etcd.get(kv.value).kvs.first.value).symbolize_keys
            job.delete(:locked_by)
            job.delete(:locked_at)
            Delayed::Worker.etcd.put key, job.to_json
          end
        end

        def self.materialize(result)
          hash = JSON.parse(result.value)
          hash["payload_object"] = YAML.load(hash["payload_object"])
          hash["run_at"] = Time.at(hash["run_at"])
          hash[result.mod_revision]
          new(hash)
        end

        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          keys_to_search = Worker.queues.any? ? Worker.queues.map{ |queue| "#{prefix}_#{queue}_#{Time.now.to_i}" } : ["#{prefix}__#{Time.now.to_i}"]
          keys_to_search.map do |key|
            Delayed::Worker.etcd.get(prefix, :range_end => key, :limit => limit).kvs.map do |kv|
              materialize(kv)
            end
          end.flatten[0..limit-1]
        end

        def key
          "#{prefix}_#{queue}_#{run_at.to_i}_#{id}"
        end

        def lock_exclusively!(max_run_time, worker_name)
          lock_time = Time.now.to_i
          transaction_result = Delayed::Worker.etcd.transaction do |txn|
            txn.compare = [
              txn.mod_revision(key, :equal, mod_revision)
            ]
            txn.success = [
              txn.del(key, key),
              txn.put(worker_lock_name, hash_representation.merge({:locked_by => Worker.name, :locked_at => lock_time}).to_json)
            ]
          end
          if transaction_result.succeeded
            locked_by = Worker.name
            locked_at = lock_time
            true
          else
            false
          end
        end

        def self.create(options)
          new(options).save
        end

        def self.create!(options)
          create(options)
        end

        def ==(other)
          self.id == other.id
        end

      end
    end
  end
end
