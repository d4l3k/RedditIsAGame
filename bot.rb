require 'bundler'
Bundler.require

# requires socksify gem
require "socksify"
require 'socksify/http'

# use w/ OAuth2 like OAuth2::Client.new(id, secret, connection_opts: { proxy: 'socks://127.0.0.1:9050' })
class Faraday::Adapter::NetHttp
    def net_http_connection(env)
        if proxy = env[:request][:proxy]
          if proxy[:uri].scheme == 'socks'
            Net::HTTP::SOCKSProxy(proxy[:uri].host, proxy[:uri].port)
          else
            Net::HTTP::Proxy(proxy[:uri].host, proxy[:uri].port, proxy[:user], proxy[:password])
          end
        else
          Net::HTTP
        end.new(env[:url].host, env[:url].port)
    end
end
$port = 13000+(rand*100).floor * 10
dir = Dir.mktmpdir
file = "#{dir}/torrc"
File.write(file, "SOCKSPort #{$port}\nControlPort #{$port+1}\nDataDirectory #{dir}")
tor_proc = fork do
    exec "tor -f #{file}"
end
Process.detach tor_proc
sleep 1
class RedditKit::Client
    def connection_with_url(url)
        Faraday.new(url, {:builder => middleware, :proxy => "socks://127.0.0.1:#{$port}"})
    end
end

def conn url
    Faraday.new( url, {:proxy => "socks://127.0.0.1:#{$port}"} ) do |conn|
        conn.use FaradayMiddleware::FollowRedirects
        conn.adapter :net_http
    end
end

$client = RedditKit::Client.new
$redis = Redis.new( driver: 'hiredis' )
$captcha = DeathByCaptcha.socket_client($redis.get("deathbycaptcha:user"),$redis.get("deathbycaptcha:pass"))
$agents = ["Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.63 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9) AppleWebKit/537.71 (KHTML, like Gecko) Version/7.0 Safari/537.71",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.63 Safari/537.36",
    "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:25.0) Gecko/20100101 Firefox/25.0",
    "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.57 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_1) AppleWebKit/537.73.11 (KHTML, like Gecko) Version/7.0.1 Safari/537.73.11",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.63 Safari/537.36",
    "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.63 Safari/537.36"
]
$words = File.read("/usr/share/dict/cracklib-small").split("\n")
$tor = Tor::Controller.connect(:port => ($port +1))
$tor.authenticate
puts "Tor SOCKS port: #{$port}"
#TCPSocket.socks_server="localhost"
#TCPSocket.socks_port = port

def get_captcha
    id = $client.new_captcha_identifier
    url = $client.captcha_url id
    puts "ID: #{id}, URL: #{url}"
end
def import_ids
    ids = JSON.parse(File.read("ids.json"))
    ids.each do |v|
        $redis.zadd("riag:rewind:ids", v["time"],v["id"])
    end
end
def name words, style
    parts = []
    words.times do
        word = "'"
        while word.include? "'" do
            word = $words[($words.length*rand).floor]
        end
        parts.push word
    end
    nam = ""
    if style==1
        parts.each do |part|
            nam += part.capitalize
        end
    elsif style==2
        nam = parts.join ""
    else
        nam = parts.join "_"
    end
    return nam[0..19]
end
def rand_name
    return name((2*rand).floor+2, (rand*2).floor)
end
def rand_pass
    letters = (0..9).to_a + ('A'..'Z').to_a+('a'..'z').to_a
    return (0...rand(20)+5).map { letters[rand(letters.length)] }.join
end
def rand_code len
    letters = (0..9).to_a + ('A'..'Z').to_a+('a'..'z').to_a
    return (0...len).map { letters[rand(letters.length)] }.join
end
def write_accounts
    File.write("tmp/accounts.txt",$redis.keys("riag:account:*").map{|a| a.split(":").last}.join("\n"))
