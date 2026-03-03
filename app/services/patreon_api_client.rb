# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonApiClient
    BASE_URL_V1 = 'https://api.patreon.com/oauth2/api'
    BASE_URL_V2 = 'https://www.patreon.com/api/oauth2/v2'
    
    def initialize(access_token: nil, campaign_id: nil)
      @access_token = (access_token || SiteSetting.patreon_creator_access_token).to_s.strip
      @campaign_id = (campaign_id || SiteSetting.patreon_donations_campaign_id).to_s.strip
      @api_version = SiteSetting.patreon_donations_api_version || 'v2'

      if @access_token.blank?
        Rails.logger.error("Patreon API: No access token configured!")
      else
        Rails.logger.info("Patreon API: Using access token (length: #{@access_token.length})")
        Rails.logger.info("Patreon API: Using API version #{@api_version}")
      end
    end

    def fetch_campaign_data
      if @api_version == 'v1'
        fetch_campaign_data_v1
      else
        fetch_campaign_data_v2
      end
    end

    def fetch_all_campaigns
      if @api_version == 'v1'
        fetch_all_campaigns_v1
      else
        fetch_all_campaigns_v2
      end
    end

    def fetch_members
      if @api_version == 'v1'
        fetch_members_v1
      else
        fetch_members_v2
      end
    end

    def discover_campaign_id(campaign_url)
      return nil if campaign_url.blank?

      vanity_name = extract_vanity_name(campaign_url)
      return nil if vanity_name.blank?

      campaigns = fetch_all_campaigns
      matching_campaign = campaigns.find do |campaign|
        campaign.dig('attributes', 'vanity') == vanity_name
      end

      matching_campaign&.dig('id')
    end

    private

    # V2 API methods
    def fetch_campaign_data_v2
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'patron_count,is_monthly,creation_name' }
      
      response = make_request(endpoint, params)
      response&.dig('data', 0)
    end

    def fetch_all_campaigns_v2
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'vanity,patron_count,is_monthly,creation_name' }
      
      response = make_request(endpoint, params)
      response&.dig('data') || []
    end

    def fetch_members_v2
      all_members = []
      cursor = nil

      loop do
        endpoint = "/campaigns/#{@campaign_id}/members"
        params = {
          'fields[member]' => 'currently_entitled_amount_cents,patron_status,last_charge_date,last_charge_status',
          'page[count]' => '1000'
        }
        params['page[cursor]'] = cursor if cursor

        response = make_request(endpoint, params)
        break unless response

        all_members.concat(response['data'] || [])
        cursor = response.dig('meta', 'pagination', 'cursors', 'next')
        break unless cursor
      end

      all_members
    end

    # V1 API methods
    def fetch_campaign_data_v1
      # V1 API uses include parameter to get related data in one request
      endpoint = '/current_user/campaigns'
      params = { 'include' => 'pledges' }
      
      response = make_request(endpoint, params)
      Rails.logger.warn("V1 API - Campaign response present: #{response.present?}")
      Rails.logger.warn("V1 API - Response data: #{response&.dig('data')&.length || 0} campaigns")
      
      # V1 returns campaigns in 'data' array
      campaigns = response&.dig('data') || []
      campaign = campaigns.first
      
      # Auto-populate campaign_id if empty (V1 discovers it from the API)
      if campaign && @campaign_id.blank?
        discovered_id = campaign['id']
        if discovered_id.present?
          Rails.logger.warn("V1 API - Auto-discovered campaign_id: #{discovered_id}")
          SiteSetting.patreon_donations_campaign_id = discovered_id
          @campaign_id = discovered_id
        end
      end
      
      Rails.logger.warn("V1 API - Campaign attributes: #{campaign&.dig('attributes')&.keys&.join(', ')}")
      
      # Log full attributes for debugging
      if campaign
        attrs = campaign['attributes'] || {}
        Rails.logger.warn("V1 API - Campaign full attributes: #{attrs.inspect}")
      end
      
      campaign
    end

    def fetch_all_campaigns_v1
      endpoint = '/current_user/campaigns'
      params = {}
      
      response = make_request(endpoint, params)
      response&.dig('data') || []
    end

    def fetch_members_v1
      # V1 API has a dedicated pledges endpoint that supports pagination
      return [] if @campaign_id.blank?
      
      all_pledges = []
      page_url = "/campaigns/#{@campaign_id}/pledges"
      page = 1
      
      loop do
        Rails.logger.warn("V1 API - Fetching pledges page #{page} from: #{page_url}")
        
        response = make_request(page_url, {})
        break unless response
        
        Rails.logger.warn("V1 API - Page #{page}: Response data count: #{response['data']&.length || 0}")
        
        # V1 pledges endpoint returns pledges directly in 'data' array
        page_pledges = response['data'] || []
        all_pledges.concat(page_pledges)
        
        Rails.logger.warn("V1 API - Page #{page}: Found #{page_pledges.length} pledges (total: #{all_pledges.length})")
        
        # Check for next page in links
        next_link = response.dig('links', 'next')
        Rails.logger.warn("V1 API - Next link: #{next_link.inspect}")
        break unless next_link.present?
        
        # The next link is a full URL, we need just the path and query
        page_url = extract_path_from_url(next_link)
        break unless page_url
        
        page += 1
        
        # Safety limit to prevent infinite loops
        break if page > 20
      end
      
      Rails.logger.warn("V1 API - Total pledges fetched: #{all_pledges.length}")
      
      # V1 pledges need to be converted to v2 member format for compatibility
      members = convert_pledges_to_members(all_pledges)
      Rails.logger.warn("V1 API - Converted to #{members.length} members")
      members
    end

    def extract_path_from_url(url)
      return nil unless url
      
      uri = URI.parse(url)
      path = uri.path
      
      # Remove the API base path if it's included in the next URL
      # v1 base: /oauth2/api, but next URLs may include /api/oauth2/api
      # v2 base: /api/oauth2/v2
      if @api_version == 'v1'
        # Strip both possible v1 path prefixes
        path = path.sub(%r{^/api/oauth2/api}, '')
        path = path.sub(%r{^/oauth2/api}, '')
      elsif @api_version == 'v2'
        path = path.sub(%r{^/api/oauth2/v2}, '')
      end
      
      # Add query string if present
      path += "?#{uri.query}" if uri.query
      
      Rails.logger.warn("V1 API - Extracted path from next URL: #{path}")
      path
    rescue StandardError => e
      Rails.logger.error("Failed to extract path from URL: #{e.message}")
      nil
    end
    
    def convert_pledges_to_members(pledges)
      pledges.map do |pledge|
        attrs = pledge['attributes'] || {}
        amount_cents = attrs['amount_cents'] || 0
        
        Rails.logger.warn("V1 Pledge: id=#{pledge['id']}, amount_cents=#{amount_cents}, declined=#{attrs['declined_since']}")
        
        {
          'id' => pledge['id'],
          'type' => 'member',
          'attributes' => {
            'currently_entitled_amount_cents' => amount_cents,
            'patron_status' => pledge_status_to_patron_status(pledge),
            'last_charge_date' => attrs['created_at'],
            'last_charge_status' => attrs['declined_since'] ? 'Declined' : 'Paid'
          }
        }
      end
    end
    
    def pledge_status_to_patron_status(pledge)
      if pledge.dig('attributes', 'declined_since')
        'declined_patron'
      else
        'active_patron'
      end
    end

    MAX_RETRIES = 3
    BASE_DELAY = 2

    def make_request(endpoint, params = {}, retry_count: 0)
      uri = build_uri(endpoint, params)
      response = make_http_request(uri)

      case response
      when Net::HTTPSuccess
        handle_response(response)
      when Net::HTTPUnauthorized
        if retry_count == 0 && refresh_access_token
          Rails.logger.info("Patreon API: Retrying request after token refresh")
          make_request(endpoint, params, retry_count: retry_count + 1)
        else
          handle_response(response)
        end
      when Net::HTTPTooManyRequests
        if retry_count < MAX_RETRIES
          retry_after = response['Retry-After']&.to_i
          delay = [BASE_DELAY ** (retry_count + 1), retry_after || 0].max
          Rails.logger.warn("Patreon API: Rate limited, retrying in #{delay}s (attempt #{retry_count + 1}/#{MAX_RETRIES})")
          sleep(delay)
          make_request(endpoint, params, retry_count: retry_count + 1)
        else
          handle_response(response)
        end
      else
        handle_response(response)
      end
    rescue StandardError => e
      Rails.logger.error("Patreon API error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?
      nil
    end

    def make_http_request(uri)
      redirect_limit = 5
      redirect_count = 0

      loop do
        request = build_request(uri)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        case response
        when Net::HTTPRedirection
          redirect_count += 1
          if redirect_count > redirect_limit
            Rails.logger.error("Patreon API: Too many redirects (>#{redirect_limit})")
            return response
          end

          location = response['location']
          Rails.logger.info("Patreon API: Following redirect to #{location}")
          uri = URI(location)
        else
          return response
        end
      end
    end

    def refresh_access_token
      refresh_token = SiteSetting.patreon_creator_refresh_token
      client_id = SiteSetting.patreon_client_id
      client_secret = SiteSetting.patreon_client_secret

      if refresh_token.blank? || client_id.blank? || client_secret.blank?
        Rails.logger.error("Patreon API: Cannot refresh token - missing refresh_token, client_id, or client_secret")
        return false
      end

      Rails.logger.info("Patreon API: Attempting token refresh")

      uri = URI("https://www.patreon.com/api/oauth2/token")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: client_id,
        client_secret: client_secret
      )

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        SiteSetting.patreon_creator_access_token = data["access_token"]
        @access_token = data["access_token"]

        if data["refresh_token"].present?
          SiteSetting.patreon_creator_refresh_token = data["refresh_token"]
        end

        Rails.logger.info("Patreon API: Access token refreshed successfully")
        true
      else
        Rails.logger.error("Patreon API: Token refresh failed - HTTP #{response.code}: #{response.body[0..200]}")
        false
      end
    rescue StandardError => e
      Rails.logger.error("Patreon API: Token refresh error - #{e.message}")
      false
    end

    def build_uri(endpoint, params)
      base_url = @api_version == 'v1' ? BASE_URL_V1 : BASE_URL_V2
      uri = URI("#{base_url}#{endpoint}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      Rails.logger.info("Patreon API: Requesting #{uri}")
      uri
    end

    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"
      request['User-Agent'] = user_agent
      request
    end

    def handle_response(response)
      case response.code.to_i
      when 200
        Rails.logger.info("Patreon API: Success (200)")
        JSON.parse(response.body)
      when 401
        Rails.logger.error("Patreon API: Unauthorized (401) - Invalid or expired access token")
        Rails.logger.error("  Token length: #{@access_token&.length || 0} characters")
        Rails.logger.error("  Token starts with: #{@access_token[0..10]}...") if @access_token
        Rails.logger.error("  Please check your Creator Access Token in plugin settings")
        Rails.logger.error("  Response: #{response.body[0..200]}") if response.body
        nil
      when 403
        Rails.logger.error("Patreon API: Forbidden (403) - Token may be missing required scopes")
        Rails.logger.error("  Required scopes: 'campaigns' and 'campaigns.members'")
        Rails.logger.error("  Response: #{response.body[0..200]}") if response.body
        nil
      when 429
        Rails.logger.warn("Patreon API: Rate limited (429) - retry after #{response['Retry-After']} seconds")
        nil
      else
        Rails.logger.error("Patreon API error: HTTP #{response.code}")
        Rails.logger.error("Response body: #{response.body[0..500]}") if response.body
        nil
      end
    end

    def extract_vanity_name(url)
      # Strip protocol and www if present
      cleaned_url = url.gsub(%r{^https?://(www\.)?}, '')
      
      # Extract vanity name from patreon.com/vanity_name format
      if cleaned_url.match?(%r{^patreon\.com/([^/\?]+)})
        cleaned_url.match(%r{^patreon\.com/([^/\?]+)})[1]
      else
        # If just the vanity name is provided
        cleaned_url.split('/').first
      end
    end

    def user_agent
      "Discourse-Patreon-Plugin/#{DiscoursePatreonDonations::PLUGIN_NAME}"
    end
  end
end
