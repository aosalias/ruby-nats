require 'spec_helper'
require 'yaml'

describe 'cluster' do

  before(:all) do
    B1_CONFIG_FILE = File.dirname(__FILE__) + '/resources/b1_cluster.yml'
    @s1 = NatsServerControl.init_with_config(B1_CONFIG_FILE)
    @s1.start_server

    B2_CONFIG_FILE = File.dirname(__FILE__) + '/resources/b2_cluster.yml'
    @s2 = NatsServerControl.init_with_config(B2_CONFIG_FILE)
    @s2.start_server
  end

  after(:all) do
    @s1.kill_server
    @s2.kill_server
  end

  it 'should properly route plain messages between different servers' do
    data = 'Hello World!'
    received = 0
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)
      wait_on_connections([c1, c2]) do
        c1.subscribe('foo') do |msg|
          msg.should == data
          received += 1
        end
        c2.subscribe('foo') do |msg|
          msg.should == data
          received += 1
        end
        c1.flush do #make sure sub1 registered
          sleep(0.25)
          c2.publish('foo', data)
          c2.publish('foo', data)
          c2.flush do #make sure published
            sleep(0.25)
            c1.flush do #make sure received
              EM.stop
            end
          end
        end
      end
    end
    received.should == 4
  end

  it 'should properly route messages with staggered startup' do
    @s2.kill_server
    data = 'Hello World!'
    received = 0
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri) do
        c1.subscribe('foo') do |msg|
          msg.should == data
          received += 1
        end
        c1.flush do
          @s2.start_server
          c2 = NATS.connect(:uri => @s2.uri) do
            sleep(0.25) # Allow time for route to form
            c2.publish('foo', data)
            c2.publish('foo', data)
            c2.flush do #make sure published
              c1.flush do #make sure received
                EM.stop
              end
            end
          end
        end
      end
    end
    received.should == 2
  end

end
