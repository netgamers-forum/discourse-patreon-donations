# frozen_string_literal: true

require 'rails_helper'

describe DiscoursePatreonDonations::PatreonMonthlyStat do
  fab!(:campaign_id) { '9070965' }

  describe 'validations' do
    it 'validates presence of campaign_id' do
      stat = described_class.new(year: 2026, month: 3, patron_count: 10, total_amount_cents: 1000)
      expect(stat).not_to be_valid
      expect(stat.errors[:campaign_id]).to be_present
    end

    it 'validates presence of year' do
      stat = described_class.new(campaign_id: campaign_id, month: 3, patron_count: 10, total_amount_cents: 1000)
      expect(stat).not_to be_valid
      expect(stat.errors[:year]).to be_present
    end

    it 'validates presence of month' do
      stat = described_class.new(campaign_id: campaign_id, year: 2026, patron_count: 10, total_amount_cents: 1000)
      expect(stat).not_to be_valid
      expect(stat.errors[:month]).to be_present
    end

    it 'validates month is between 1 and 12' do
      stat = described_class.new(campaign_id: campaign_id, year: 2026, month: 13, patron_count: 10, total_amount_cents: 1000)
      expect(stat).not_to be_valid
      expect(stat.errors[:month]).to be_present
    end

    it 'validates patron_count is not negative' do
      stat = described_class.new(campaign_id: campaign_id, year: 2026, month: 3, patron_count: -1, total_amount_cents: 1000)
      expect(stat).not_to be_valid
      expect(stat.errors[:patron_count]).to be_present
    end

    it 'validates total_amount_cents is not negative' do
      stat = described_class.new(campaign_id: campaign_id, year: 2026, month: 3, patron_count: 10, total_amount_cents: -100)
      expect(stat).not_to be_valid
      expect(stat.errors[:total_amount_cents]).to be_present
    end
  end

  describe '.record_monthly_snapshot' do
    it 'creates a new record when none exists' do
      expect {
        described_class.record_monthly_snapshot(campaign_id, 150, 5000, Time.utc(2026, 3, 1))
      }.to change { described_class.count }.by(1)

      stat = described_class.last
      expect(stat.campaign_id).to eq(campaign_id)
      expect(stat.year).to eq(2026)
      expect(stat.month).to eq(3)
      expect(stat.patron_count).to eq(150)
      expect(stat.total_amount_cents).to eq(5000)
    end

    it 'updates existing record for same month' do
      existing = described_class.create!(
        campaign_id: campaign_id,
        year: 2026,
        month: 3,
        patron_count: 100,
        total_amount_cents: 3000
      )

      expect {
        described_class.record_monthly_snapshot(campaign_id, 150, 5000, Time.utc(2026, 3, 15))
      }.not_to change { described_class.count }

      existing.reload
      expect(existing.patron_count).to eq(150)
      expect(existing.total_amount_cents).to eq(5000)
    end

    it 'cleans up old records beyond 12 months' do
      # Create 15 months of data
      15.times do |i|
        date = i.months.ago.beginning_of_month
        described_class.create!(
          campaign_id: campaign_id,
          year: date.year,
          month: date.month,
          patron_count: 100,
          total_amount_cents: 5000
        )
      end

      described_class.record_monthly_snapshot(campaign_id, 150, 5000, Time.now.utc)

      # Should keep only 12 records
      expect(described_class.where(campaign_id: campaign_id).count).to eq(12)
    end
  end

  describe '.last_12_months' do
    before do
      # Create 15 months of data
      15.times do |i|
        date = i.months.ago.beginning_of_month
        described_class.create!(
          campaign_id: campaign_id,
          year: date.year,
          month: date.month,
          patron_count: 100 + i,
          total_amount_cents: 5000 + (i * 100)
        )
      end
    end

    it 'returns only 12 most recent months' do
      results = described_class.last_12_months(campaign_id)
      expect(results.count).to eq(12)
    end

    it 'returns results in chronological order (oldest first)' do
      results = described_class.last_12_months(campaign_id)
      expect(results.first.year).to be <= results.last.year
      
      if results.first.year == results.last.year
        expect(results.first.month).to be < results.last.month
      end
    end

    it 'filters by campaign_id' do
      other_campaign = '1111111'
      described_class.create!(
        campaign_id: other_campaign,
        year: 2026,
        month: 3,
        patron_count: 999,
        total_amount_cents: 99900
      )

      results = described_class.last_12_months(campaign_id)
      expect(results.all? { |r| r.campaign_id == campaign_id }).to be true
    end
  end

  describe '#total_amount' do
    it 'converts cents to dollars' do
      stat = described_class.new(total_amount_cents: 5000)
      expect(stat.total_amount).to eq(50.0)
    end

    it 'handles zero amount' do
      stat = described_class.new(total_amount_cents: 0)
      expect(stat.total_amount).to eq(0.0)
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      stat = described_class.new(
        year: 2026,
        month: 3,
        patron_count: 150,
        total_amount_cents: 5000
      )

      result = stat.to_h
      expect(result).to eq({
        year: 2026,
        month: 3,
        patron_count: 150,
        total_amount: 50.0,
        total_amount_cents: 5000
      })
    end
  end
end
