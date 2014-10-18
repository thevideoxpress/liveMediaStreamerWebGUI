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

require 'rubygems'
require 'bundler/setup'
require 'liquid'
require 'sinatra/base'
require 'rmixer'
require 'rack/protection'

class LoginScreen < Sinatra::Base
  #enable :sessions
  use Rack::Session::Cookie,  :key => 'rack.session',
                              #:domain => 'localhost',
                              :expire_after => 2592000, # In seconds
                              :path => '/',
                              :secret => 'livemediastreamerGUIsecret'
  
  #set :session_secret, 'super secret'
  #use Rack::Protection
  
  #set :protection
  #, :session => true
  
  get('/') do
    if session['user_name']
      redirect '/app'
    else
      liquid :login, :locals => { "message" => 'ok' }
    end
  end

  get('/logout') do
    session['user_name'] = nil
    redirect '/'
  end
  
  post('/') do
    puts "LOGING..."
    if params['user'] == 'admin' && params['password'] == 'i2cat'
      puts "LOGIN PARAMS ARE CORRECT!"
      session['user_name'] = params['user']
      redirect '/app'
    else
      puts "WRONG LOGIN PARAMS!"
      halt liquid :login, :locals => { "message" => 'Access denied, please go and sign in <a href="/">here</a>' }
    end
  end
end

class MixerAPI < Sinatra::Base

  set :ip, '127.0.0.1'
  set :port, 7777
  set :mixer, RMixer::Mixer.new(settings.ip, settings.port)

  use LoginScreen
  
  before do
    unless session['user_name']
      halt liquid :login, :locals => { "message" => 'Access denied, please go and sign in <a href="/">here</a>' }
    end
  end
  
  configure do
    set :show_exceptions, false
  end
  
  not_found do
    msg = "no path to #{request.path}"
    halt liquid :error, :locals => { "message" => msg }
  end
  
  error do
    msg = "Error is:  #{params[:captures].first.inspect}"
    halt liquid :error, :locals => { "message" => msg }   
  end
  
  def error_html
    begin
      yield
    rescue Errno::ECONNREFUSED, RMixer::MixerError => e
      status 500
      halt liquid :error, :locals => { "message" => e.message }
    end
  end

  helpers do
    def started
      error_html do
        settings.mixer.isStarted
      end
    end
    def isNumber?(object)
      true if Float(object) rescue false
    end
  end

  def dashboardAVMixer (grid = '2x2')
    if started
      avmstate = settings.mixer.getAVMixerState(grid)
      videoMixerHash = avmstate[:video]
      audioMixerHash = avmstate[:audio]
      liquid :AVMixer, :locals => {
            "stateVideoHash" => videoMixerHash,
            "stateAudioHash" => audioMixerHash
        }
    else
      liquid :before
    end
  end

  # Web App Methods
  # Routes
  get '/app' do
    redirect '/app/avmixer'
  end

  post '/app/start/avmixer' do
    content_type :html
    error_html do
      settings.mixer.start
    end
    redirect '/app'
  end
  
#  post '/app/start/vico' do
#    content_type :html
#    error_html do
#      settings.mixer.start
#    end
#    redirect '/app'
#  end
  
  post '/app/stop' do
    content_type :html
    error_html do
      settings.mixer.stop
    end
    redirect '/app'
  end

  get '/app/avmixer' do
    redirect '/app/avmixer/video/grid2x2'
  end

  get '/app/avmixer/video/grid2x2' do
    content_type :html
    dashboardAVMixer('2x2')
  end

  get '/app/avmixer/video/grid3x3' do
    content_type :html
    dashboardAVMixer('3x3')
  end

  get '/app/avmixer/video/grid4x4' do
    content_type :html
    dashboardAVMixer('4x4')
  end

  get '/app/avmixer/video/gridPiP' do
    content_type :html
    dashboardAVMixer('PiP')
  end

  post '/app/addRTSPSession' do 
    content_type :html
    error_html do
        settings.mixer.addRTSPSession(params[:channel].to_i, 'mixer', params[:uri])
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/audio/:mixerid/channel/:channelid/mute' do
    content_type :html
    error_html do
      if (params[:channelid] == "master")
        settings.mixer.sendRequest(
          settings.mixer.muteMaster(params[:mixerid].to_i)
        )
      else
        settings.mixer.sendRequest(
          settings.mixer.muteChannel(params[:mixerid].to_i, params[:channelid].to_i)
        )
      end
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/audio/:mixerid/channel/:channelid/solo' do
    content_type :html
    error_html do
      settings.mixer.sendRequest(
        settings.mixer.soloChannel(params[:mixerid].to_i, params[:channelid].to_i)
      )
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/audio/:mixerid/channel/:channelid/changeVolume' do
    content_type :html
    error_html do
      if (params[:channelid] == "master")
        settings.mixer.sendRequest(
          settings.mixer.changeMasterVolume(params[:mixerid].to_i, params[:volume].to_f)
        )
      else
        settings.mixer.sendRequest(
          settings.mixer.changeChannelVolume(params[:mixerid].to_i, params[:channelid].to_i, params[:volume].to_f)
        )
      end
    end
    redirect '/app/avmixer'
  end
  
  post '/app/avmixer/audio/:mixer_id/:encoder_id/reconfigure' do
    content_type :html
    error_html do
      puts params
      settings.mixer.configEncoder(params[:encoder_id].to_i, 
                                   params[:codec], 
                                   params[:sampleRate].to_i, 
                                   params[:channels].to_i
                                  )
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/audio/:mixerID/addSession' do
    content_type :html
    error_html do
      settings.mixer.addRTPSession("audio", params, 5000, 0)
    end
    redirect '/app/avmixer'
  end

   post '/app/avmixer/audio/:mixerID/addOutputSession' do
    content_type :html
    error_html do
      settings.mixer.addOutputSession(params[:mixerID].to_i, params[:sessionName])
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/video/:grid/applyGrid' do
    content_type :html
    error_html do
      positions = []
      params.each do |k,v|
        if isNumber?(k)
          pos = {
            :pos => k.to_i,
            :ch => v.to_i
          }
          positions << pos
        end
      end

      settings.mixer.applyGrid(params[:grid], positions)

    end
    redirect "/app/avmixer/video/grid#{params[:grid]}"
  end

  post '/app/avmixer/video/:channel/addSession' do
    content_type :html
    error_html do
      settings.mixer.addRTPSession("video", params, 5000, 90000)
    end
    redirect '/app/avmixer'
  end
  
  #TODO
  #gets channel index (not port) to be removed from sessions
  post '/app/avmixer/video/:channel/rmSession' do
    content_type :html
    error_html do
      settings.mixer.rmRTPSession(params[:channel].to_i,
                                  params[:port].to_i,
                                  "video",
                                  params[:codec],
                                  5000,
                                  90000
                                  )
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/video/:channel/commute' do
    content_type :html
    error_html do
      settings.mixer.commute(params[:channel].to_i)
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/video/:channel/fade/:time' do
    content_type :html
    error_html do
      settings.mixer.fade(params[:channel].to_i, params[:time].to_i)
    end
    redirect '/app/avmixer'
  end

  post '/app/avmixer/video/:channel/blend' do
    content_type :html
    error_html do
      settings.mixer.blend(params[:channel].to_i)
    end
    redirect '/app/avmixer'
  end

end
