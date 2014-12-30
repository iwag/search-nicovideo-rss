require 'sinatra'
require 'builder'
require 'time'
require 'net/http'
require 'json'
require 'redis'
require 'nicosearch'
require 'date'

redis = if (ENV["REDISTOGO_URL"])
          Redis.new( url: ENV['REDISTOGO_URL'])
        else
          nil
        end

get '/' do
  status 400
end

get '/rss' do 
  status 200
  headers \
        "Content-Type"   => "application/xml",
        "Last-Modified" => Time.now.rfc822().to_s

  term = ENV["QUERY_TERM"] || "アニメ"
  s = ENV["QUERY_SERVICE"] || "live"
  filters =  [
    SearchNicovideo::FilterBuilder.new().type("equal").field("live_status").value("onair").build(),
    SearchNicovideo::FilterBuilder.new().type("equal").field("provider_type").value("official").build(),
    SearchNicovideo::FilterBuilder.new().type("range").field("score_timeshift_reserved").from(10).build()
  ]
  qb = SearchNicovideo::QueryBuilder.new()
  q = qb.query(term).service([s]).search(["title","description"]).join(["title","description","start_time","cmsid"]).filters(filters).sort_by("start_time").desc(false).build().to_json
  res = SearchNicovideo::search(q)
  hits = res[:hits] 
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
      xml.link SearchNicovideo::uri_string
      stored.each do |u|
        v = JSON.parse(u)
        xml.item do
          u = SearchNicovideo::watch_uri(s, v['cmsid']).to_s
          xml.title v['title']
          xml.link u
          xml.description v['description'] 
          xml.pubDate SearchNicovideo.parse_time(v['start_time']).rfc822() # requires TZ=JST
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

