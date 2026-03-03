import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "patreon-donations-admin-nav",

  initialize() {
    withPluginApi("0.8.31", (api) => {
      api.addAdminPluginConfigurationNav("patreon-donations", "patreon_donations.admin.title");
    });
  }
};
