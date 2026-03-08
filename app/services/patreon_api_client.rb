# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonApiClient
    BASE_URL = 'https://www.patreon.com/api/oauth2/v2'

    attr_reader :tier_titles

    def initialize(access_token: nil, campaign_id: nil)
      @access_token = (access_token || SiteSetting.patreon_donations_creator_access_token).to_s.strip
      @campaign_id = (campaign_id || SiteSetting.patreon_donations_campaign_id).to_s.strip
      @tier_titles = {}

      if @access_token.blank?
        Rails.logger.error("Patreon API: No access token configured!")
      end
    end

    def fetch_campaign_data
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'patron_count,is_monthly,creation_name' }

      response = make_request(endpoint, params)
      response&.dig('data', 0)
    end

    def fetch_all_campaigns
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'vanity,patron_count,is_monthly,creation_name' }

      response = make_request(endpoint, params)
      response&.dig('data') || []
    end

    def fetch_members
      all_members = []
      tier_map = {}
      cursor = nil

      loop do
        endpoint = "/campaigns/#{@campaign_id}/members"
        params = {
          'fields[member]' => 'currently_entitled_amount_cents,will_pay_amount_cents,patron_status,last_charge_date,last_charge_status',
          'fields[tier]' => 'amount_cents,title',
          'include' => 'currently_entitled_tiers',
          'page[count]' => '1000'
        }
        params['page[cursor]'] = cursor if cursor

        response = make_request(endpoint, params)
        break unless response

        # Build tier lookup from included data
        (response['included'] || []).each do |included|
          next unless included['type'] == 'tier'
          amount = included.dig('attributes', 'amount_cents') || 0
          title = included.dig('attributes', 'title') || 'Unknown'
          tier_map[included['id']] = { amount_cents: amount, title: title }
        end

        all_members.concat(response['data'] || [])
        cursor = response.dig('meta', 'pagination', 'cursors', 'next')
        break unless cursor
      end

      # Build tier_titles map (amount_cents => title) for tier breakdown display
      @tier_titles = {}
      tier_map.each_value do |info|
        @tier_titles[info[:amount_cents]] = info[:title]
      end

      # Attach tier amount to each member for declined patron revenue calculation
      all_members.each do |member|
        tier_ids = member.dig('relationships', 'currently_entitled_tiers', 'data') || []
        tier_info = tier_ids.map { |t| tier_map[t['id']] }.compact
        tier_amount = tier_info.sum { |t| t[:amount_cents] }
        member['attributes']['tier_amount_cents'] = tier_amount if tier_amount > 0
      end

      # Log declined members to debug tier/amount resolution
      declined = all_members.select { |m| m.dig('attributes', 'patron_status') == 'declined_patron' }
      if declined.any?
        Rails.logger.warn("Patreon API: #{declined.length} declined members found")
        declined.first(3).each do |m|
          attrs = m['attributes']
          rels = m.dig('relationships', 'currently_entitled_tiers', 'data') || []
          Rails.logger.warn("  Declined member #{m['id']}: entitled=#{attrs['currently_entitled_amount_cents']}, will_pay=#{attrs['will_pay_amount_cents']}, tier_amount=#{attrs['tier_amount_cents']}, tier_ids=#{rels.map { |t| t['id'] }}")
        end
      end

      all_members
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
      refresh_token = SiteSetting.patreon_donations_creator_refresh_token
      client_id = SiteSetting.patreon_donations_client_id
      client_secret = SiteSetting.patreon_donations_client_secret

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
        SiteSetting.patreon_donations_creator_access_token = data["access_token"]
        @access_token = data["access_token"]

        if data["refresh_token"].present?
          SiteSetting.patreon_donations_creator_refresh_token = data["refresh_token"]
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
      uri = URI("#{BASE_URL}#{endpoint}")
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
      cleaned_url = url.gsub(%r{^https?://(www\.)?}, '')

      if cleaned_url.match?(%r{^patreon\.com/([^/\?]+)})
        cleaned_url.match(%r{^patreon\.com/([^/\?]+)})[1]
      else
        cleaned_url.split('/').first
      end
    end

    def user_agent
      "Discourse-Patreon-Plugin/#{DiscoursePatreonDonations::PLUGIN_NAME}"
    end
  end
end
