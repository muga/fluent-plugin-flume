#
# Fluent
#
# Copyright (C) 2012 Muga Nishizawa
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

class FlumeOutput < BufferedOutput
  Fluent::Plugin.register_output('flume', self)

  config_param :host,      :string,  :default => 'localhost'
  config_param :port,      :integer, :default => 35863
  config_param :timeout,   :integer, :default => 30
  config_param :remove_prefix,    :string, :default => nil
  config_param :default_category, :string, :default => 'unknown'

  def initialize
    require 'thrift'
    $:.unshift File.join(File.dirname(__FILE__), 'thrift')
    require 'flume_types'
    require 'flume_constants'
    require 'thrift_flume_event_server'

    super
  end

  def configure(conf)
    super
  end

  def start
    super

    if @remove_prefix
      @removed_prefix_string = @remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
  end

  def shutdown
    super
  end

  def format(tag, time, record)
    if @remove_prefix and
        ( (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length) or
          tag == @remove_prefix)
      [(tag[@removed_length..-1] || @default_category), time, record].to_msgpack
    else
      [tag, time, record].to_msgpack
    end
  end

  def write(chunk)
    records = []
    chunk.msgpack_each { |arr|
      records << arr
    }

    transport = Thrift::Socket.new @host, @port, @timeout
    #transport = Thrift::FramedTransport.new socket
    #protocol = Thrift::BinaryProtocol.new transport, false, false
    protocol = Thrift::BinaryProtocol.new transport
    client = ThriftFlumeEventServer::Client.new protocol

    transport.open
    $log.debug "thrift client opend: #{client}"
    begin
      records.each { |r|
        tag, time, record = r
        entry = ThriftFlumeEvent.new(:body=>record.to_json.to_s.force_encoding('UTF-8'),
                                     :priority=>Priority::INFO,
                                     :timestamp=>time,
                                     :fieldss=>{'category'=>tag})
        client.append entry
      }
    ensure
      $log.debug "thrift client closing: #{client}"
      transport.close
    end
  end
end

end
