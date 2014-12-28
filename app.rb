require 'sinatra'
require 'builder'
require 'time'
require 'net/http'
require 'json'
require 'redis'

redis = Redis.new( url: ENV['REDISTOGO_URL'] || 'redis://localhost:56379')

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

get '/rss' do 
  status 200
  headers \
        "Content-Type"   => "application/xml",
        "Last-Modified" => Time.now.rfc822().to_s

  s = "live"
  filters =  [{type: "equal", field: "ss_adult", value: false},
              {type: "equal", field: "live_status", value: "onair"},
              {type: "equal", field: "provider_type", value: "official"},
              {type:"range", field:"score_timeshift_reserved", from:10}]
  q = {query: "は or の or 【 or 「", service: [s], search: ["title", "description"], join: ["title","description","start_time","cmsid"], filters: filters, size:100}.to_json
  hits = query(q)
  hits = hits[0]["values"]

  stored = redis.lrange s, 0, 2024

  hits.clone.each do |h|
    if stored.any?{|i| JSON.parse(i)['cmsid'] == h['cmsid'] }
      hits.delete_if{ |v| v['cmsid'] == h['cmsid'] }
    else
      redis.rpush(h['cmsid'], h.to_json)
    end
  end

  stored = redis.lrange s, -redis.llen, -1

  xml = Builder::XmlMarkup.new
  xml.instruct! :xml, :version => "1.1", :encoding => "UTF-8"
  xml.rss :version => '2.0' do
    xml.channel do
      xml.title 'waiwai'
      xml.link 'http://search.nicovideo.jp'
      stored.each do |u|
        v = u.to_json
        xml.item do
          xml.title v['title']
          xml.link 'http://search.nicovideo.jp'
          xml.description v['description'] #[0...512]
          xml.pubDate Time.parse(v['start_time']).rfc822() # requires TZ=JST
          xml.guid "http://#{s}.nicovideo.jp/watch/#{v['cmsid']}"
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

