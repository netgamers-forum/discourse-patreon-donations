# frozen_string_literal: true

require 'rails_helper'

describe Jobs::SyncPatreonData do
  fab!(:campaign_id) { '9070965' }

  before do
    SiteSetting.patreon_donations_enabled = true
    SiteSetting.patreon_donations_campaign_id = campaign_id
    SiteSetting.patreon_donations_creator_access_token = 'test_token'
    SiteSetting.patreon_donations_sync_frequency = 24
  end

  let(:mock_client) { instance_double(DiscoursePatreonDonations::PatreonApiClient) }
  let(:campaign_data) { { 'attributes' => { 'patron_count' => 150 } } }
  let(:members) do
    [
      {
        'attributes' => {
          'patron_status' => 'active_patron',
          'currently_entitled_amount_cents' => 500,
          'last_charge_status' => 'Paid',
          'last_charge_date' => 1.month.ago.iso8601
        }
      }
    ]
  end

  describe '#execute' do
    before do
      allow(DiscoursePatreonDonations::PatreonApiClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:fetch_campaign_data).and_return(campaign_data)
      allow(mock_client).to receive(:fetch_members).and_return(members)
    end

    context 'when Patreon is disabled' do
      before { SiteSetting.patreon_donations_enabled = false }

      it 'does not sync' do
        expect(mock_client).not_to receive(:fetch_campaign_data)
        subject.execute({})
      end
    end

    context 'when sync frequency has not elapsed' do
      before do
        Rails.cache.write('patreon_last_sync_time', 1.hour.ago)
      end

      it 'does not sync' do
        expect(mock_client).not_to receive(:fetch_campaign_data)
        subject.execute({})
      end
    end

    context 'when sync should run' do
      before do
        Rails.cache.delete('patreon_last_sync_time')
      end

      it 'fetches data from Patreon API' do
        expect(mock_client).to receive(:fetch_campaign_data).and_return(campaign_data)
        expect(mock_client).to receive(:fetch_members).and_return(members)
        subject.execute({})
      end

      it 'caches the stats' do
        subject.execute({})
        
        cached = Rails.cache.read("patreon_stats:#{campaign_id}")
        expect(cached).to be_present
        expect(cached[:patron_count]).to eq(150)
        expect(cached[:monthly_estimate]).to eq(5.0)
      end

      it 'records monthly snapshot' do
        now = Time.now.utc
        
        freeze_time now do
          expect {
            subject.execute({})
          }.to change { DiscoursePatreonDonations::PatreonMonthlyStat.count }.by(1)

          stat = DiscoursePatreonDonations::PatreonMonthlyStat.last
          expect(stat.campaign_id).to eq(campaign_id)
          expect(stat.year).to eq(now.year)
          expect(stat.month).to eq(now.month)
          expect(stat.patron_count).to eq(150)
        end
      end

      it 'updates sync time' do
        subject.execute({})
        expect(Rails.cache.read('patreon_last_sync_time')).to be_present
      end

      it 'logs the snapshot' do
        Rails.logger.expects(:info).with(includes('Recorded monthly snapshot'))
        subject.execute({})
      end
    end

    context 'when API returns nil data' do
      before do
        Rails.cache.delete('patreon_last_sync_time')
        allow(mock_client).to receive(:fetch_campaign_data).and_return(nil)
      end

      it 'does not cache stats' do
        subject.execute({})
        expect(Rails.cache.read("patreon_stats:#{campaign_id}")).to be_nil
      end

      it 'does not record monthly snapshot' do
        expect {
          subject.execute({})
        }.not_to change { DiscoursePatreonDonations::PatreonMonthlyStat.count }
      end
    end

    context 'when an error occurs' do
      before do
        Rails.cache.delete('patreon_last_sync_time')
        allow(mock_client).to receive(:fetch_campaign_data).and_raise(StandardError.new('API Error'))
      end

      it 'logs the error' do
        Rails.logger.expects(:error).with(includes('Patreon sync job failed'))
        Rails.logger.expects(:error).with(instance_of(String))
        subject.execute({})
      end

      it 'does not raise the error' do
        expect { subject.execute({}) }.not_to raise_error
      end
    end
  end
end
