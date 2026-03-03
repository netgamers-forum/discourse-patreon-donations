import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "patreon-stats-navigation",
  
  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    
    if (!siteSettings.patreon_donations_enabled) {
      return;
    }
    
    withPluginApi("0.8.31", (api) => {
      api.addCommunitySectionLink({
        name: "patreon-stats",
        route: "patreon-stats",
        text: "Patreon Statistics",
        title: "View Patreon campaign statistics"
      });
    });
  }
};
