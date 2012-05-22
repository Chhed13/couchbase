require "spec_helper"
require "node_resource"
require "node_provider"

describe Chef::Provider::CouchbaseNode do
  let(:provider) { described_class.new(new_resource, stub("run_context")) }
  let(:new_resource) { stub(:name => "self") }

  describe ".ancestors" do
    it { described_class.ancestors.should include Chef::Provider }
  end

  describe "#current_resource" do
    let(:current_resource) { provider.load_current_resource; provider.current_resource }

    context "for the local node" do
      before { stub_request(:get, "localhost:8091/nodes/self").to_return(fixture("nodes_self_mnt.http")) }

      it { current_resource.should be_a_kind_of Chef::Resource::CouchbaseNode }

      it "has the same name as the new resource" do
        current_resource.name.should == new_resource.name
      end

      it "populates the database_path" do
        current_resource.database_path.should == "/mnt/couchbase-server/data"
      end
    end

    context "for a remote node" do
      let(:new_resource) { stub(:name => "10.0.1.20") }
      before { stub_request(:get, "localhost:8091/nodes/10.0.1.20").to_return(fixture("nodes_self_opt.http")) }

      it "has the same name as the new resource" do
        current_resource.name.should == new_resource.name
      end

      it "populates the database_path" do
        current_resource.database_path.should == "/opt/couchbase/var/lib/couchbase/data"
      end
    end
  end

  describe "#action_update" do
    before { provider.current_resource = current_resource }

    context "database path does not match" do
      shared_examples "update couchbase node" do
        let(:current_resource) { stub(:name => node_name, :database_path => "/opt/couchbase/var/lib/couchbase/data") }

        let :new_resource do
          stub({
            :name => node_name,
            :database_path => "/mnt/couchbase-server/data/#{SecureRandom.hex(8)}",
            :updated_by_last_action => nil,
          })
        end

        let! :node_request do
          stub_request(:post, "localhost:8091/nodes/#{node_name}/controller/settings").with({
            :body => hash_including("path" => new_resource.database_path),
          })
        end

        it "POSTs to the Management REST API to update the database path" do
          provider.action_update
          node_request.should have_been_made.once
        end

        it "updates the new resource" do
          new_resource.should_receive(:updated_by_last_action).with(true)
          provider.action_update
        end
      end

      context "addressing the node as self" do
        let(:node_name) { "self" }
        include_examples "update couchbase node"
      end

      context "addressing the node by hostname" do
        let(:node_name) { "10.0.1.20" }
        include_examples "update couchbase node"
      end
    end

    context "database path matches" do
      let(:new_resource)     { stub(:name => "self", :database_path => "/opt/couchbase/var/lib/couchbase/data") }
      let(:current_resource) { stub(:name => "self", :database_path => "/opt/couchbase/var/lib/couchbase/data") }

      before do
        new_resource.as_null_object
        stub_request(:post, "localhost:8091/nodes/self/controller/settings").with({
          :body => hash_including("path" => new_resource.database_path),
        })
      end

      it "does not POST to the Management REST API" do
        provider.action_update
        a_request(:any, /.*/).should_not have_been_made
      end

      it "does not update the new resource" do
        new_resource.should_not_receive(:updated_by_last_action)
        provider.action_update
      end
    end
  end
end