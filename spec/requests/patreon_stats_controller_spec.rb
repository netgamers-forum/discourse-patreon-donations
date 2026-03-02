# frozen_string_literal: true

require 'rails_helper'

describe DiscoursePatreonDonations::PatreonStatsController do
  before do
    SiteSetting.patreon_donations_enabled = true
    SiteSetting.patreon_donations_campaign_id = '9070965'
  end

  describe '#show' do
    context 'when Patreon is not enabled' do
      before { SiteSetting.patreon_donations_enabled = false }

      it 'returns 503 error' do
        get '/patreon-stats.json'
        expect(response.status).to eq(503)
      end

      it 'returns error message' do
        get '/patreon-stats.json'
        json = JSON.parse(response.body)
        expect(json['errors']).to be_present
      end
    end

    context 'when Patreon is enabled' do
      let(:cached_stats) do
        {
          patron_count: 150,
          monthly_estimate: 75.50,
          last_month_total: 70.25,
          updated_at: Time.now.utc
        }
      end

      let(:monthly_history) do
        [
          { year: 2026, month: 1, patron_count: 140, total_amount: 65.0, total_amount_cents: 6500 },
          { year: 2026, month: 2, patron_count: 145, total_amount: 70.0, total_amount_cents: 7000 },
          { year: 2026, month: 3, patron_count: 150, total_amount: 75.5, total_amount_cents: 7550 }
        ]
      end

      before do
        Rails.cache.write("patreon_stats:9070965", cached_stats)
        
        monthly_history.each do |record|
          DiscoursePatreonDonations::PatreonMonthlyStat.create!(
            campaign_id: '9070965',
            year: record[:year],
            month: record[:month],
            patron_count: record[:patron_count],
            total_amount_cents: record[:total_amount_cents]
          )
        end
      end

      it 'returns current stats' do
        get '/patreon-stats.json'
        expect(response.status).to eq(200)

        json = JSON.parse(response.body)
        expect(json['stats']['patron_count']).to eq(150)
        expect(json['stats']['monthly_estimate']).to eq(75.50)
      end

      it 'returns monthly history' do
        get '/patreon-stats.json'
        expect(response.status).to eq(200)

        json = JSON.parse(response.body)
        expect(json['monthly_history']).to be_present
        expect(json['monthly_history'].length).to eq(3)
        expect(json['monthly_history'].last['patron_count']).to eq(150)
      end

      it 'caches the response' do
        get '/patreon-stats.json'
        get '/patreon-stats.json'

        expect(Rails.cache.read("patreon_stats:9070965")).to be_present
      end
    end

    context 'when cache is empty and API fails' do
      before do
        Rails.cache.clear
        allow_any_instance_of(DiscoursePatreonDonations::PatreonApiClient)
          .to receive(:fetch_campaign_data).and_return(nil)
      end

      it 'returns 503 error' do
        get '/patreon-stats.json'
        expect(response.status).to eq(503)
      end
    end
  end
end
