# Gems
require 'socket'
require 'packetgen'
require 'erb'
require 'thread'

iface = '\Device\NPF_{BB821D48-B18C-433A-B36C-1DE06EC3AF39}' # Meu id Ethernet da minha placa de rede

puts "Iniciando a captura contínua na interface: '#{iface}'..."

# Filtro para pesquisa

$data_mutex = Mutex.new
$all_packets = [] # Para todos os pacotes IP
$tcp_packets = [] # Apenas para pacotes TCP


Thread.new do
  begin
    PacketGen.capture(iface: iface, promisc: true) do |pkt|
      if pkt.is?('IP')
        packet_data = {
          src: pkt.ip.src,
          dst: pkt.ip.dst,
          protocol: pkt.ip.protocol_name,
          timestamp: Time.now.strftime("%H:%M:%S")
        }
        $data_mutex.synchronize do
          $all_packets << packet_data
          $tcp_packets << packet_data if packet_data[:protocol] == 'TCP' # Utilizei binary left-shift para captura da pacotes
        end
      end
    end
  rescue RuntimeError => e
    puts "\n--- ERRO NA CAPTURA: #{e.message} ---"
  end
end

begin
  server = TCPServer.new(4567)
  puts "Servidor TCP/IP rodando em http://localhost:4567" # Servidor web
rescue Errno::EADDRINUSE
  puts "ERRO: A porta 4567 já está em uso."
  exit
end

loop do
  client = server.accept
  request = client.gets

  if request.nil? || request.include?('favicon.ico' )
    client.close
    next
  end

  # Lógica de filtro segura

  filter = request.match(/GET \/\?filter=(\w+)/)&.captures&.first
  if filter.nil? || filter.empty?
    filter = 'all'
  end

  puts "Filtro solicitado: '#{filter}'"

  # Lógica de seleção de pacotes 

  packets_to_show = []
  $data_mutex.synchronize do
    packets_to_show = case filter.downcase
                      when 'tcp'
                        $tcp_packets.dup
                      else # 'all'
                        $all_packets.dup
                      end
  end

  begin
    if File.exist?('index.html.erb')
      erb_template = File.read('index.html.erb')
      renderer = ERB.new(erb_template)
      html = renderer.result_with_hash(packets: packets_to_show, current_filter: filter)

      client.puts "HTTP/1.1 200 OK"
      client.puts "Content-Type: text/html; charset=utf-8\r\n\r\n"
      client.puts html
    else
      client.puts "HTTP/1.1 404 Not Found\r\n\r\n<h1>Erro: Arquivo index.html.erb não encontrado.</h1>"
    end
  rescue Errno::EPIPE
    puts "Aviso: A conexão foi fechada pelo cliente antes da resposta ser enviada."
  ensure
    client.close
  end
end
