# frozen_string_literal: true

require 'rails_helper'

describe DiscoursePatreonDonations::PatreonCampaignDiscovery do
  fab!(:admin) { Fabricate(:admin) }

  before do
    SiteSetting.patreon_enabled = true
    SiteSetting.patreon_creator_access_token = 'test_token_123'
  end

  describe '.discover_and_save' do
    let(:mock_client) { instance_double(DiscoursePatreonDonations::PatreonApiClient) }

    before do
      allow(DiscoursePatreonDonations::PatreonApiClient).to receive(:new).and_return(mock_client)
    end

    context 'when campaign ID is successfully discovered' do
      before do
        allow(mock_client).to receive(:discover_campaign_id).and_return('9070965')
      end

      it 'saves the campaign ID to settings' do
        described_class.discover_and_save
        expect(SiteSetting.patreon_campaign_id).to eq('9070965')
      end

      it 'returns true' do
        expect(described_class.discover_and_save).to be true
      end

      it 'logs success message' do
        Rails.logger.expects(:info).with(includes('9070965'))
        described_class.discover_and_save
      end
    end

    context 'when campaign ID discovery returns nil' do
      before do
        allow(mock_client).to receive(:discover_campaign_id).and_return(nil)
      end

      it 'does not update settings' do
        original_id = SiteSetting.patreon_campaign_id
        described_class.discover_and_save
        expect(SiteSetting.patreon_campaign_id).to eq(original_id)
      end

      it 'returns false' do
        expect(described_class.discover_and_save).to be false
      end

      it 'logs error message' do
        Rails.logger.expects(:error).with(includes('Failed'))
        described_class.discover_and_save
      end
    end

    context 'when access token is not present' do
      before do
        SiteSetting.patreon_creator_access_token = ''
      end

      it 'returns false without calling API' do
        expect(DiscoursePatreonDonations::PatreonApiClient).not_to receive(:new)
        expect(described_class.discover_and_save).to be false
      end
    end

    context 'when API client raises an error' do
      before do
        allow(mock_client).to receive(:discover_campaign_id).and_raise(StandardError.new('API Error'))
      end

      it 'returns false' do
        expect(described_class.discover_and_save).to be false
      end

      it 'logs the error' do
        Rails.logger.expects(:error).with(includes('API Error'))
        described_class.discover_and_save
      end
    end
  end
end