end
def mass_upvote id
    link = nil
    puts "[MassUpvote] #{id}"
    $redis.keys("riag:account:*").shuffle.each do |acc|
        user = acc.split(":").last
        begin
            client = login user
            link ||= id[0..2]=="t1_" ? client.comment(id) : client.link(id)
            begin
                client.upvote link
                puts " :: #{user} upvoted."
            rescue RedditKit::PermissionDenied
                puts " :: #{user} already upvoted."
            rescue RedditKit::RateLimited
                puts " :: #{user} rate limited!"
                change_ip
            end
        rescue RedditKit::PermissionDenied
            puts " :: #{user} failed to login."
        end
        change_ip
    end
end
class String
    def minclude? arr
        d = self.downcase
        arr.each do |word|
            if d.include? word
                return true
            end
        end
        return false
    end
end

def response str
    bot = CleverBot.new
    resp = ""
    while resp.length == 0 || resp.minclude?(["bot", "ai ", "a.i."])
        resp = bot.think str
    end
    return resp
end
def internal_karma
    c = 0
    l = 0
    maxc = 0
    maxl = 0
    max_user = ""
    $redis.keys("riag:account:*").each do |acc|
        info = $redis.hgetall(acc)
        uc = info["comment_karma"].to_i
        ul = info["link_karma"].to_i
        c += uc
        l += ul
        if maxc+maxl < ul + uc
            maxc = uc
            maxl = ul
            max_user = info["user"]
        end
    end
    puts "[InternalKarma] Link: #{l}, Comment: #{c}, Total: #{l+c}"
    puts " :: Highest: #{max_user}, #{maxl}/#{maxc}/#{maxl+maxc}"
end
def enumerate_karma
    link_karma = 0
    comment_karma = 0
    $redis.keys("riag:account:*").shuffle.each do |acc|
        user = acc.split(":").last
        c = conn "http://www.reddit.com/user/#{user}/"
        resp = c.get.body
        noko = Nokogiri.parse resp
        karmas = noko.css(".karma")
        if karmas.length > 0
            lkarma = karmas.first.text.gsub(",","").to_i
            ckarma = noko.css(".comment-karma").first.text.gsub(",","").to_i
            link_karma += lkarma
            comment_karma += ckarma
            puts "[Karma] #{user}, L: #{lkarma}/#{link_karma}, C: #{ckarma}/#{comment_karma}, T: #{lkarma + ckarma}/#{comment_karma+link_karma}"
            $redis.hmset "riag:account:#{user}", "link_karma", lkarma, "comment_karma", ckarma
        else
            puts "[ShadowBanned] #{user}".red
            $redis.hmset "riag:account:#{user}", "shadow_banned", true
        end
        change_ip
        sleep 6
    end
end
def rand_user
    acc = $redis.keys("riag:account:*")
    user = acc[rand(acc.length)].split(":").last
    return login user
rescue RedditKit::PermissionDenied
    error "Failed to login to #{user}"
    sleep 6
    return
end
def top_posts n
    c = rand_user
    links = []
    puts "[Top Posts] Fetching top #{n*100}."
    n.times do |i|
        puts " :: Getting Page #{i+1}, Link Count: #{links.length}"
        after = ""
        if links.length > 0
            after = "t3_#{links.last.id}"
        end
        got = c.front_page({category: 'top', limit: 100, time: 'all', after: after}).to_a
        got.select do |link|
            link.domain.include? "imgur.com"
        end .each do |link|
            $redis.sadd "riag:top-images", "t3_#{link.id}"
        end
        links += got
    end
    binding.pry
end
def post_a_bunch n
    top = $redis.smembers "riag:top-images"
    n.times do |i|
        submit top[rand(top.length)]
        change_ip
    end
end
def error msg
    puts " :: Error! #{msg}".red
