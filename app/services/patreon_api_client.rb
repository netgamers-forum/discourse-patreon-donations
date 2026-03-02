# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonApiClient
    BASE_URL = 'https://www.patreon.com/api/oauth2/v2'
    
    def initialize(access_token: nil, campaign_id: nil)
    @access_token = (access_token || SiteSetting.patreon_donations_creator_access_token).to_s.strip
    @campaign_id = (campaign_id || SiteSetting.patreon_donations_campaign_id).to_s.strip
    
    if @access_token.blank?
      Rails.logger.error("Patreon API: No access token configured!")
    else
      Rails.logger.info("Patreon API: Using access token (length: #{@access_token.length})")
    end

    def fetch_campaign_data
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'patron_count,is_monthly,creation_name' }
      
      response = make_request(endpoint, params)
      response&.dig('data', 0)
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

    def fetch_all_campaigns
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'vanity,patron_count,is_monthly,creation_name' }
      
      response = make_request(endpoint, params)
      response&.dig('data') || []
    end

    def fetch_members
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

    private

    def make_request(endpoint, params = {})
      uri = build_uri(endpoint, params)
      
      # Follow redirects (up to 5 times)
      redirect_limit = 5
      redirect_count = 0
      
      loop do
        request = build_request(uri)
        
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end
        
        case response
        when Net::HTTPSuccess
          return handle_response(response)
        when Net::HTTPRedirection
          redirect_count += 1
          if redirect_count > redirect_limit
            Rails.logger.error("Patreon API: Too many redirects (>#{redirect_limit})")
            return nil
          end
          
          location = response['location']
          Rails.logger.info("Patreon API: Following redirect to #{location}")
          uri = URI(location)
        else
          return handle_response(response)
        end
      end
    rescue StandardError => e
      Rails.logger.error("Patreon API error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?
      nil
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
