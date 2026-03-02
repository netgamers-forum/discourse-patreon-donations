import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "patreon-stats-link",
  
  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    
    withPluginApi("1.2.0", api => {
      if (!siteSettings.patreon_enabled) {
        return;
      }

      api.addCommunitySectionLink({
        name: "patreon-stats",
        route: "patreon-stats",
        text: "patreon_stats.title",
        title: "patreon_stats.title"
      });
    });
  }
};
