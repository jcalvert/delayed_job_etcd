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

        #prefix with 0 to ensure range queries include all ids
        def id
          @id ||= "0#{SecureRandom.uuid}"
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
          keys.inject({:handler => handler}) do |hash, key|
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
          self.queue = Delayed::Worker.default_queue_name if queue.nil? || queue.blank?
          if self.locked_at.nil?
            Delayed::Worker.etcd.put key, hash_representation.to_json
          else
            Delayed::Worker.etcd.put(worker_lock_name(locked_by), hash_representation.merge({:locked_by => locked_by, :locked_at => locked_at}).to_json)
          end
          self
        end

        def worker_lock_name(lock_name = Worker.name)
          "locked_#{prefix}_#{lock_name}_#{id}"
        end

        def save!
          save
        end

        def destroy
          Delayed::Worker.etcd.del key
        end

        def retrieve_hash(locker=nil)
          key_to_use = locker.nil? ? key : worker_lock_name(locker)
          JSON.parse(Delayed::Worker.etcd.get(key_to_use).kvs.first.value).symbolize_keys
        end

        #this isn't actually part of the interface, it is just used for testing - TODO FIX
        def reload(locker=nil)
          reset

          result = retrieve_hash(locker)
          self.priority = result[:priority].to_i
          self.run_at = Time.at(result[:run_at])
          self.locked_at = Time.at(result[:locked_at]) if result[:locked_at]
          self.failed_at = Time.at(result[:failed_at]) if result[:failed_at]
          self.last_error = result[:last_error]
          self.queue = result[:queue]
          self.attempts = result[:attempts]
          self
        end

        def update_attributes(options)
          options.each {|k,v| send("#{k}=", v) }
          save
        end

        def self.get_worker_locks(worker_name)
          Delayed::Worker.etcd.get("locked_#{prefix}_#{worker_name}", :range_end => "\0").kvs.select{ |kv| kv.key =~ Regexp.new("^locked_#{prefix}_#{worker_name}_") }
        end

        def self.clear_locks!(worker_name)
          get_worker_locks(worker_name).each do |kv|
            job = materialize(kv)
            Delayed::Worker.etcd.del(job.worker_lock_name)
            job.locked_by = nil
            job.locked_at = nil
            job.save
          end
        end

        def self.materialize(result)
          hash = JSON.parse(result.value)
      #    binding.pry
          #hash["payload_object"] = YAML.load(hash["payload_object"])
          hash["run_at"] = Time.at(hash["run_at"])
          hash[result.mod_revision]
          new(hash)
        end

        def fail!
          self.failed_at = Time.now
          #TODO - attempts and retry policy?
          self.save
        end

        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          keys_to_search = Worker.queues.any? ? Worker.queues.map{ |queue| "#{prefix}_#{queue}" } : ["#{prefix}_#{Delayed::Worker.default_queue_name}"]
          results = keys_to_search.map do |key|
            Delayed::Worker.etcd.get(key, :range_end => "#{key}_#{Time.now.to_i}_9_1", :limit => limit, :sort_order => :ascend).kvs.map do |kv|
              materialize(kv)
            end
          end.flatten[0..limit-1].select{|job| job.failed_at == nil && job.locked_at == nil}
          if Delayed::Worker.min_priority || Delayed::Worker.max_priority
            results.reject! do |job|
              (job.priority < (Delayed::Worker.min_priority || -1*Float::INFINITY)) ||
                (job.priority > (Delayed::Worker.max_priority || Float::INFINITY))
            end
          end
          results
        end

        def key
         "#{prefix}_#{queue}_#{run_at.to_i}_#{priority}_#{id}"
        end

        def lock_exclusively!(max_run_time, worker_name)
          lock_time = Time.now.to_i
          transaction_result = Delayed::Worker.etcd.transaction do |txn|
            txn.compare = [
              txn.mod_revision(key, :equal, mod_revision)
            ]
            txn.success = [
              Etcdserverpb::DeleteRangeRequest.new(key: key),
              txn.put(worker_lock_name(worker_name), hash_representation.merge({:locked_by => worker_name, :locked_at => lock_time}).to_json)
            ]
          end
          if transaction_result.succeeded
            self.locked_by = worker_name
            self.locked_at = lock_time
            return true
          else
            return false
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