end
def submit id
    client = rand_user
    if !client
        return
    end
    details = client.link(id)
    name = client.username
    title = details.title
    subreddit = client.subreddit details.subreddit
    puts "[Resubmitting] #{title} as #{name} to r/#{details.subreddit}"
    if details.subreddit == "Music"
        error "r/Music doesn't accept pictures!"
        return
    end
    if details.kind == "t3"
        if details.domain.include? "imgur"
            # link = upload_url details.url
            link = change_url details.url
            puts " :: Image uploaded: #{link}"
            captcha = client.needs_captcha?
            $redis.hmset "riag:account:#{name}", "needs_captcha", captcha
            if captcha
                captcha_id = client.new_captcha_identifier
                url = client.captcha_url captcha_id
                puts " :: Decoding captcha... (#{url})"
                co = conn url
                co.headers['User-Agent'] = $redis.hmget("riag:account:#{name}", "useragent")[0]
                img_resp = co.get
                file = Tempfile.new "captcha.png"
                file.write img_resp.body
                file.close
                file.open
                resp = $captcha.decode file
                begin
                    link = client.submit title, subreddit, {url: link, captcha_identifier: captcha_id, captcha_value: resp['text'], save: true}
                rescue RedditKit::InvalidCaptcha
                    error "Invalid Captcha. URL: #{url}, Code: #{resp['text']}"
                    $captcha.report resp["captcha"]
                rescue RedditKit::RateLimited
                    error "RateLimited!"
                    return
                end
            else
                client.submit title, subreddit, {url: link}
            end
            $redis.incr "riag:links_submitted"
        else
            error "Not Imgur!"
        end
    else
        error "Not link!"
    end
end
def change_url url
    if url.include? "://imgur.com/a/"
        if url[url.length-1]!="/"
            url += "/"
        end
        return url +"#{rand(100)}/"
    elsif url.include? "://imgur.com/gallery/"
        bits = url.split("/")
        id = bits[bits.index("gallery")+1]
        return "http://i.imgur.com/#{id}.jpg.png"
    else
        uri = URI.parse url
        uri.host = "i.imgur.com"
            uri.path += ".png"
        return uri.to_s# + rand(100).to_s
    end
end
def upload_url url
    if url.include? "://imgur.com/a/"
        return "#{url}/#{$words[rand($words.length)]}"
    end
    conn = Faraday.new(:url => 'https://api.imgur.com/3/image') do |faraday|
        faraday.request  :url_encoded             # form-encode POST params
        faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
    end
    resp = conn.post do |req|
        req.headers["Authorization"] = "Client-ID "+$redis.get("riag:imgur-id")
        req.body = "image=#{url}"
    end
    return JSON.parse(resp.body)["data"]["link"]
end
def change_ip
    $tor.send(:send_line, "SIGNAL NEWNYM")
end
def make_account
    user = rand_name
    pass = rand_pass
    captcha_id = $client.new_captcha_identifier
    url = $client.captcha_url captcha_id
    puts "[MakeAccount] #{user} / #{pass}"
    puts " :: Decoding captcha... (#{url})"
    resp = $captcha.decode url
    answer = resp['text']
    begin
        $client.user_agent = $agents[(rand*$agents.length).floor]
        reddit_resp = $client.register user, pass, {captcha_identifier: captcha_id, captcha:answer}
        if reddit_resp[:status]==200
            puts " :: Registered!"
            $redis.hmset "riag:account:"+user, {user: user, pass:pass, useragent: $client.user_agent}.flatten
        else
            error "Status: #{reddit_resp[:status]}"
            binding.pry
        end
        change_ip
    rescue RedditKit::RateLimited
        error "Rate Limited"
        change_ip
    rescue RedditKit::InvalidCaptcha
        error "Invalid Captcha. URL: #{url}, Code: #{answer}"
        $captcha.report resp["captcha"]
    end
end

def login user
    client = RedditKit::Client.new
    details = $redis.hgetall "riag:account:#{user}"
    if details.keys.length > 0
        client.user_agent = details["useragent"]
        client.sign_in details["user"], details["pass"]
        client
    end
end
if ARGV.length > 0
    eval ARGV.join " "
end
binding.pry
Process.kill "INT", tor_proc
