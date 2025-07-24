require 'socket'
require 'packetgen'
require 'erb'

# Captura de pacotes (IP e TCP)
$packets = []

Thread.new do
  PacketGen.capture(iface: 'eth0', max: 100, promisc: true) do |pkt|
    if pkt.is?('IP') || pkt.is?('TCP')
      $packets << {
        src: pkt.ip&.src,
        dst: pkt.ip&.dst,
        protocol: pkt.is?('TCP') ? 'TCP' : 'IP',
        timestamp: Time.now
      }
    end
  end
end

# Servidor Web básico
server = TCPServer.new(4567)

puts "Servidor TCP/IP rodando em http://localhost:4567"

loop do
  client = server.accept

  request = client.gets
  filter = request[/GET \/(\w*)/, 1] || 'all'

  filtered_packets = case filter
                     when 'tcp' then $packets.select { |p| p[:protocol] == 'TCP' }
                     when 'ip'  then $packets.select { |p| p[:protocol] == 'IP' }
                     else $packets
                     end

  erb_template = File.read('index.html.erb')
  renderer = ERB.new(erb_template)
  html = renderer.result_with_hash(packets: filtered_packets)

  client.puts "HTTP/1.1 200 OK"
  client.puts "Content-Type: text/html\r\n\r\n"
  client.puts html

  client.close
end
