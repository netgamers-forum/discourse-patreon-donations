# frozen_string_literal: true

module DiscoursePatreonDonations
  class PatreonStatsCalculator
    def initialize(campaign_data, members)
      @campaign_data = campaign_data
      @members = members
    end

    def patron_count
      @campaign_data&.dig('attributes', 'patron_count') || 0
    end

    def currency
      @campaign_data&.dig('attributes', 'currency') || 'USD'
    end

    def monthly_estimate
      total_cents = active_members.sum { |m| entitled_amount(m) }

      # Patreon v1 API no longer returns amount_cents on individual pledges.
      # Fall back to campaign_pledge_sum (in cents) from the campaign object.
      if total_cents == 0 && active_members.any?
        pledge_sum = @campaign_data&.dig('attributes', 'campaign_pledge_sum').to_i
        if pledge_sum > 0
          Rails.logger.warn("Monthly estimate: using campaign_pledge_sum #{pledge_sum} cents")
          return pledge_sum / 100.0
        end
      end

      Rails.logger.warn("Monthly estimate calculation: #{active_members.count} active members, #{total_cents} total cents, $#{total_cents / 100.0}")
      total_cents / 100.0
    end

    def active_member_ids
      active_members.map { |m| m['id'] }.compact.sort
    end

    def last_month_total
      last_month_members.sum { |m| entitled_amount(m) } / 100.0
    end

    private

    def active_members
      @active_members ||= @members.select { |m| patron_status(m) == 'active_patron' }
    end

    def last_month_members
      @last_month_members ||= @members.select do |m|
        charge_status(m) == 'Paid' && charged_last_month?(m)
      end
    end

    def patron_status(member)
      member.dig('attributes', 'patron_status')
    end

    def charge_status(member)
      member.dig('attributes', 'last_charge_status')
    end

    def entitled_amount(member)
      member.dig('attributes', 'currently_entitled_amount_cents') || 0
    end

    def charged_last_month?(member)
      charge_date_str = member.dig('attributes', 'last_charge_date')
      return false unless charge_date_str

      charge_date = Time.parse(charge_date_str)
      last_month_start = Time.now.utc.beginning_of_month - 1.month
      last_month_end = Time.now.utc.beginning_of_month - 1.second

      charge_date >= last_month_start && charge_date <= last_month_end
    rescue ArgumentError => e
      Rails.logger.error("Invalid date format: #{e.message}")
      false
    end
  end
end
