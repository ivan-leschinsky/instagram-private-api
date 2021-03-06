require 'ostruct'

module IgApi
  class Account
    def initialized
      @api = nil
    end

    def api
      @api = IgApi::Http.new if @api.nil?

      @api
    end

    def using(session)
      User.new session: session
    end

    def login(username, password, path_to_store)
      if path_to_store && File.exist?(path_to_store)
        if (saved_data = File.read(path_to_store))
          return Marshal.load(saved_data)
        end
      end

      config = IgApi::Configuration.new

      user = User.new username: username,
                      password: password


      uuid = IgApi::Http.generate_uuid
      request = api.post(
        Constants::URL + 'accounts/login/',
        format(
          'ig_sig_key_version=4&signed_body=%s',
          IgApi::Http.generate_signature(
            device_id: user.device_id,
            login_attempt_user: 0, password: user.password, username: user.username,
            _csrftoken: 'missing', _uuid: uuid
          )
        )
      ).with(ua: user.useragent).exec

      response = JSON.parse request.body, object_class: OpenStruct

      if response.status == 'fail'
        if response.error_type == 'checkpoint_challenge_required'
          # uuid = IgApi::Http.generate_uuid
          username_id = response.challenge.api_path.split('/')[2]
          csrf_token = request.get_fields('set-cookie')[0].match(/\bcsrftoken.*; /).to_s.split(';').first.split('csrftoken=').last
          params = format(
            'ig_sig_key_version=4&signed_body=%s',
            IgApi::Http.generate_signature(
              choice: 0,
              device_id: user.device_id,
              _uid: username_id,
              _csrftoken: csrf_token,
              _uuid: uuid,
              guid: uuid
            )
          )
          request = api.post(Constants::URL + response.challenge.api_path[1..-1], params).with(ua: user.useragent).exec.body

          request = api.post(Constants::URL + '/challenge/6005886155/OURE81JskT/'[1..-1], params).with(ua: user.useragent).exec

          # request = api.get(Constants::URL + response.challenge.api_path[1..-1] + '?choice=0').with(ua: user.useragent).exec
          # request = api.post(Constants::URL + response.challenge.url, { choice: 0 }).with(ua: user.useragent).exec
          # request = api.post(response.challenge.url, format('choice=0')).with(ua: user.useragent).exec
        else
          raise response.message
        end
      end

      logged_in_user = response.logged_in_user
      user.data = logged_in_user

      cookies_array = []
      all_cookies = request.get_fields('set-cookie')
      all_cookies.each do |cookie|
        cookies_array.push(cookie.split('; ')[0])
      end
      cookies = cookies_array.join('; ')
      user.config = config
      user.session = cookies
      File.write(path_to_store, Marshal.dump(user)) if path_to_store
      user
    end

    def self.search_for_user_graphql(user, username)
      endpoint = "https://www.instagram.com/#{username}/?__a=1"
      result = IgApi::Http.new.get(endpoint).with(session: user.session, ua: user.useragent).exec

      response = JSON.parse result.body, symbolize_names: true, object_class: OpenStruct
      response if response.graphql
    end

    def search_for_user(user, username)
      rank_token = IgApi::Http.generate_rank_token user.session.scan(/ds_user_id=([\d]+);/)[0][0]
      endpoint = 'https://i.instagram.com/api/v1/users/search/'
      param = format('?is_typehead=true&q=%s&rank_token=%s', username, rank_token)
      result = api.get(endpoint + param)
                   .with(session: user.session, ua: user.useragent).exec

      result = JSON.parse result.body, object_class: OpenStruct

      if result.num_results && result.num_results > 0
        result_users = result.users
        user_result = result_users.find { |u| u[:username] == username }
        user_object = IgApi::User.new username: username
        user_object.data = user_result
        user_object.session = user.session
        user_object
      end
    end

    def self.create_for_id(user, username, data)
      user_object = IgApi::User.new username: username
      user_object.data = data
      user_object.session = user.session
      user_object
    end

    def list_direct_messages(user, limit = 100)
      base_url = 'https://i.instagram.com/api/v1'
      rank_token = IgApi::Http.generate_rank_token user.session.scan(/ds_user_id=([\d]+);/)[0][0]

      endpoint = base_url + "/direct_v2/inbox/?persistentBadging=true&use_unified_inbox=true&show_threads=true&limit=#{limit}"
      param = format('&is_typehead=true&q=%s&rank_token=%s', user.username, rank_token)

      result = api.get(endpoint + param).with(session: user.session, ua: user.useragent).exec
      result = JSON.parse result.body, object_class: OpenStruct

      # fetch + combine past messages from parent thread
      all_messages = []
      result.inbox.threads.each do |thread|
        # thread_id = thread.thread_v2_id # => 17953972372244048 DO NOT USE V2!
        thread_id = thread.thread_id # => 340282366841710300949128223810596505168
        cursor_id = thread.oldest_cursor # '28623389310319272791051433794338816'

        thread_endpoint = base_url + "/direct_v2/threads/#{thread_id}/?cursor=#{cursor_id}"
        param = format('&is_typehead=true&q=%s&rank_token=%s', user.username, rank_token)

        result = api.get(thread_endpoint + param).with(session: user.session, ua: user.useragent).exec
        result = JSON.parse result.body, object_class: OpenStruct

        if result.thread && result.thread.items.count > 0
          older_messages = result.thread.items.sort_by(&:timestamp) # returns oldest --> newest
          all_messages << {
            thread_id: thread_id,
            recipient_username: thread.users.first.username, # possible to have 1+
            conversations: older_messages << thread.items.first
          }
        end
      end

      all_messages
    end
  end
end
