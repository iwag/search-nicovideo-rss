require 'sinatra'
require 'builder'
require 'time'
require 'net/http'
require 'json'
require 'redis'

redis = if (ENV["RACK_ENV"]=="localhost" ) 
          nil
        else
          Redis.new( url: ENV['REDISTOGO_URL'] || 'redis://localhost:56379')
        end

get '/' do
end

def query(q)
  uri = URI.parse('http://search.nicovideo.jp/api/')
  res = nil
  Net::HTTP.start(uri.host, uri.port){|http|
    json = q || {query: "test", service: ["video"], search: ["title", "description"], join: ["title"]}.to_json
    res = http.post(uri.path, json)
  }
  arr = res.body.split("\n").map{|i| JSON.parse(i) }
  arr.select{ |i| i["type"]=="hits" && ! i["endofstream"] }
end

def makeUrl(s, id)
  "http://#{s}.nicovideo.jp/watch/#{id}"
end

get '/rss' do 
  status 200
  headers \
        "Content-Type"   => "application/xml",
        "Last-Modified" => Time.now.rfc822().to_s

  term = ENV["QUERY_TERM"] || "アニメ"
  s = ENV["QUERY_SERVICE"] || "live"
  filters =  [
    {type: "equal", field: "live_status", value: "onair"},
    {type: "equal", field: "provider_type", value: "official"},
    {type:"range", field:"score_timeshift_reserved", from:10}]
  q = {query: term, service: [s], search: ["title", "description"], join: ["title","description","start_time","cmsid"], filters: filters, size:100, issuer: "github.com/iwag/search-nicovideo-rss", reason: "ma10"}.to_json
  hits = query(q)
  hits = (hits==nil || hits.empty? || hits[0] == nil || hits[0]["values"] == nil) ?  [] : hits[0]["values"]

  stored = redis == nil ? [] : redis.lrange(s, 0, 1024)

  hits.each do |h|
    if stored.any?{|i| JSON.parse(i)['cmsid'] == h['cmsid'] }
      ;
    else
      redis.rpush(s, h.to_json) if redis != nil
      stored.push(h.to_json)
    end
  end

  stored.reverse!

  xml = Builder::XmlMarkup.new
  xml.instruct! :xml, :version => "1.1", :encoding => "UTF-8"
  xml.rss :version => '2.0' do
    xml.channel do
      xml.title 'search-nico' + s + " " + term
      xml.link 'http://search.nicovideo.jp'
      stored.each do |u|
        v = JSON.parse(u)
        xml.item do
          u = makeUrl(s, v['cmsid'])
          xml.title v['title']
          xml.link u
          xml.description "" # v['description'] 
          xml.pubDate Time.parse(v['start_time']).rfc822() # requires TZ=JST
          xml.guid u
        end
      end
    end
  end
end

get '/delete' do
  redis.keys.each do |k,v|
    redis.del(k)
  end
end

