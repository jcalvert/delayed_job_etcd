require "spec_helper"
require "delayed/backend/etcd"

describe Delayed::Backend::Etcd::Job do
    before(:each) do
      Delayed::Backend::Etcd::Job.after_fork
    end

    it_behaves_like "a delayed_job backend"

    describe "after_fork" do
      it "calls reconnect on the connection" do
        expect(Delayed::Worker).to receive(:etcd=) do |arg|
          expect(arg).to be_a_kind_of(Etcdv3)
        end
        Delayed::Backend::Etcd::Job.after_fork
      end
    end

end
