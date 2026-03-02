# frozen_string_literal: true

module DiscoursePatreonDonations
  class Admin::PatreonDonationsController < ::Admin::AdminController
    requires_plugin DiscoursePatreonDonations::PLUGIN_NAME

    def index
      render json: success_json
    end

    def backfill_history
      result = DiscoursePatreonDonations::PatreonMonthlyStat.backfill_historical_data(12)
      
      if result[:success]
        render json: success_json.merge(
          message: result[:message],
          created: result[:created]
        )
      else
        render json: failed_json.merge(error: result[:error]), status: :unprocessable_entity
      end
    end
  end
end
