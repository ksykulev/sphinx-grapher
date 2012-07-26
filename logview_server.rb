require 'date'
require 'webrick'
require 'erb'
require 'bigdecimal'
include WEBrick

module TailIO
  TAIL_BUF_LENGTH = 1 << 16

  def tail(n)
    return [] if n < 1
    buf = ""
    begin
      seek -TAIL_BUF_LENGTH, IO::SEEK_END
      while buf.count("\n") <= n
        buf = read(TAIL_BUF_LENGTH) + buf
        seek 2 * -TAIL_BUF_LENGTH, IO::SEEK_CUR
      end
    rescue
      #overrun top of file
      p = pos
      if  p > 0
        #the last seek ran past the beginning of the file
        rread = p
        seek 0, IO::SEEK_SET
        buf = read(rread-TAIL_BUF_LENGTH-1) + buf
      else
        #because buffer was larger than the entire size of the file
        buf = read(TAIL_BUF_LENGTH)
      end
    end
    buf = buf.split("\n")
    n = 0 if(n > buf.length)
    buf[-n..-1]
  end
end
IO.send(:include, TailIO)

class LogParser
  SPHINXQL = /\/\*(?<date>.+)conn.+(?<time>\d+\.\d+).+(?<found>\d+)\s\*\/.+(?:from |FROM )(?<index>\w+)/
  PLAIN = /\[(?<date>.+?)\]\s(?<time>\d+\.\d+).+\s(?<found>\d+)\s\(.+\[(?<index>\w+)\]/

  def initialize(file)
    @file = file
  end

  def formatted_points(points)
    formatted_points = {}
    self.parse(points).reverse_each do |point|
      match = PLAIN.match(point) || SPHINXQL.match(point)
      if match
        formatted_points[match['index']] = {} unless formatted_points[match['index']]
        time = DateTime.strptime(match['date'].strip,'%a %b %d %H:%M:%S.%L %Y').to_time
        date_key = "new Date('#{time.year}','#{time.month-1}','#{time.day}','#{time.hour}','#{time.min}').getTime()"
        value = Float(match['time'])
        unless value == 0
          formatted_points[match['index']][date_key] = [] unless formatted_points[match['index']][date_key]
          formatted_points[match['index']][date_key] << value unless value == 0
        end
      end
    end
    formatted_points
  end

  def parse(points)
    raw_log_lines = []
    File.open(@file) do |f|
      raw_log_lines = f.tail(points)
    end
    raw_log_lines
  end
end


class Index < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    res['Content-Type'] = "text/html"
    res.status = 200

    lp = LogParser.new('query.log')
    indexes = lp.formatted_points(2000)
    template = ERB.new(File.new('index.erb').read)

    res.body = template.result(binding)
  end
end

server = WEBrick::HTTPServer.new({:Port => 2000})
server.mount("/", Index)
trap('INT'){ server.shutdown }
server.start
