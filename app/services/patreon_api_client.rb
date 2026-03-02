# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonApiClient
    BASE_URL = 'https://www.patreon.com/api/oauth2/v2'
    
    def initialize
      @access_token = SiteSetting.patreon_creator_access_token
      @campaign_id = SiteSetting.patreon_campaign_id
    end

    def fetch_campaign_data
      endpoint = '/campaigns'
      params = { 'fields[campaign]' => 'patron_count,is_monthly,creation_name' }
      
      response = make_request(endpoint, params)
      response&.dig('data', 0)
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
      request = build_request(uri)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      handle_response(response)
    rescue StandardError => e
      Rails.logger.error("Patreon API error: #{e.message}")
      nil
    end

    def build_uri(endpoint, params)
      uri = URI("#{BASE_URL}#{endpoint}")
      uri.query = URI.encode_www_form(params) unless params.empty?
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
        JSON.parse(response.body)
      when 401
        Rails.logger.error("Patreon API: Unauthorized - check access token")
        nil
      when 429
        Rails.logger.warn("Patreon API: Rate limited - retry after #{response['Retry-After']} seconds")
        nil
      else
        Rails.logger.error("Patreon API error: HTTP #{response.code}")
        nil
      end
    end

    def user_agent
      "Discourse-Patreon-Plugin/#{DiscoursePatreonDonations::PLUGIN_NAME}"
    end
  end
end
