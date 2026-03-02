# frozen_string_literal: true

require 'rails_helper'

describe DiscoursePatreonDonations::PatreonStatsCalculator do
  let(:campaign_data) do
    {
      'attributes' => {
        'patron_count' => 150
      }
    }
  end

  let(:active_member_1) do
    {
      'attributes' => {
        'patron_status' => 'active_patron',
        'currently_entitled_amount_cents' => 500,
        'last_charge_status' => 'Paid',
        'last_charge_date' => 1.month.ago.beginning_of_month.iso8601
      }
    }
  end

  let(:active_member_2) do
    {
      'attributes' => {
        'patron_status' => 'active_patron',
        'currently_entitled_amount_cents' => 1000,
        'last_charge_status' => 'Paid',
        'last_charge_date' => 1.month.ago.beginning_of_month.iso8601
      }
    }
  end

  let(:declined_member) do
    {
      'attributes' => {
        'patron_status' => 'declined_patron',
        'currently_entitled_amount_cents' => 300,
        'last_charge_status' => 'Declined',
        'last_charge_date' => 2.months.ago.iso8601
      }
    }
  end

  let(:former_member) do
    {
      'attributes' => {
        'patron_status' => 'former_patron',
        'currently_entitled_amount_cents' => 0,
        'last_charge_status' => 'Deleted',
        'last_charge_date' => 3.months.ago.iso8601
      }
    }
  end

  describe '#patron_count' do
    it 'returns patron count from campaign data' do
      calculator = described_class.new(campaign_data, [])
      expect(calculator.patron_count).to eq(150)
    end

    it 'returns 0 when campaign data is nil' do
      calculator = described_class.new(nil, [])
      expect(calculator.patron_count).to eq(0)
    end

    it 'returns 0 when patron_count attribute is missing' do
      calculator = described_class.new({ 'attributes' => {} }, [])
      expect(calculator.patron_count).to eq(0)
    end
  end

  describe '#monthly_estimate' do
    it 'sums only active patron amounts and converts to dollars' do
      members = [active_member_1, active_member_2, declined_member, former_member]
      calculator = described_class.new(campaign_data, members)
      
      expect(calculator.monthly_estimate).to eq(15.0) # (500 + 1000) / 100
    end

    it 'returns 0 when no active members' do
      members = [declined_member, former_member]
      calculator = described_class.new(campaign_data, members)
      
      expect(calculator.monthly_estimate).to eq(0.0)
    end

    it 'returns 0 when members array is empty' do
      calculator = described_class.new(campaign_data, [])
      expect(calculator.monthly_estimate).to eq(0.0)
    end

    it 'handles nil entitled_amount_cents gracefully' do
      member_with_nil = {
        'attributes' => {
          'patron_status' => 'active_patron',
          'currently_entitled_amount_cents' => nil
        }
      }
      calculator = described_class.new(campaign_data, [member_with_nil])
      expect(calculator.monthly_estimate).to eq(0.0)
    end
  end

  describe '#last_month_total' do
    it 'sums amounts for paid charges from last month' do
      members = [active_member_1, active_member_2, declined_member]
      calculator = described_class.new(campaign_data, members)
      
      expect(calculator.last_month_total).to eq(15.0) # (500 + 1000) / 100
    end

    it 'excludes declined charges' do
      members = [active_member_1, declined_member]
      calculator = described_class.new(campaign_data, members)
      
      expect(calculator.last_month_total).to eq(5.0) # 500 / 100
    end

    it 'excludes charges from other months' do
      old_member = {
        'attributes' => {
          'patron_status' => 'active_patron',
          'currently_entitled_amount_cents' => 2000,
          'last_charge_status' => 'Paid',
          'last_charge_date' => 3.months.ago.iso8601
        }
      }
      members = [active_member_1, old_member]
      calculator = described_class.new(campaign_data, members)
      
      expect(calculator.last_month_total).to eq(5.0) # Only active_member_1
    end

    it 'returns 0 when no valid charges' do
      calculator = described_class.new(campaign_data, [former_member])
      expect(calculator.last_month_total).to eq(0.0)
    end

    it 'handles invalid date formats gracefully' do
      invalid_date_member = {
        'attributes' => {
          'patron_status' => 'active_patron',
          'currently_entitled_amount_cents' => 500,
          'last_charge_status' => 'Paid',
          'last_charge_date' => 'invalid-date'
        }
      }
      calculator = described_class.new(campaign_data, [invalid_date_member])
      expect(calculator.last_month_total).to eq(0.0)
    end
  end
end
