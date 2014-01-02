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
class RedditKit::Client
    def connection_with_url(url)
        Faraday.new(url, {:builder => middleware, :proxy => "socks://127.0.0.1:9050"})
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
$torrc = Tor::Config.load("/etc/tor/torrc")
$tor = Tor::Controller.connect(:port => 9051)
$tor.authenticate
port = ($torrc['SocksPort']||9050).to_i
puts "Tor SOCKS port: #{port}"
#TCPSocket.socks_server="localhost"
#TCPSocket.socks_port = port

def get_captcha
    id = $client.new_captcha_identifier
    url = $client.captcha_url id
    puts "ID: #{id}, URL: #{url}"
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
    return (0...(20*rand).floor+5).map { ('a'..'z').to_a[rand(26)] }.join
end
def mass_upvote id
    link = nil
    puts "[MassUpvote] #{id}"
    $redis.keys("riag:account:*").shuffle.each do |acc|
        user = acc.split(":").last
        begin
            client = login user
            link ||= client.link id
            begin
                client.upvote link
                puts " :: #{user} upvoted."
            rescue RedditKit::PermissionDenied
                puts " :: #{user} already upvoted."
            end
        rescue RedditKit::PermissionDenied
            puts " :: #{user} failed to login."
        end
        change_ip
    end
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
            puts " :: Error! Status: #{reddit_resp[:status]}"
            binding.pry
        end
        change_ip
    rescue RedditKit::RateLimited
        puts " :: Error! Rate Limited"
        change_ip
    rescue RedditKit::InvalidCaptcha
        puts " :: Error! Invalid Captcha. URL: #{url}, Code: #{answer}"
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
binding.pry
