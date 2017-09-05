$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "delayed_job_etcd"
require "delayed/backend/shared_spec"
require 'active_record'
require "pry"


# Apparently delayed job has support for active record objects having methods called in a delayed manner
# This is copied from the delayed_job spec helper.


ActiveRecord::Base.establish_connection :adapter => 'sqlite3', :database => ':memory:'
ActiveRecord::Base.logger = Delayed::Worker.logger
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :stories, :primary_key => :story_id, :force => true do |table|
    table.string :text
    table.boolean :scoped, :default => true
  end
end

class Story < ActiveRecord::Base
  self.primary_key = :story_id
  def tell; text; end
  def whatever(n, _); tell*n; end
#  default_scope where(:scoped => true)

  handle_asynchronously :whatever
end
