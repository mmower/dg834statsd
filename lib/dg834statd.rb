require 'rubygems'

require 'net/http'
require 'net/telnet'
require 'logger'

require 'daemons'
require 'json'

DAEMON_ROOT = File.expand_path( File.join( File.dirname( __FILE__ ), '..' ) )

module DG834
  FILTERS = {
    :ds_conn_rate => /ds\sconnection\srate\s?:\s*(\d+)/i,
    :ds_line_attenutation => /ds\sline\sattenuation\s?:\s*(\d+)/i,
    :ds_margin => /ds\smargin\s?:\s*(\d+)/i,
    :ds_payload => /ds\spayload\s?:\s*(\d+)/i,
    :us_conn_rate => /us\sconnection\srate\s?:\s*(\d+)/i,
    :us_line_attenutation => /us\sline\sattenuation\s?:\s*(\d+)/i,
    :us_margin => /us\smargin\s?:\s*(\d+)/i,
    :us_payload => /us\spayload\s?:\s*(\d+)/i
  }
  
  ROUTER_IP = ENV['ROUTER_IP'] || '192.168.0.1'
  DAEMON_SLEEP = 10
  
  class ADSLStatsDaemon
    
    def self.start( router_ip = ROUTER_IP, sleep_interval = DAEMON_SLEEP )
      Daemons.run_proc( 'dg834statd' ) do
        daemon = ADSLStatsDaemon.new( router_ip, sleep_interval )
        daemon.runloop
      end
    end
    
    def initialize( router_ip, sleep_interval )
      @router_ip = router_ip
      @sleep_interval = sleep_interval
      @json_stats = File.open( File.join( DAEMON_ROOT, 'log', 'dg834.json' ), 'w' )
      @csv_stats = File.open( File.join( DAEMON_ROOT, 'log', 'dg834.csv' ), 'w' )
      @logger = Logger.new( File.join( DAEMON_ROOT, 'log', 'dg834statds.log' ) )
      @should_exit = false
      
      Signal.trap( "TERM" ) do
        @logger.info( "Shutting down on SIGTERM" )
        @should_exit = true
      end
      
      Signal.trap( "QUIT" ) do
        @logger.info( "Shutting down on SIGQUIT" )
        @should_exit = true
      end
      
      Signal.trap( "HUP" ) do
        @logger.info( "Received SIGHUP" )
      end
      
      @logger.debug( "DG834statsd initialization complete" )
    end
    
    def runloop
      @logger.debug( "Enabling telnet interface for DG834@#{@router_ip}" )
      enable_telnet
      @logger.info( "Enabled telnet interface for DG834@#{@router_ip}" )
      loop do
        break if should_exit?
        report_stats( collect_stats )
        daemon_sleep
      end
    end
    
    def should_exit?
      @should_exit
    end
    
    def daemon_sleep
      sleep( @sleep_interval )
    end
    
    # First enable debug mode on the DG834
    def enable_telnet
      Net::HTTP.get_response( @router_ip, '/setup.cgi?todo=debug' )
    end
    
    def match_stats( data, filters )
      stats = {
        :when => Time.now.to_i
      }

      filters.each do |key,filter|
        match = data.match( filter )
        if match
          stats[key] = match[1].to_i
        else
          puts "No match for key: #{key}"
        end
      end

      stats
    end
    
    def report_stats( stats )
      @json_stats.write( stats.to_json )
      @json_stats.flush
      @csv_stats.puts( "#{stats[:when]},#{stats[:ds_conn_rate]},#{stats[:ds_line_attenutation]},#{stats[:ds_margin]},#{stats[:ds_payload]},#{stats[:us_conn_rate]},#{stats[:us_line_attenutation]},#{stats[:us_margin]},#{stats[:us_payload]}" )
      @csv_stats.flush
    end
    
    # Telnet to local admin port
    def collect_stats
      @logger.info( "Collecting router stats" )
      router = Net::Telnet.new( 'Host' => @router_ip, 'Timeout' => 10,  'Prompt' => /[$%#>] \z/n )
      router.waitfor( 'Prompt' => /[$%#>] \z/n )
      data = router.cmd( 'cat /proc/avalanche/avsar_modem_stats' )
      match_stats( data, FILTERS )
    end
    
  end
  
end

END {
  DG834::ADSLStatsDaemon.start
}
