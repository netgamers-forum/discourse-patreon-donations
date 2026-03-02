# frozen_string_literal: true

require 'rails_helper'

describe DiscoursePatreonDonations::PatreonApiClient do
  before do
    SiteSetting.patreon_donations_enabled = true
    SiteSetting.patreon_donations_creator_access_token = 'test_access_token'
    SiteSetting.patreon_donations_campaign_id = '9070965'
  end

  let(:client) { described_class.new }

  describe '#extract_vanity_name' do
    it 'extracts vanity name from full URL with https' do
      url = 'https://www.patreon.com/testcampaign'
      expect(client.send(:extract_vanity_name, url)).to eq('testcampaign')
    end

    it 'extracts vanity name from URL without www' do
      url = 'https://patreon.com/testcampaign'
      expect(client.send(:extract_vanity_name, url)).to eq('testcampaign')
    end

    it 'extracts vanity name from URL without protocol' do
      url = 'patreon.com/testcampaign'
      expect(client.send(:extract_vanity_name, url)).to eq('testcampaign')
    end

    it 'extracts vanity name from URL with trailing slash' do
      url = 'https://www.patreon.com/testcampaign/'
      expect(client.send(:extract_vanity_name, url)).to eq('testcampaign')
    end

    it 'extracts vanity name from URL with query parameters' do
      url = 'https://www.patreon.com/testcampaign?something=value'
      expect(client.send(:extract_vanity_name, url)).to eq('testcampaign')
    end

    it 'accepts just the vanity name' do
      url = 'testcampaign'
      expect(client.send(:extract_vanity_name, url)).to eq('testcampaign')
    end
  end

  describe '#discover_campaign_id' do
    let(:campaigns_response) do
      {
        'data' => [
          {
            'id' => '9070965',
            'type' => 'campaign',
            'attributes' => {
              'vanity' => 'testcampaign',
              'patron_count' => 150
            }
          },
          {
            'id' => '9999999',
            'type' => 'campaign',
            'attributes' => {
              'vanity' => 'othercampaign',
              'patron_count' => 200
            }
          }
        ]
      }
    end

    before do
      stub_request(:get, /api\.patreon\.com.*\/campaigns/)
        .to_return(status: 200, body: campaigns_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns the matching campaign ID for a given URL' do
      campaign_id = client.discover_campaign_id('patreon.com/testcampaign')
      expect(campaign_id).to eq('9070965')
    end

    it 'returns the correct campaign when multiple exist' do
      campaign_id = client.discover_campaign_id('patreon.com/othercampaign')
      expect(campaign_id).to eq('9999999')
    end

    it 'returns nil when no matching campaign is found' do
      campaign_id = client.discover_campaign_id('patreon.com/nonexistent')
      expect(campaign_id).to be_nil
    end

    it 'returns nil when campaign URL is blank' do
      expect(client.discover_campaign_id('')).to be_nil
      expect(client.discover_campaign_id(nil)).to be_nil
    end

    it 'handles API errors gracefully' do
      stub_request(:get, /api\.patreon\.com.*\/campaigns/)
        .to_return(status: 500, body: '', headers: {})
      
      campaign_id = client.discover_campaign_id('patreon.com/testcampaign')
      expect(campaign_id).to be_nil
    end
  end

  describe '#fetch_all_campaigns' do
    let(:campaigns_response) do
      {
        'data' => [
          {
            'id' => '9070965',
            'type' => 'campaign',
            'attributes' => { 'vanity' => 'testcampaign' }
          }
        ]
      }
    end

    before do
      stub_request(:get, /api\.patreon\.com.*\/campaigns/)
        .to_return(status: 200, body: campaigns_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'fetches all campaigns' do
      campaigns = client.send(:fetch_all_campaigns)
      expect(campaigns).to be_an(Array)
      expect(campaigns.length).to eq(1)
      expect(campaigns.first['id']).to eq('9070965')
    end

    it 'returns empty array on API error' do
      stub_request(:get, /api\.patreon\.com.*\/campaigns/)
        .to_return(status: 401, body: '', headers: {})
      
      campaigns = client.send(:fetch_all_campaigns)
      expect(campaigns).to eq([])
    end
  end
end
