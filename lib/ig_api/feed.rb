require 'ostruct'

module IgApi
  class Feed
    def initialize
      @api = Http.singleton
    end

    def using user
      @user = {
        id: user.data[:pk],
        session: user.session,
        ua: user.useragent
      }
      self
    end

    def story(ids)
      signature = IgApi::Http.generate_signature(
        user_ids: ids.map(&:to_s)
      )
      response = @api.post(Constants::URL + 'feed/reels_media/',
                           "ig_sig_key_version=4&signed_body=#{signature}")
                     .with(session: @user[:session], ua: @user[:ua])
                     .exec

      JSON.parse(response.body)['reels']
    rescue JSON::ParserError => e
      if defined?($LOG_ERRORS) && $LOG_ERRORS
        puts "ERROR! Error while parsing json for reels(stories), #{e.message}"
        puts response.body
        puts "End error"
      end
      {}
    end

    def highlights_tray(user_id)
      endpoint = Constants::URL + "highlights/#{user_id}/highlights_tray/"
      response = @api.get(endpoint)
                     .with(session: @user[:session], ua: @user[:ua])
                     .exec

      JSON.parse(response.body)['tray']
    rescue JSON::ParserError => e
      if defined?($LOG_ERRORS) && $LOG_ERRORS
        puts "ERROR! Error while parsing json for highlights, #{e.message}"
        puts response.body
        puts "End error"
      end
      {}
    end

    def timeline_media(params = {})
      user_id = @user[:id]

      rank_token = IgApi::Http.generate_rank_token @user[:id]
      endpoint = Constants::URL + "feed/user/#{user_id}/"
      endpoint << "?rank_token=#{rank_token}"
      params.each { |k, v| endpoint << "&#{k}=#{v}" }
      response = @api.get(endpoint)
                   .with(session: @user[:session], ua: @user[:ua])
                   .exec

      JSON.parse response.body, object_class: OpenStruct
    rescue JSON::ParserError => e
      if defined?($LOG_ERRORS) && $LOG_ERRORS
        puts "ERROR! Error while parsing json, #{e.message}"
        puts response.body
        puts "End error"
      end
      {}
    end

    def self.user_followers(user, data, limit)
      has_next_page = true
      followers = []
      user_id = (!data[:id].nil? ? data[:id] : user.data[:id])
      data[:rank_token] = IgApi::API.generate_rank_token user.session.scan(/ds_user_id=([\d]+);/)[0][0]
      while has_next_page && limit > followers.size
        response = user_followers_next_page(user, user_id, data)
        has_next_page = !response['next_max_id'].nil?
        data[:max_id] = response['next_max_id']
        followers += response['users']
      end
      limit.infinite? ? followers : followers[0...limit]
    end

    def self.user_followers_next_page(user, user_id, data)
      endpoint = "https://i.instagram.com/api/v1/friendships/#{user_id}/followers/"
      param = "?rank_token=#{data[:rank_token]}" +
              (!data[:max_id].nil? ? '&max_id=' + data[:max_id] : '')
      result = IgApi::API.http(
        url: endpoint + param,
        method: 'GET',
        user: user
      )
      JSON.parse result.body, object_class: OpenStruct
    end
  end
end
