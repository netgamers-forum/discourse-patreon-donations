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

    def active_patron_count
      active_members.length
    end

    def free_member_count
      @members.count { |m| patron_status(m).nil? }
    end

    def total_member_count
      @members.length
    end

    def currency
      @campaign_data&.dig('attributes', 'currency') || 'USD'
    end

    def monthly_estimate
      log_member_status_breakdown

      total_cents = active_members.sum { |m| entitled_amount(m) }
      Rails.logger.warn("Monthly estimate calculation: #{active_members.count} active members, #{total_cents} total cents, $#{total_cents / 100.0}")
      total_cents / 100.0
    end

    def active_member_ids
      active_members.map { |m| m['id'] }.compact.sort
    end

    def declined_patrons_count
      declined_members.length
    end

    def recently_declined_count
      recently_declined_members.length
    end

    def recently_declined_amount
      recently_declined_members.sum { |m| tier_or_entitled_amount(m) } / 100.0
    end

    # Calculates total processing fees based on per-member pledge amounts.
    # Patreon charges different rates for payments under/over $3.
    def processing_fee_estimate(standard_pct:, standard_fixed_cents:, micro_pct:, micro_fixed_cents:, threshold_cents: 300)
      result = processing_fee_breakdown(
        standard_pct: standard_pct, standard_fixed_cents: standard_fixed_cents,
        micro_pct: micro_pct, micro_fixed_cents: micro_fixed_cents,
        threshold_cents: threshold_cents
      )
      result.sum { |r| r[:fee] }
    end

    # Returns per-tier breakdown of processing fees for display
    def processing_fee_breakdown(standard_pct:, standard_fixed_cents:, micro_pct:, micro_fixed_cents:, threshold_cents: 300)
      groups = active_members.group_by { |m| entitled_amount(m) }

      groups.map do |amount_cents, members|
        count = members.length
        if amount_cents >= threshold_cents
          fee_per = (amount_cents * standard_pct / 100.0) + standard_fixed_cents
          rate_label = "#{standard_pct}% + $#{standard_fixed_cents / 100.0}"
        else
          fee_per = (amount_cents * micro_pct / 100.0) + micro_fixed_cents
          rate_label = "#{micro_pct}% + $#{micro_fixed_cents / 100.0}"
        end

        {
          amount: amount_cents / 100.0,
          count: count,
          rate: rate_label,
          fee_per: fee_per / 100.0,
          fee: (fee_per * count) / 100.0
        }
      end.sort_by { |r| r[:amount] }
    end

    def last_month_total
      last_month_members.sum { |m| entitled_amount(m) } / 100.0
    end

    private

    def active_members
      @active_members ||= @members.select { |m| patron_status(m) == 'active_patron' }
    end

    def declined_members
      @declined_members ||= @members.select { |m| patron_status(m) == 'declined_patron' }
    end

    def recently_declined_members
      @recently_declined_members ||= declined_members.select { |m| declined_recently?(m) }
    end

    def log_member_status_breakdown
      statuses = @members.group_by { |m| patron_status(m) || 'nil' }
      Rails.logger.warn("Patreon member breakdown: #{@members.length} total members fetched")
      statuses.each do |status, members|
        total_cents = members.sum { |m| entitled_amount(m) }
        Rails.logger.warn("  #{status}: #{members.length} members, #{total_cents} cents ($#{total_cents / 100.0})")
      end
      Rails.logger.warn("  Campaign-level patron_count: #{@campaign_data&.dig('attributes', 'patron_count')}")
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

    # For declined patrons, Patreon zeros out currently_entitled_amount_cents.
    # Prefer tier amount (matches displayed price) over will_pay (includes fees).
    def tier_or_entitled_amount(member)
      amount = entitled_amount(member)
      return amount if amount > 0

      tier = member.dig('attributes', 'tier_amount_cents') || 0
      return tier if tier > 0

      member.dig('attributes', 'will_pay_amount_cents') || 0
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

    def declined_recently?(member, days: 25)
      charge_date_str = member.dig('attributes', 'last_charge_date')
      return false unless charge_date_str

      charge_date = Time.parse(charge_date_str)
      charge_date >= (Time.now.utc - days.days)
    rescue ArgumentError => e
      Rails.logger.error("Invalid date format: #{e.message}")
      false
    end
  end
end
