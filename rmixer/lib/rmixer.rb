#
#  RUBYMIXER - A management ruby interface for MIXER 
#  Copyright (C) 2013  Fundació i2CAT, Internet i Innovació digital a Catalunya
#
#  This file is part of thin RUBYMIXER.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#  Authors:  Marc Palau <marc.palau@i2cat.net>,
#            Ignacio Contreras <ignacio.contreras@i2cat.net>
#   

require "rmixer/version"
require "connector"
require "append"
require "grids"
require "mongodb"


module RMixer

  # Generic error to be thrown when an error is returned by the remote
  # *Mixer* instance
  class MixerError < StandardError
  end

  # Proxy class that delegates most of it functions to a RMixer::Connector
  # instance while adding exception and convenience methods.
  class Mixer

    def initialize(host, port)
      @conn = RMixer::Connector.new(host, port)
      @db = RMixer::MongoMngr.new
      @started = false
      @randomSize = 2**16
    end

    def isStarted
      @started
    end

    def start 
      puts airMixerID = Random.rand(@randomSize)
      puts previewMixerID = Random.rand(@randomSize)
      puts airEncoderID = Random.rand(@randomSize)
      puts previewEncoderID = Random.rand(@randomSize)
      puts airOutputPathID = Random.rand(@randomSize)
      puts previewOutputPathID = Random.rand(@randomSize)

      createFilter(airMixerID, 'videoMixer', 'airMixer')
      createFilter(previewMixerID, 'videoMixer', 'previewMixer')
      createFilter(airEncoderID, 'videoEncoder', 'airEncoder')
      createFilter(previewEncoderID, 'videoEncoder', 'previewEncoder')

      txId = @db.getTransmitterID

      createPath(airOutputPathID, airMixerID, txId, [airEncoderID])
      createPath(previewOutputPathID, previewMixerID, txId, [previewEncoderID])

      airPath = @db.getPath(airOutputPathID)
      previewPath = @db.getPath(previewOutputPathID)

      @conn.addOutputSession(txId, [airPath["destinationReader"]], 'air')
      @conn.addOutputSession(txId, [previewPath["destinationReader"]], 'preview')

      @started = true
    end

    def updateDataBase
      stateHash = getState
      @db.update(stateHash)
    end

    def getAudioMixerState
      @db.getAudioMixerState
    end

    def getReceiverID
      @db.getReceiverID
    end

    def createFilter(id, type, role = 'default')
      begin 
        response = @conn.createFilter(id, type)
        raise MixerError, response[:error] if response[:error]
      rescue
        return response
      end

      updateDataBase
      @db.addFilterRole(id, type, role)
    end

    def createPath(id, orgFilterId, dstFilterId, midFiltersIds, options = {})
      orgWriterId = (options[:orgWriterId].to_i != 0) ? options[:orgWriterId].to_i : -1
      dstReaderId = (options[:dstReaderId].to_i != 0) ? options[:dstReaderId].to_i : -1

      begin 
        response = @conn.createPath(id, orgFilterId, dstFilterId, orgWriterId, dstReaderId, midFiltersIds)
        raise MixerError, response[:error] if response[:error]
      rescue
        return response
      end

      updateDataBase
    end

    def updateChannelVolume(id, volume)
      @db.updateChannelVolume
    end

    def configEncoder(encoderID, codec, sampleRate, channels)
      encoder = @db.getFilter(encoderID)

      if encoder["codec"] == codec
        configAudioEncoder(encoderID, sampleRate, channels)
      else
        reconfigAudioEncoder(encoderID, codec, sampleRate, channels)
      end
    end

    def addOutputSession(mixerID, sessionName)
      path = @db.getOutputPathFromFilter(mixerID)
      readers = []
      readers << path["destinationReader"]
      @conn.addOutputSession(path["destinationFilter"], readers, sessionName)
    end

    def method_missing(name, *args, &block)
      if @conn.respond_to?(name)
        begin
          response = @conn.send(name, *args, &block)
        rescue JSON::ParserError, Errno::ECONNREFUSED => e
          raise MixerError, e.message
        end
        raise MixerError, response[:error] if response[:error]
        #return nil if response.include?(:error) && response.size == 1
        return response
      elsif @db.respond_to?(name)
        begin
          response = @db.send(name, *args, &block)
        rescue JSON::ParserError, Errno::ECONNREFUSED => e
          raise MixerError, e.message
        end
        raise MixerError, response[:error] if response[:error]
        #return nil if response.include?(:error) && response.size == 1
        return response
      else
        super
      end
    end

  end

end
